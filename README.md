# OCI 프리티어 Kubernetes 클러스터 자동화

Oracle Cloud Infrastructure (OCI) 프리티어를 활용한 Kubernetes 클러스터 자동 배포 프로젝트입니다.

## 📋 프로젝트 개요

이 프로젝트는 Terraform을 사용하여 OCI 프리티어 환경에서 다음을 자동으로 구성합니다:

- **네트워크**: VCN, Public Subnet, Internet Gateway
- **보안**: Security List (Kubernetes 전용 포트 구성)
- **컴퓨트**: Master 노드 (Reserved Public IP), Worker 노드 (Ephemeral Public IP)
- **스토리지**: 각 노드에 50GB Block Volume 자동 마운트 (`/data`)
- **Kubernetes**: containerd, kubeadm, kubelet, kubectl 자동 설치

## 🎯 주요 특징

- ✅ **완전 무료**: 프리티어 한도 내 과금 $0
- ✅ **Master 고정 IP**: Reserved Public IP로 재부팅 후에도 동일 IP 유지
- ✅ **자동화**: Terraform + Cloud-Init으로 원클릭 배포
- ✅ **학습용 최적화**: 복잡한 네트워크 없이 Kubernetes 학습에 집중

## 🚀 빠른 시작

### 1단계: 사전 준비

#### 필수 소프트웨어
```bash
# Terraform 설치 확인
terraform version  # 최소 v1.0 이상 필요
```

