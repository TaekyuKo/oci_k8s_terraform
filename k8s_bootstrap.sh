set -eo pipefail

echo "=== Starting Kubernetes Bootstrap ==="
exec > >(tee -a /var/log/k8s-bootstrap.log) 2>&1
echo "Bootstrap started at: $(date)"

echo "Setting hostname..."
INSTANCE_DISPLAY_NAME=$(curl -s -H "Authorization: Bearer Oracle" \
  http://169.254.169.254/opc/v2/instance/displayName 2>/dev/null || echo "")

if [ -n "$INSTANCE_DISPLAY_NAME" ]; then
    echo "Instance display name: $INSTANCE_DISPLAY_NAME"
    sudo hostnamectl set-hostname "$INSTANCE_DISPLAY_NAME"
    echo "✓ Hostname set to $INSTANCE_DISPLAY_NAME"
else
    echo "⚠ Warning: Could not fetch instance display name, keeping default hostname"
fi

echo "Waiting for APT lock..."
while sudo fuser /var/lib/dpkg/lock-frontend >/dev/null 2>&1 || sudo fuser /var/lib/apt/lists/lock >/dev/null 2>&1; do
    echo "  ... waiting for other APT processes to finish"
    sleep 5
done

echo "Installing iptables-persistent and jq..."
sudo DEBIAN_FRONTEND=noninteractive apt-get update -qq
sudo DEBIAN_FRONTEND=noninteractive apt-get install -y iptables-persistent jq curl

echo "Removing default REJECT rules..."
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
if [ -f /etc/iptables/rules.v4 ]; then
    sudo cp /etc/iptables/rules.v4 /etc/iptables/rules.v4.oci.backup
    sudo sed -i '/REJECT.*icmp-host-prohibited/d' /etc/iptables/rules.v4
fi

echo "Configuring iptables..."

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
sudo sed -i '/ swap / s/^\(.*\)$/#\1/g' /etc/fstab

echo "Configuring kernel modules..."
cat <<EOF | sudo tee /etc/modules-load.d/k8s.conf
overlay
br_netfilter
EOF
sudo modprobe overlay
sudo modprobe br_netfilter

echo "Configuring sysctl..."
cat <<EOF | sudo tee /etc/sysctl.d/k8s.conf
net.bridge.bridge-nf-call-iptables  = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward                 = 1
EOF
sudo sysctl --system

echo "Installing containerd..."
sudo apt-get install -y containerd

sudo mkdir -p /etc/containerd

if [ -f /etc/containerd/config.toml ]; then
    sudo cp /etc/containerd/config.toml /etc/containerd/config.toml.backup
fi

containerd config default | sudo tee /etc/containerd/config.toml > /dev/null
sudo sed -i 's/SystemdCgroup = false/SystemdCgroup = true/g' /etc/containerd/config.toml
sudo systemctl restart containerd
sudo systemctl enable containerd

# containerd 시작 대기 (최대 30초)
echo "Waiting for containerd to be ready..."
CONTAINERD_READY=false
for i in {1..30}; do
    if sudo systemctl is-active --quiet containerd; then
        CONTAINERD_READY=true
        break
    fi
    sleep 1
done

if [ "$CONTAINERD_READY" = false ]; then
    echo "⚠ Warning: containerd failed to start"
    sudo systemctl status containerd
    exit 1
fi

echo "✓ containerd ready"

echo "Installing Kubernetes..."
sudo apt-get install -y apt-transport-https ca-certificates curl gpg conntrack

sudo mkdir -p /etc/apt/keyrings
sudo rm -f /etc/apt/keyrings/kubernetes-apt-keyring.gpg
curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.31/deb/Release.key | sudo gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
echo 'deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.31/deb/ /' | sudo tee /etc/apt/sources.list.d/kubernetes.list

sudo apt-get update -qq
sudo apt-get install -y kubelet kubeadm kubectl

# 자동 업데이트 방지 (클러스터 버전 일관성 유지)
sudo apt-mark hold kubelet kubeadm kubectl
sudo systemctl enable kubelet

echo "✓ Kubernetes components installed."

# 9. iSCSI 설치 (Block Volume 연결을 위한 준비만 수행)
echo "Installing iSCSI tools for Block Volume support..."
sudo apt-get install -y open-iscsi lsscsi sg3-utils
sudo systemctl start iscsid
sudo systemctl enable iscsid
echo "✓ iSCSI tools installed."

# 10. 시스템 검증 스크립트
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
echo "7. iSCSI Service:"
systemctl is-active iscsid
echo ""
echo "8. iptables Rules (first 20 lines):"
sudo iptables -L INPUT -n --line-numbers | head -20
echo ""
echo "9. Network Interfaces:"
ip -br addr
echo ""
echo "=== Verification Complete ==="
VERIFY_EOF

sudo chmod +x /usr/local/bin/verify-k8s-setup.sh

echo ""
echo "=== Bootstrap Complete ==="
echo "Bootstrap finished at: $(date)"
echo "Log file: /var/log/k8s-bootstrap.log"
echo ""
echo "Run 'sudo /usr/local/bin/verify-k8s-setup.sh' to verify the setup."
echo ""
echo "Next steps:"
echo "  Master node: Initialize cluster with kubeadm init"
echo "  Worker node: Join cluster with kubeadm join command from master"