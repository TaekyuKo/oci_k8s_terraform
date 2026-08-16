[English](README.md) | [한국어](README.ko.md)

# OCI 프리티어 Kubernetes 클러스터 자동화

[![Terraform](https://img.shields.io/badge/Terraform-%3E%3D1.0-blue?logo=terraform)](https://www.terraform.io/)
[![OCI](https://img.shields.io/badge/OCI-Free%20Tier-red?logo=oracle)](https://www.oracle.com/cloud/free/)
[![Kubernetes](https://img.shields.io/badge/Kubernetes-v1.31-326CE5?logo=kubernetes)](https://kubernetes.io/)
[![License](https://img.shields.io/badge/License-MIT-green.svg)](LICENSE)

Oracle Cloud Infrastructure (OCI) 프리티어를 활용한 Kubernetes 클러스터 자동 배포 프로젝트입니다.

## 📋 프로젝트 개요

이 프로젝트는 Terraform을 사용하여 OCI 프리티어 환경에서 다음을 자동으로 구성합니다:

- **네트워크**: VCN, Public Subnet, Internet Gateway
- **보안**: Security List (Kubernetes 전용 포트 구성)
- **컴퓨트**: Master 노드 (Reserved Public IP), Worker 노드 (Ephemeral Public IP)
- **스토리지**: 각 노드에 50GB Block Volume 연결 (수동 마운트)
- **Kubernetes**: containerd, kubeadm, kubelet, kubectl 자동 설치

## 🎯 주요 특징

- ✅ **완전 무료**: Oracle Cloud Infrastructure (OCI) 프리티어 한도 내 과금 $0
- ✅ **Master 고정 IP**: Reserved Public IP로 재부팅 후에도 동일 IP 유지
- ✅ **자동화**: Terraform + Cloud-Init으로 원클릭 배포
- ✅ **학습용 최적화**: 복잡한 네트워크 없이 Kubernetes 학습에 집중
- ✅ **ARM 아키텍처**: Ampere A1 프로세서 사용 (VM.Standard.A1.Flex)

## 📁 파일 구조

```
oci_k8s_terraform/
├── provider.tf         # OCI Provider 설정 및 인증
├── variables.tf        # 입력 변수 정의
├── main.tf             # 메인 리소스 (VCN, 인스턴스, 볼륨 등)
├── outputs.tf          # 출력값 정의 (IP 주소 등)
├── k8s_bootstrap.sh    # Cloud-Init 스크립트 (K8s 자동 설치)
├── terraform.tfvars    # 변수 값 설정 (직접 생성 필요, .gitignore됨)
├── .gitignore          # Git 제외 파일 목록
└── README.md           # 프로젝트 문서
```

## 🚀 빠른 시작

### 1단계: 사전 준비

#### 필수 소프트웨어
```bash
# Terraform 설치 확인
terraform version  # 최소 v1.0 이상 필요
```

#### OCI 계정 준비

**1. OCI 계정 및 프리티어 확인**
- [OCI 콘솔](https://cloud.oracle.com)에 로그인
- 프리티어 활성화 확인 (Always Free Resources)

**2. API Key 생성 (Terraform이 OCI와 통신하기 위한 인증키)**

OCI 콘솔에서:
1. 우측 상단 프로필 아이콘 클릭 → **User Settings**
2. 왼쪽 메뉴 **API Keys** → **Add API Key** 클릭
3. **Generate API Key Pair** 선택
4. **Download Private Key** 클릭 → 파일 저장 (예: `oci_api_key.pem`)
   - Windows: `C:\Users\<username>\.oci\oci_api_key.pem`
   - Linux/Mac: `~/.oci/oci_api_key.pem`
5. **Add** 클릭
6. **Configuration File Preview** 창에서 다음 정보 복사:
   - `tenancy` (tenancy_ocid)
   - `user` (user_ocid)
   - `fingerprint`
   - `region`

**3. SSH Key 준비 (생성된 인스턴스에 접속하기 위한 키)**

**방법 1: OCI 콘솔에서 생성 (가장 간단)**
1. OCI 콘솔 → **Compute** → **Instances**
2. **Create Instance** 페이지로 이동 (실제로 생성하지 않아도 됨)
3. **Add SSH keys** 섹션에서 **Generate a key pair for me** 선택
4. **Save Private Key** 클릭 → 프라이빗 키 저장 (예: `ssh-key-2025-12-01.key`)
5. **Save Public Key** 클릭 → 퍼블릭 키 저장 (예: `ssh-key-2025-12-01.key.pub`)
6. 퍼블릭 키 파일을 텍스트 에디터로 열어서 내용 전체 복사 (`ssh-rsa AAAA...`로 시작)

**방법 2: 로컬에서 직접 생성**

이미 SSH 키가 있다면 이 단계를 건너뛰세요.

**Windows (PowerShell):**
```powershell
# SSH 키 생성
ssh-keygen -t rsa -b 2048 -f $env:USERPROFILE\.ssh\id_rsa

# 공개키 확인
cat $env:USERPROFILE\.ssh\id_rsa.pub
```

**Linux/Mac:**
```bash
# SSH 키 생성
ssh-keygen -t rsa -b 2048 -f ~/.ssh/id_rsa

# 공개키 확인
cat ~/.ssh/id_rsa.pub
```

출력되는 `ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQ...` 전체를 복사하세요.

### 2단계: 변수 설정

프로젝트 디렉토리에 `terraform.tfvars` 파일을 생성하고 위에서 준비한 정보를 입력합니다.

**파일 생성:**
```bash
# 프로젝트 디렉토리로 이동
cd oci_k8s_terraform

# terraform.tfvars 파일 생성 (텍스트 에디터로)
notepad terraform.tfvars  # Windows
# 또는
nano terraform.tfvars     # Linux/Mac
```

**파일 내용:**
```hcl
# ========================================
# OCI 인증 정보
# ========================================

# OCI API Key 생성 시 받은 정보 (Configuration File Preview에서 복사)
tenancy_ocid     = "ocid1.tenancy.oc1..aaaaaaaxxxxx"     # tenancy 값
user_ocid        = "ocid1.user.oc1..aaaaaaaxxxxx"        # user 값
fingerprint      = "aa:bb:cc:dd:ee:ff:00:11:22:33:44:55:66:77:88:99"  # fingerprint 값
region           = "ap-seoul-1"  # region 값 (본인의 Home Region)

# API Private Key 파일 경로 (다운로드한 oci_api_key.pem 파일 경로)
private_key_path = "C:/Users/YourName/.oci/oci_api_key.pem"  # Windows 예시
# private_key_path = "~/.oci/oci_api_key.pem"  # Linux/Mac 예시

# ========================================
# 리소스 설정
# ========================================

# Compartment OCID (루트 compartment 사용 시 tenancy_ocid와 동일)
compartment_ocid = "ocid1.compartment.oc1..aaaaaaaxxxxx"  # 또는 tenancy_ocid와 동일

# ========================================
# SSH 접속 키
# ========================================

# SSH 공개키 (위에서 생성한 id_rsa.pub 파일 내용 전체를 붙여넣기)
ssh_public_key   = "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQ..."
```

**각 항목 설명:**

| 항목 | 설명 | 어디서 가져오나요? |
|------|------|-------------------|
| `tenancy_ocid` | OCI 테넌시 ID | API Key 생성 시 Configuration File Preview |
| `user_ocid` | 사용자 ID | API Key 생성 시 Configuration File Preview |
| `fingerprint` | API Key 지문 | API Key 생성 시 Configuration File Preview |
| `region` | 리전 | API Key 생성 시 Configuration File Preview (예: ap-seoul-1) |
| `private_key_path` | API 프라이빗 키 경로 | 다운로드한 `oci_api_key.pem` 파일의 **절대 경로** |
| `compartment_ocid` | 구획 ID | tenancy_ocid와 동일하게 입력 (루트 사용 시) |
| `ssh_public_key` | SSH 공개키 | `cat ~/.ssh/id_rsa.pub` 명령어로 출력된 전체 내용 |

**주의사항:**
- Windows에서 경로 입력 시 `/` 또는 `\\` 사용 (예: `C:/Users/...` 또는 `C:\\Users\\...`)
- `ssh_public_key`는 `ssh-rsa AAAA...`로 시작하는 한 줄 전체를 복사해야 합니다
- 모든 OCID는 따옴표로 감싸야 합니다

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
# SSH로 접속 (다운로드한 SSH 프라이빗 키 사용)
ssh -i /path/to/ssh-private-key ubuntu@<master_node_public_ip>

# 예시:
# OCI 콘솔에서 다운로드한 키 사용 시
ssh -i ~/Downloads/ssh-key-2025-12-01.key ubuntu@132.145.xxx.xxx

# 로컬에서 생성한 키 사용 시
ssh -i ~/.ssh/id_rsa ubuntu@132.145.xxx.xxx
```

**참고:** 
- 기본 사용자명은 `ubuntu` (Ubuntu 이미지 기본 계정)
- SSH 키 권한 오류 시: `chmod 600 /path/to/ssh-private-key`

#### 4-2. 부트스트랩 검증
```bash
# 자동 설치 상태 확인 (약 5-10분 대기 후)
sudo /usr/local/bin/verify-k8s-setup.sh
```

**확인할 항목**:
- ✅ Swap: 0B (비활성화됨)
- ✅ Containerd: active
- ✅ iSCSI: active (Block Volume 연결 준비)
- ✅ IP Forwarding: 1
- ✅ iptables: VCN 내부 통신 허용

**참고**: 인스턴스 생성 직후에는 부트스트랩이 실행 중일 수 있습니다. 5-10분 후 확인하세요.

#### 4-3. Block Volume 연결 (선택사항)

추가 스토리지가 필요한 경우 Block Volume을 연결할 수 있습니다.

**연결 방법:**
1. OCI 콘솔 → Compute → Instances → 해당 인스턴스 클릭
2. Resources → Attached Block Volumes 클릭
3. Block Volume 클릭 → "iSCSI Commands and Information" 탭
4. 표시된 **iSCSI 명령어 3개**를 복사하여 인스턴스에서 실행

**명령어 예시** (실제 값은 OCI 콘솔에서 각 노드마다 확인):
```bash
sudo iscsiadm -m node -o new -T iqn.2015-12.com.oracleiaas:xxxxxx -p xxx.xxx.x.x:3260
sudo iscsiadm -m node -o update -T iqn.2015-12.com.oracleiaas:xxxxxx -n node.startup -v automatic
sudo iscsiadm -m node -T iqn.2015-12.com.oracleiaas:xxxxxx -p xxx.xxx.x.x:3260 -l
```

**디스크 포맷 및 마운트** (처음 1회만):
```bash
# 연결된 디바이스 확인
lsblk

# 파일시스템 생성 (디바이스명은 lsblk에서 확인)
sudo mkfs.ext4 /dev/sdb

# 마운트
sudo mkdir -p /data
sudo mount /dev/sdb /data

# 재부팅 후 자동 마운트
UUID=$(sudo blkid -s UUID -o value /dev/sdb)
echo "UUID=$UUID /data ext4 defaults,nofail,_netdev 0 2" | sudo tee -a /etc/fstab
```

**참고**: Block Volume이 필요없다면 이 단계를 건너뛰어도 됩니다.

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
kubectl apply -f https://raw.githubusercontent.com/projectcalico/calico/v3.28.0/manifests/calico.yaml

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
| **Block Volume** | 100GB (2개 × 50GB) | 100GB |
| **Boot Volume** | 100GB (2개 × 50GB) | 100GB |
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

### IP 할당
- **Master 노드**: Reserved Public IP 사용
- **Worker 노드**: Ephemeral Public IP 사용

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
    assign_public_ip          = true
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
  device          = "/dev/oracleoci/oraclevdd"
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

### 다른 CNI 플러그인 사용

> ⚠️ **주의**: CNI는 하나만 설치해야 합니다. Calico 대신 다른 CNI를 사용하려면 `kubeadm init` 후 Calico 대신 아래 중 하나를 설치하세요.

**Flannel** (가장 단순):
```bash
# Flannel 설치 (pod-network-cidr: 10.244.0.0/16 사용 시)
kubectl apply -f https://github.com/flannel-io/flannel/releases/latest/download/kube-flannel.yml
```

**Cilium** (eBPF 기반, 고성능):
```bash
# Cilium CLI 설치
CILIUM_CLI_VERSION=$(curl -s https://raw.githubusercontent.com/cilium/cilium-cli/main/stable.txt)
CLI_ARCH=arm64  # ARM 인스턴스용 (x86_64면 amd64로 변경)
curl -L --fail --remote-name-all \
  https://github.com/cilium/cilium-cli/releases/download/${CILIUM_CLI_VERSION}/cilium-linux-${CLI_ARCH}.tar.gz
sudo tar xzvf cilium-linux-${CLI_ARCH}.tar.gz -C /usr/local/bin
rm cilium-linux-${CLI_ARCH}.tar.gz

# Cilium 설치
cilium install

# 설치 상태 확인
cilium status --wait

# 연결 테스트 (선택)
cilium connectivity test
```

**Weave Net**:
```bash
kubectl apply -f https://github.com/weaveworks/weave/releases/download/v2.8.1/weave-daemonset-k8s.yaml
```

#### CNI 비교

| CNI | 장점 | 단점 | 추천 상황 |
|-----|------|------|-----------|
| **Calico** | 안정적, NetworkPolicy 지원 | 메모리 사용량 중간 | 일반적인 사용 (기본 선택) |
| **Flannel** | 가장 단순, 가벼움 | NetworkPolicy 미지원 | 최소 리소스, 학습용 |
| **Cilium** | eBPF 기반, 고성능, 관측성 | 약간 무거움 | 고급 기능 필요 시 |
| **Weave** | 설치 쉬움, 암호화 지원 | 성능 중간 | 멀티 클라우드 |

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
2. **Reserved IP 한도**: Master 노드에 1개 사용 (프리티어 한도: 1개).
3. **Worker IP 변경**: Worker 노드의 Ephemeral IP는 재부팅 시 변경될 수 있습니다.
4. **보안**: SSH는 모든 IP에서 접근 가능하지만 프라이빗 키를 가진 사용자만 인증됩니다. 키 관리에 주의하세요.
5. **Region**: 프리티어는 Home Region에서만 사용 가능합니다.
6. **데이터 백업**: `terraform destroy` 시 Block Volume과 Reserved IP도 함께 삭제됩니다.
7. **비용**: 프리티어 범위 내에서만 사용하면 완전 무료입니다.
8. **부트스트랩 시간**: 인스턴스 생성 후 5-10분간 자동 설치가 진행됩니다. 바로 접속해도 설치가 완료되지 않았을 수 있습니다.

