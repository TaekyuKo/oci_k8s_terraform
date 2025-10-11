#!/bin/bash
set -e

echo "=== Starting Kubernetes Bootstrap ==="

# 0. 호스트 이름 설정 (OCI 메타데이터에서 인스턴스 이름 가져오기)
echo "Setting hostname based on instance display name..."
INSTANCE_DISPLAY_NAME=$(curl -s -H "Authorization: Bearer Oracle" \
  http://169.254.169.254/opc/v2/instance/displayName 2>/dev/null || echo "")

if [ -n "$INSTANCE_DISPLAY_NAME" ]; then
    echo "Instance display name: $INSTANCE_DISPLAY_NAME"
    sudo hostnamectl set-hostname "$INSTANCE_DISPLAY_NAME"
    echo "✓ Hostname set to $INSTANCE_DISPLAY_NAME"
else
    echo "⚠ Warning: Could not fetch instance display name, keeping default hostname"
fi

# 1. iptables-persistent 먼저 설치 (REJECT 규칙 제거 전)
echo "Installing iptables-persistent..."
sudo DEBIAN_FRONTEND=noninteractive apt-get update
sudo DEBIAN_FRONTEND=noninteractive apt-get install -y iptables-persistent

# 2. 기존 REJECT 규칙 제거
echo "Removing default REJECT rules..."

# OCI의 기본 REJECT 규칙을 생성하는 서비스 비활성화
sudo systemctl stop oracle-cloud-agent.service 2>/dev/null || true
sudo systemctl disable oracle-cloud-agent.service 2>/dev/null || true
sudo systemctl stop oracle-cloud-agent-updater 2>/dev/null || true
sudo systemctl disable oracle-cloud-agent-updater 2>/dev/null || true

sudo systemctl mask oracle-cloud-agent.service 2>/dev/null || true
sudo systemctl mask oracle-cloud-agent-updater 2>/dev/null || true

while sudo iptables -C INPUT -j REJECT --reject-with icmp-host-prohibited 2>/dev/null; do
    sudo iptables -D INPUT -j REJECT --reject-with icmp-host-prohibited
done

while sudo iptables -C FORWARD -j REJECT --reject-with icmp-host-prohibited 2>/dev/null; do
    sudo iptables -D FORWARD -j REJECT --reject-with icmp-host-prohibited
done

# OCI 기본 iptables 규칙 파일 백업 및 무력화
if [ -f /etc/iptables/rules.v4 ]; then
    sudo cp /etc/iptables/rules.v4 /etc/iptables/rules.v4.oci.backup
    sudo sed -i '/REJECT.*icmp-host-prohibited/d' /etc/iptables/rules.v4
fi

# 3. iptables 정책 및 규칙 설정
echo "Configuring iptables for Kubernetes..."

# 기본 정책을 ACCEPT로 변경
sudo iptables -P INPUT ACCEPT
sudo iptables -P FORWARD ACCEPT
sudo iptables -P OUTPUT ACCEPT

# 기존 사용자 정의 규칙 플러시
sudo iptables -F INPUT
sudo iptables -F FORWARD

# Loopback 인터페이스 허용 (localhost 통신)
sudo iptables -A INPUT -i lo -j ACCEPT

# 기존 연결 및 관련 트래픽 허용 (이미 수립된 연결 유지)
sudo iptables -A INPUT -m state --state ESTABLISHED,RELATED -j ACCEPT

# VCN 내부 통신 전체 허용 (Kubernetes Pod 간 통신에 필수)
sudo iptables -A INPUT -s 10.0.0.0/16 -j ACCEPT

# SSH 포트 허용 (Security List에서 admin IP만 필터링됨)
sudo iptables -A INPUT -p tcp --dport 22 -j ACCEPT

# Kubernetes API Server 포트 (마스터 노드)
sudo iptables -A INPUT -p tcp --dport 6443 -j ACCEPT

# etcd 서버 포트 (마스터 노드의 데이터베이스)
sudo iptables -A INPUT -p tcp --dport 2379:2380 -j ACCEPT

# Kubelet API 포트 (모든 노드에서 필요)
sudo iptables -A INPUT -p tcp --dport 10250 -j ACCEPT

# Kubernetes NodePort 서비스 범위
sudo iptables -A INPUT -p tcp --dport 30000:32767 -j ACCEPT

# HTTP/HTTPS 포트 (외부 서비스 노출용)
sudo iptables -A INPUT -p tcp --dport 80 -j ACCEPT
sudo iptables -A INPUT -p tcp --dport 443 -j ACCEPT

# CNI 플러그인 통신 포트
sudo iptables -A INPUT -p tcp --dport 179 -j ACCEPT  # BGP (Calico)
sudo iptables -A INPUT -p udp --dport 8472 -j ACCEPT  # VXLAN (Flannel)
sudo iptables -A INPUT -p udp --dport 4789 -j ACCEPT  # VXLAN alternative

# ICMP 허용 (ping 및 네트워크 진단)
sudo iptables -A INPUT -p icmp -j ACCEPT

# iptables 규칙 영구 저장
sudo netfilter-persistent save
# 추가: 재부팅 후에도 OCI 규칙 재주입 방지
sudo systemctl disable iptables-restore 2>/dev/null || true

echo "✓ Kubernetes firewall rules configured and saved."

# 4. Swap 비활성화 (Kubernetes 요구사항)
echo "Disabling swap..."
sudo swapoff -a
# /etc/fstab에서 swap 항목 주석 처리 (재부팅 후에도 유지)
sudo sed -i '/ swap / s/^\(.*\)$/#\1/g' /etc/fstab

# 5. Kernel 모듈 로드 (컨테이너 네트워킹에 필요)
echo "Configuring kernel modules..."
cat <<EOF | sudo tee /etc/modules-load.d/k8s.conf
overlay
br_netfilter
EOF
# overlay: 컨테이너 파일시스템용
sudo modprobe overlay
# br_netfilter: 브리지 네트워크 필터링용
sudo modprobe br_netfilter

# 6. sysctl 파라미터 설정 (네트워크 브리지 및 IP 포워딩)
echo "Configuring sysctl parameters..."
cat <<EOF | sudo tee /etc/sysctl.d/k8s.conf
net.bridge.bridge-nf-call-iptables  = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward                 = 1
EOF
# 설정 즉시 적용
sudo sysctl --system

# 7. containerd 설치 및 설정 (컨테이너 런타임)
echo "Installing containerd..."
sudo apt-get update
sudo apt-get install -y containerd
sudo mkdir -p /etc/containerd
# containerd 기본 설정 생성
containerd config default | sudo tee /etc/containerd/config.toml
# SystemdCgroup 활성화 (Kubernetes 권장 설정)
sudo sed -i 's/SystemdCgroup = false/SystemdCgroup = true/g' /etc/containerd/config.toml
sudo systemctl restart containerd
sudo systemctl enable containerd

# 8. Kubernetes 컴포넌트 설치 (kubeadm, kubelet, kubectl)
echo "Installing Kubernetes components..."
sudo apt-get update
sudo apt-get install -y apt-transport-https ca-certificates curl gpg

# Kubernetes 저장소 GPG 키 추가
sudo mkdir -p /etc/apt/keyrings
curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.31/deb/Release.key | sudo gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg

# Kubernetes 저장소 추가
echo 'deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.31/deb/ /' | sudo tee /etc/apt/sources.list.d/kubernetes.list

sudo apt-get update
sudo apt-get install -y kubelet kubeadm kubectl
# 자동 업데이트 방지 (클러스터 버전 일관성 유지)
sudo apt-mark hold kubelet kubeadm kubectl
sudo systemctl enable kubelet

echo "✓ Kubernetes components installed."

# 9. iSCSI 설치 및 Block Volume 설정
echo "Configuring iSCSI for OCI Block Volumes..."
sudo apt-get install -y open-iscsi lsscsi sg3-utils
sudo systemctl start iscsid
sudo systemctl enable iscsid

# OCI 메타데이터 API URL
METADATA_URL="http://169.254.169.254/opc/v2/instance/"

# Block Volume 연결 대기 (최대 3분)
echo "Waiting for Block Volume attachment..."
MAX_WAIT=180
COUNTER=0

while [ $COUNTER -lt $MAX_WAIT ]; do
    # OCI 메타데이터에서 iSCSI 볼륨 정보 가져오기
    ISCSI_INFO=$(curl -s -H "Authorization: Bearer Oracle" "${METADATA_URL}iscsiVolumeAttachments/" 2>/dev/null || echo "")
    
    # 볼륨이 연결되어 있는지 확인
    if [ -n "$ISCSI_INFO" ] && [ "$ISCSI_INFO" != "[]" ]; then
        echo "Block Volume attachment detected, configuring iSCSI..."
        
        # JSON에서 iSCSI 연결 정보 추출
        IQN=$(echo "$ISCSI_INFO" | grep -oP '"iqn":\s*"\K[^"]+' | head -1)
        IPADDR=$(echo "$ISCSI_INFO" | grep -oP '"ipv4":\s*"\K[^"]+' | head -1)
        PORT=$(echo "$ISCSI_INFO" | grep -oP '"port":\s*\K[0-9]+' | head -1)
        
        if [ -n "$IQN" ] && [ -n "$IPADDR" ]; then
            echo "Connecting to iSCSI target: $IQN at $IPADDR:$PORT"
            
            # iSCSI 타겟 노드 생성
            sudo iscsiadm -m node -o new -T "$IQN" -p "$IPADDR:$PORT"
            # 부팅 시 자동 연결 설정
            sudo iscsiadm -m node -o update -T "$IQN" -n node.startup -v automatic
            # iSCSI 타겟 로그인 (볼륨 연결)
            sudo iscsiadm -m node -T "$IQN" -p "$IPADDR:$PORT" -l
            
            # 디바이스가 나타날 때까지 대기
            echo "Waiting for device to appear..."
            
            # *** Boot Volume 식별 (디바이스 검색 전 먼저 수행) ***
            ROOT_DEVICE=$(lsblk -no PKNAME $(findmnt -n -o SOURCE /) 2>/dev/null || echo "")
            if [ -z "$ROOT_DEVICE" ]; then
                # Fallback: findmnt가 실패하면 df 사용
                ROOT_DEVICE=$(df / | tail -1 | awk '{print $1}' | sed 's/[0-9]*$//' | sed 's|/dev/||')
            fi
            ROOT_DEVICE_PATH="/dev/${ROOT_DEVICE}"
            echo "Identified Boot Volume: $ROOT_DEVICE_PATH"
            
            DEVICE_WAIT=0
            MAX_DEVICE_WAIT=60
            DEVICE=""

            while [ $DEVICE_WAIT -lt $MAX_DEVICE_WAIT ]; do
                # 디스크 타입 디바이스만 필터링 (개선: awk로 한 번에 처리)
                NEW_DEVICES=$(lsblk -d -n -o NAME,TYPE 2>/dev/null | awk '$2=="disk" {print "/dev/"$1}')
    
                for dev in $NEW_DEVICES; do
                    # 루트 디바이스가 아니고 마운트되지 않은 디바이스 찾기
                    if [ "$dev" != "$ROOT_DEVICE_PATH" ] && ! mount | grep -q "^$dev"; then
                        DEVICE=$dev
                        echo "Block device detected: $DEVICE"
                        break 2
                    fi
                done
    
                sleep 3
                DEVICE_WAIT=$((DEVICE_WAIT + 3))
            done

            if [ -z "$DEVICE" ]; then
                echo "⚠ Warning: Block Volume device not detected after ${MAX_DEVICE_WAIT}s"
                
                # 추가 시도: /dev/sd[b-z] 또는 /dev/nvme[1-9]n1 직접 확인
                echo "Attempting to find block device manually..."
                for dev in /dev/sd[b-z] /dev/nvme[1-9]n1; do
                    if [ -e "$dev" ]; then
                        # 디스크 타입만 확인 (파티션 제외)
                        if [ "$(lsblk -no TYPE "$dev" 2>/dev/null)" = "disk" ]; then
                            # 루트 디바이스 제외
                            if [ "$dev" != "$ROOT_DEVICE_PATH" ]; then
                                # 이미 마운트되어 있는지 확인
                                if ! mount | grep -q "^$dev"; then
                                    DEVICE=$dev
                                    echo "Found available block device: $DEVICE"
                                    break
                                fi
                            fi
                        fi
                    fi
                done
            fi
            
            if [ -n "$DEVICE" ] && [ -e "$DEVICE" ]; then
                MOUNT_POINT="/data"
                
                echo "Configuring Block Volume: $DEVICE"
                
                # 기존 파일시스템 확인
                if ! sudo blkid "$DEVICE" | grep -q "TYPE"; then
                    echo "Creating ext4 filesystem on $DEVICE..."
                    sudo mkfs.ext4 -F "$DEVICE"
                else
                    echo "Filesystem already exists on $DEVICE"
                fi
                
                # 마운트 포인트 생성
                sudo mkdir -p "$MOUNT_POINT"
                
                # UUID 추출 (디바이스 경로 변경 대비)
                UUID=$(sudo blkid -s UUID -o value "$DEVICE")
                
                # /etc/fstab에 자동 마운트 설정 추가
                if ! grep -q "$UUID" /etc/fstab 2>/dev/null; then
                    # nofail: 볼륨이 없어도 부팅 가능
                    # _netdev: 네트워크 디바이스 (iSCSI)
                    echo "UUID=$UUID $MOUNT_POINT ext4 defaults,nofail,_netdev 0 2" | sudo tee -a /etc/fstab
                fi
                
                # 마운트 실행
                sudo mount -a
                # ubuntu 사용자에게 권한 부여
                sudo chown -R ubuntu:ubuntu "$MOUNT_POINT"
                
                echo "✓ Block Volume successfully mounted at $MOUNT_POINT"
                df -h "$MOUNT_POINT"
                
                break
            else
                echo "⚠ Warning: Could not identify Block Volume device"
            fi
        fi
    fi
    
    sleep 5
    COUNTER=$((COUNTER + 5))
    echo "Waiting... ($COUNTER/$MAX_WAIT seconds)"
done

if [ $COUNTER -ge $MAX_WAIT ]; then
    echo "⚠ Warning: Block Volume attachment timeout. Manual configuration may be required."
    echo "Available devices:"
    lsblk -o NAME,SIZE,TYPE,MOUNTPOINT
fi

# 10. 시스템 검증 스크립트 설치
cat <<'VERIFY_EOF' | sudo tee /usr/local/bin/verify-k8s-setup.sh
#!/bin/bash
echo "=== Kubernetes Setup Verification ==="
echo ""
echo "1. Hostname:"
hostname
echo ""
echo "2. Swap Status (should show 0B):"
free -h | grep Swap
echo ""
echo "3. Kernel Modules (should show overlay and br_netfilter):"
lsmod | grep -E "overlay|br_netfilter"
echo ""
echo "4. IP Forwarding (should be 1):"
sysctl net.ipv4.ip_forward
echo ""
echo "5. Containerd Status (should be active):"
systemctl is-active containerd
echo ""
echo "6. Kubelet Status:"
systemctl is-active kubelet || echo "Not started (expected before kubeadm init/join)"
echo ""
echo "7. Block Volume Mount:"
df -h | grep /data || echo "⚠ Block volume not mounted"
echo ""
echo "8. iSCSI Sessions:"
sudo iscsiadm -m session 2>/dev/null || echo "No active iSCSI sessions"
echo ""
echo "9. iptables Rules (first 20 lines):"
sudo iptables -L INPUT -n --line-numbers | head -20
echo ""
echo "10. Network Interfaces:"
ip -br addr
echo ""
echo "=== Verification Complete ==="
VERIFY_EOF

sudo chmod +x /usr/local/bin/verify-k8s-setup.sh

echo ""
echo "=== Bootstrap Complete ==="
echo "Run 'sudo /usr/local/bin/verify-k8s-setup.sh' to verify the setup."
echo ""
echo "Next steps:"
echo "  Master node: Initialize cluster with kubeadm init"
echo "  Worker node: Join cluster with kubeadm join command from master"