#### OCI 계정 준비
1. [OCI 콘솔](https://cloud.oracle.com)에 로그인
2. **프리티어 활성화 확인** (Always Free Resources)
3. **API Key 생성**:
   - User Settings → API Keys → Add API Key
   - Private Key 다운로드 (예: `~/.oci/oci_api_key.pem`)
   - Configuration File Preview의 정보 복사

### 2단계: 변수 설정

`terraform.tfvars` 파일을 생성하고 본인의 OCI 정보를 입력:

```hcl
# OCI 인증 정보 (API Key 생성 시 받은 정보)
tenancy_ocid     = "ocid1.tenancy.oc1..aaaaaaaxxxxx"
user_ocid        = "ocid1.user.oc1..aaaaaaaxxxxx"
fingerprint      = "aa:bb:cc:dd:ee:ff:00:11:22:33:44:55:66:77:88:99"
private_key_path = "~/.oci/oci_api_key.pem"
region           = "ap-seoul-1"  # 본인의 Home Region

# Compartment (루트 compartment 사용 시 tenancy_ocid와 동일)
compartment_ocid = "ocid1.compartment.oc1..aaaaaaaxxxxx"

# SSH 공개키 (본인의 SSH 공개키)
ssh_public_key   = "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQ..."

# 관리자 공인 IP (본인의 IP만 SSH/API 접근 가능하도록 제한)
admin_ip_cidr    = "123.45.67.89/32"  # https://ipinfo.io 에서 확인
```

#### 중요 참고사항
- **admin_ip_cidr**: 본인의 공인 IP로 설정 (보안 권장, 학습용이면 `0.0.0.0/0`도 가능)
- **region**: 프리티어는 Home Region에서만 사용 가능
- **ssh_public_key**: `~/.ssh/id_rsa.pub` 내용 복사 (없으면 `ssh-keygen`으로 생성)

### 3단계: Terraform 배포

```bash
# 초기화 (최초 1회)
terraform init

# 배포 계획 확인 (예상 리소스 확인)
terraform plan

# 배포 실행
terraform apply
# "yes" 입력하여 승인
```

**배포 시간**: 약 5-10분 소요

배포 완료 후 다음 정보가 출력됩니다:
```
Outputs:

master_node_public_ip = "132.145.xxx.xxx"  (Reserved IP - 재부팅 후에도 유지)
master_node_private_ip = "10.0.1.2"
worker_node_public_ip = "138.2.xxx.xxx"  (Ephemeral IP - 재부팅 시 변경 가능)
worker_node_private_ip = "10.0.1.3"
ssh_connection_commands = <<EOT
    # Master 노드 직접 접속 (Reserved IP)
    ssh ubuntu@132.145.xxx.xxx
    
    # Worker 노드 직접 접속 (Ephemeral IP)
    ssh ubuntu@138.2.xxx.xxx
EOT
```

### 4단계: 노드 접속 및 검증

#### 4-1. Master 노드 접속
```bash
# 출력된 Reserved Public IP로 접속
ssh ubuntu@<master_node_public_ip>
```

#### 4-2. 부트스트랩 검증
```bash
# 자동 설치 상태 확인 (약 5-10분 대기 후)
sudo /usr/local/bin/verify-k8s-setup.sh
```

**확인할 항목**:
- ✅ Swap: 0B (비활성화됨)
- ✅ Containerd: active
- ✅ Block Volume: `/data`에 마운트됨
- ✅ IP Forwarding: 1
- ✅ iptables: VCN 내부 통신 허용

**참고**: 인스턴스 생성 직후에는 부트스트랩이 실행 중일 수 있습니다. 5-10분 후 확인하세요.

### 5단계: Kubernetes 클러스터 초기화 (Master 노드)

```bash
# Master 노드 Private IP 확인
MASTER_IP=$(hostname -I | awk '{print $1}')
echo $MASTER_IP  # 예: 10.0.1.2

# Kubeadm 초기화
sudo kubeadm init \
  --pod-network-cidr=192.168.0.0/16 \
  --apiserver-advertise-address=$MASTER_IP \
  --control-plane-endpoint=$MASTER_IP

# kubectl 설정 (출력된 명령어 또는 아래 실행)
mkdir -p $HOME/.kube
sudo cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
sudo chown $(id -u):$(id -g) $HOME/.kube/config

# Calico CNI 설치 (Pod 네트워크 활성화)
kubectl apply -f https://raw.githubusercontent.com/projectcalico/calico/v3.26.1/manifests/calico.yaml

# 클러스터 상태 확인 (약 1-2분 후 Ready)
kubectl get nodes
kubectl get pods -A
```

### 6단계: Worker 노드 조인

#### 6-1. Join 명령어 생성 (Master 노드에서)
```bash
# Worker 노드가 클러스터에 조인할 때 사용할 명령어 생성
kubeadm token create --print-join-command

# 출력 예시 (이 명령어를 복사해두세요):
# kubeadm join 10.0.1.2:6443 --token abcdef.0123456789abcdef \
#   --discovery-token-ca-cert-hash sha256:1234567890abcdef...
```

#### 6-2. Worker 노드 접속
```bash
# 새 터미널에서 Worker 노드 직접 접속 (Ephemeral IP 사용)
ssh ubuntu@<worker_node_public_ip>

# 또는 Master에서 SSH (Private IP 사용 - 추천)
ssh ubuntu@<worker_node_private_ip>
```

**참고**: Worker의 Ephemeral IP는 재부팅 시 변경될 수 있으므로, Master에서 Private IP로 접속하는 것을 권장합니다.

#### 6-3. Worker 노드 검증
```bash
# 부트스트랩 확인
sudo /usr/local/bin/verify-k8s-setup.sh
```

#### 6-4. 클러스터 조인 (Worker 노드에서)
```bash
# Master에서 생성한 join 명령어 실행 (sudo 필수)
sudo kubeadm join 10.0.1.2:6443 --token <token> \
  --discovery-token-ca-cert-hash sha256:<hash>

# 성공 메시지:
# This node has joined the cluster:
# * Certificate signing request was sent to apiserver and a response was received.
# * The Kubelet was informed of the new secure connection details.
```

#### 6-5. Master에서 노드 확인
```bash
# Master 노드로 돌아가기
exit

# 클러스터에 Worker가 추가되었는지 확인
kubectl get nodes

# 출력 예시:
# NAME         STATUS   ROLES           AGE   VERSION
# k8s-master   Ready    control-plane   5m    v1.31.x
# k8s-worker   Ready    <none>          1m    v1.31.x
```

### 7단계: 샘플 애플리케이션 배포

```bash
# Nginx 배포
kubectl create deployment nginx --image=nginx
kubectl expose deployment nginx --port=80 --type=NodePort

# 서비스 확인
kubectl get svc nginx

# 출력 예시:
# NAME    TYPE       CLUSTER-IP      EXTERNAL-IP   PORT(S)        AGE
# nginx   NodePort   10.96.123.45    <none>        80:31234/TCP   10s

# Master 노드의 Reserved Public IP로 접근 (브라우저 또는 curl)
curl http://<master_public_ip>:31234

# Worker 노드의 Ephemeral Public IP로도 접근 가능
curl http://<worker_public_ip>:31234
```

## 📊 프리티어 리소스 사용량

| 리소스 | 이 프로젝트 사용량 | 프리티어 한도 |
|--------|-------------------|--------------|
| **Compute (OCPU)** | 4 OCPU (2 인스턴스 × 2 OCPU) | 4 OCPU |
| **Memory** | 24GB (2 인스턴스 × 12GB) | 24GB |
| **Block Volume** | 100GB (2개 × 50GB) | 200GB |
| **Boot Volume** | 100GB (2개 × 50GB) | 별도 계산 |
| **Reserved Public IP** | 1개 (Master 노드) | 1개 |
| **Ephemeral Public IP** | 1개 (Worker 노드) | 무제한 |
| **VCN** | 1개 | 2개 |
| **Outbound 데이터 전송** | 사용량에 따라 | 10TB/월 |

**💰 총 비용**: **$0/월** (100% 프리티어 범위 내)

## 🏗️ 네트워크 아키텍처

```
인터넷
  ↕
Internet Gateway (무료)
  ↕
Public Subnet (10.0.1.0/24)
  ├─ k8s-master (10.0.1.x) + Reserved Public IP (고정)
  │   └─ Block Volume 50GB → /data
  │
  └─ k8s-worker (10.0.1.x) + Ephemeral Public IP (임시)
      └─ Block Volume 50GB → /data
```

### IP 할당 전략
- **Master 노드**: Reserved Public IP 사용
  - ✅ 재부팅 후에도 동일 IP 유지
  - ✅ 안정적인 API Server 접근
  - ✅ 프리티어 한도: 1개 (1개 사용)
  
- **Worker 노드**: Ephemeral Public IP 사용
  - ✅ 재부팅 시 IP 변경 가능 (문제 없음)
  - ✅ 무제한 무료
  - ✅ 스케일링 유연성

### 특징
- ✅ NAT Gateway 없음 → 과금 $0
- ✅ Security List로 보안 제어 (admin IP만 SSH/API 접근)
- ✅ VCN 내부(10.0.0.0/16) 통신 전체 허용 → Pod 간 통신 원활
- ✅ Master는 고정 IP, Worker는 Private IP로 통신

## 🔧 커스터마이징

### 인스턴스 사양 변경

`terraform.tfvars`에 다음 변수 추가:

```hcl
# 기본값: 2 OCPU, 12GB RAM (각 노드)
instance_ocpus  = 1   # 1~4 OCPU
instance_memory = 6   # OCPU당 1~24GB (최소 OCPU × 1GB)
```

**예시**:
- **최소**: 1 OCPU, 6GB → 총 2 OCPU, 12GB (4개 노드 가능)
- **최대**: 2 OCPU, 12GB → 총 4 OCPU, 24GB (2개 노드)

### Worker 노드 추가

Worker 노드는 Ephemeral IP를 사용하므로 개수 제한 없이 추가할 수 있습니다 (OCPU/메모리 한도 내에서).

`main.tf`에서 Worker 노드 블록을 복사하여 추가:

```hcl
# Worker 2 추가
resource "oci_core_instance" "k8s_worker2" {
  availability_domain = data.oci_identity_availability_domains.ads.availability_domains[0].name
  compartment_id      = var.compartment_ocid
  display_name        = "k8s-worker2"
  shape               = var.instance_shape
  
  shape_config {
    ocpus         = var.instance_ocpus
    memory_in_gbs = var.instance_memory
  }
  
  create_vnic_details {
    subnet_id                 = oci_core_subnet.public_subnet.id
    assign_public_ip          = true  # Ephemeral IP
    assign_private_dns_record = true
    skip_source_dest_check    = true
  }
  
  source_details {
    source_type             = "image"
    source_id               = data.oci_core_images.ubuntu_image.images[0].id
    boot_volume_size_in_gbs = 50
  }
  
  metadata = {
    ssh_authorized_keys = var.ssh_public_key
    user_data           = base64encode(file("${path.module}/k8s_bootstrap.sh"))
  }
  
  timeouts {
    create = "30m"
    delete = "30m"
  }
}

# Worker 2 Block Volume
resource "oci_core_volume" "worker2_bv" {
  availability_domain = data.oci_identity_availability_domains.ads.availability_domains[0].name
  compartment_id      = var.compartment_ocid
  display_name        = "k8s-worker2-bv"
  size_in_gbs         = 50
}

resource "oci_core_volume_attachment" "worker2_bv_attachment" {
  attachment_type = "iscsi"
  instance_id     = oci_core_instance.k8s_worker2.id
  volume_id       = oci_core_volume.worker2_bv.id
  display_name    = "k8s-worker2-bv-attachment"
  
  is_pv_encryption_in_transit_enabled = false
  is_read_only                        = false
  use_chap                            = false
}
```

`outputs.tf`에도 추가:
```hcl
output "worker2_node_public_ip" {
  value = oci_core_instance.k8s_worker2.public_ip
}

output "worker2_node_private_ip" {
  value = oci_core_instance.k8s_worker2.private_ip
}
```

**참고**: 프리티어는 총 4 OCPU, 24GB RAM까지 무료이므로 1 OCPU, 6GB 사양으로 변경 시 최대 4개 노드 구성 가능합니다.

### 다른 CNI 플러그인 사용

**Flannel**:
```bash
kubectl apply -f https://github.com/flannel-io/flannel/releases/latest/download/kube-flannel.yml
```

**Weave Net**:
```bash
kubectl apply -f https://github.com/weaveworks/weave/releases/download/v2.8.1/weave-daemonset-k8s.yaml
```

## 🧹 리소스 정리

```bash
# 모든 리소스 삭제
terraform destroy
# "yes" 입력하여 승인

# 삭제 확인
terraform show
# 출력이 비어있으면 모든 리소스 삭제 완료
```

**주의**: 
- Block Volume의 데이터는 영구적으로 삭제됩니다. 필요한 데이터는 미리 백업하세요.
- Reserved Public IP도 함께 삭제됩니다.

## 📚 참고 문서

- [OCI 프리티어 공식 문서](https://docs.oracle.com/en-us/iaas/Content/FreeTier/freetier.htm)
- [OCI Terraform Provider](https://registry.terraform.io/providers/oracle/oci/latest/docs)
- [Kubernetes 공식 문서](https://kubernetes.io/docs/home/)
- [Calico 네트워킹](https://docs.tigera.io/calico/latest/about/)
- [Kubeadm 클러스터 생성](https://kubernetes.io/docs/setup/production-environment/tools/kubeadm/create-cluster-kubeadm/)

## ⚠️ 주의사항

1. **프리티어 한도**: 이 프로젝트는 프리티어 OCPU/메모리를 100% 사용합니다. 추가 인스턴스 생성 시 과금됩니다.
2. **Reserved IP 한도**: Master 노드에 1개 사용 (프리티어 한도: 2개). 추가 Reserved IP 필요 시 1개 더 생성 가능합니다.
3. **Worker IP 변경**: Worker 노드의 Ephemeral IP는 재부팅 시 변경될 수 있습니다. Master에서 Private IP로 접속하세요.
4. **보안**: `admin_ip_cidr`를 본인의 IP로 제한하는 것을 권장합니다. 학습용이라면 `0.0.0.0/0`도 가능하지만 보안에 주의하세요.
5. **Region**: 프리티어는 Home Region에서만 사용 가능합니다.
6. **데이터 백업**: `terraform destroy` 시 Block Volume과 Reserved IP도 함께 삭제됩니다.
7. **비용**: 프리티어 범위 내에서만 사용하면 완전 무료입니다.
8. **부트스트랩 시간**: 인스턴스 생성 후 5-10분간 자동 설치가 진행됩니다. 바로 접속해도 설치가 완료되지 않았을 수 있습니다.