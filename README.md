[English](README.md) | [한국어](README.ko.md)

# OCI Free Tier Kubernetes Cluster Automation

[![Terraform](https://img.shields.io/badge/Terraform-%3E%3D1.0-blue?logo=terraform)](https://www.terraform.io/)
[![OCI](https://img.shields.io/badge/OCI-Free%20Tier-red?logo=oracle)](https://www.oracle.com/cloud/free/)
[![Kubernetes](https://img.shields.io/badge/Kubernetes-v1.31-326CE5?logo=kubernetes)](https://kubernetes.io/)
[![License](https://img.shields.io/badge/License-MIT-green.svg)](LICENSE)

Automated deployment of a Kubernetes cluster on the Oracle Cloud Infrastructure (OCI) Free Tier.

## 📋 Overview

This project uses Terraform to automatically provision the following on the OCI Free Tier:

- **Network**: VCN, public subnet, Internet Gateway
- **Security**: Security List (ports required by Kubernetes)
- **Compute**: master node (Reserved Public IP), worker node (Ephemeral Public IP)
- **Storage**: a 50 GB Block Volume attached to each node (mounted manually)
- **Kubernetes**: automatic installation of containerd, kubeadm, kubelet, and kubectl

## 🎯 Highlights

- ✅ **Completely free**: $0 within Oracle Cloud Infrastructure (OCI) Free Tier limits
- ✅ **Fixed master IP**: Reserved Public IP survives reboots
- ✅ **Automated**: one-shot deployment with Terraform + Cloud-Init
- ✅ **Learning-friendly**: focus on Kubernetes itself without complex networking
- ✅ **ARM architecture**: Ampere A1 processors (VM.Standard.A1.Flex)

## 📁 Project Layout

```
oci_k8s_terraform/
├── provider.tf         # OCI provider configuration and auth
├── variables.tf        # Input variable definitions
├── main.tf             # Main resources (VCN, instances, volumes, ...)
├── outputs.tf          # Outputs (IP addresses, ...)
├── k8s_bootstrap.sh    # Cloud-Init script (automatic K8s install)
├── terraform.tfvars    # Variable values (create yourself; gitignored)
├── .gitignore          # Files excluded from Git
└── README.md           # Project documentation
```

## 🚀 Quick Start

### Step 1: Prerequisites

#### Required software
```bash
# Check Terraform installation
terraform version  # v1.0 or later required
```

#### OCI account setup

**1. OCI account and Free Tier**
- Sign in to the [OCI Console](https://cloud.oracle.com)
- Confirm the Free Tier is active (Always Free Resources)

**2. Create an API key (used by Terraform to talk to OCI)**

In the OCI Console:
1. Click your profile icon (top right) → **User Settings**
2. Left menu **API Keys** → click **Add API Key**
3. Select **Generate API Key Pair**
4. Click **Download Private Key** and save the file (e.g. `oci_api_key.pem`)
   - Windows: `C:\Users\<username>\.oci\oci_api_key.pem`
   - Linux/Mac: `~/.oci/oci_api_key.pem`
5. Click **Add**
6. From the **Configuration File Preview**, copy:
   - `tenancy` (tenancy_ocid)
   - `user` (user_ocid)
   - `fingerprint`
   - `region`

**3. Prepare an SSH key (used to connect to the instances)**

**Option 1: generate in the OCI Console (simplest)**
1. OCI Console → **Compute** → **Instances**
2. Open the **Create Instance** page (no need to actually create one)
3. In the **Add SSH keys** section, select **Generate a key pair for me**
4. Click **Save Private Key** (e.g. `ssh-key-2025-12-01.key`)
5. Click **Save Public Key** (e.g. `ssh-key-2025-12-01.key.pub`)
6. Open the public key file in a text editor and copy its full contents (starts with `ssh-rsa AAAA...`)

**Option 2: generate locally**

Skip this step if you already have an SSH key.

**Windows (PowerShell):**
```powershell
# Generate an SSH key
ssh-keygen -t rsa -b 2048 -f $env:USERPROFILE\.ssh\id_rsa

# Show the public key
cat $env:USERPROFILE\.ssh\id_rsa.pub
```

**Linux/Mac:**
```bash
# Generate an SSH key
ssh-keygen -t rsa -b 2048 -f ~/.ssh/id_rsa

# Show the public key
cat ~/.ssh/id_rsa.pub
```

Copy the entire `ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQ...` output.

### Step 2: Configure variables

Create a `terraform.tfvars` file in the project directory with the information gathered above.

**Create the file:**
```bash
# Move into the project directory
cd oci_k8s_terraform

# Create terraform.tfvars (with a text editor)
notepad terraform.tfvars  # Windows
# or
nano terraform.tfvars     # Linux/Mac
```

**File contents:**
```hcl
# ========================================
# OCI credentials
# ========================================

# Values from the API key Configuration File Preview
tenancy_ocid     = "ocid1.tenancy.oc1..aaaaaaaxxxxx"     # tenancy value
user_ocid        = "ocid1.user.oc1..aaaaaaaxxxxx"        # user value
fingerprint      = "aa:bb:cc:dd:ee:ff:00:11:22:33:44:55:66:77:88:99"  # fingerprint value
region           = "ap-seoul-1"  # region value (your Home Region)

# Path to the downloaded API private key (oci_api_key.pem)
private_key_path = "C:/Users/YourName/.oci/oci_api_key.pem"  # Windows example
# private_key_path = "~/.oci/oci_api_key.pem"  # Linux/Mac example

# ========================================
# Resource settings
# ========================================

# Compartment OCID (same as tenancy_ocid when using the root compartment)
compartment_ocid = "ocid1.compartment.oc1..aaaaaaaxxxxx"  # or same as tenancy_ocid

# ========================================
# SSH access key
# ========================================

# SSH public key (paste the full contents of id_rsa.pub generated above)
ssh_public_key   = "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQ..."
```

**Field reference:**

| Field | Description | Where to find it |
|------|------|-------------------|
| `tenancy_ocid` | OCI tenancy ID | API key Configuration File Preview |
| `user_ocid` | User ID | API key Configuration File Preview |
| `fingerprint` | API key fingerprint | API key Configuration File Preview |
| `region` | Region | API key Configuration File Preview (e.g. ap-seoul-1) |
| `private_key_path` | API private key path | **Absolute path** to the downloaded `oci_api_key.pem` |
| `compartment_ocid` | Compartment ID | Same as tenancy_ocid (when using root) |
| `ssh_public_key` | SSH public key | Full output of `cat ~/.ssh/id_rsa.pub` |

**Notes:**
- On Windows, use `/` or `\\` in paths (e.g. `C:/Users/...` or `C:\\Users\\...`)
- `ssh_public_key` must be the whole single line starting with `ssh-rsa AAAA...`
- All OCIDs must be quoted

### Step 3: Deploy with Terraform

```bash
# Initialize (first time only)
terraform init

# Review the plan (expected resources)
terraform plan

# Apply
terraform apply
# type "yes" to confirm
```

**Deployment time**: about 5–10 minutes.

When the deployment finishes, you will see:
```
Outputs:

master_node_public_ip = "132.145.xxx.xxx"  (Reserved IP - stable across reboots)
master_node_private_ip = "10.0.1.2"
worker_node_public_ip = "138.2.xxx.xxx"  (Ephemeral IP - may change on reboot)
worker_node_private_ip = "10.0.1.3"
ssh_connection_commands = <<EOT
    # Connect to the master node (Reserved IP)
    ssh ubuntu@132.145.xxx.xxx

    # Connect to the worker node (Ephemeral IP)
    ssh ubuntu@138.2.xxx.xxx
EOT
```

### Step 4: Connect and verify

#### 4-1. Connect to the master node
```bash
# SSH using the private key you saved earlier
ssh -i /path/to/ssh-private-key ubuntu@<master_node_public_ip>

# Examples:
# key downloaded from the OCI Console
ssh -i ~/Downloads/ssh-key-2025-12-01.key ubuntu@132.145.xxx.xxx

# locally generated key
ssh -i ~/.ssh/id_rsa ubuntu@132.145.xxx.xxx
```

**Notes:**
- The default username is `ubuntu` (Ubuntu image default account)
- On SSH key permission errors: `chmod 600 /path/to/ssh-private-key`

#### 4-2. Verify the bootstrap
```bash
# Check the automatic installation (wait about 5-10 minutes first)
sudo /usr/local/bin/verify-k8s-setup.sh
```

**What to check**:
- ✅ Swap: 0B (disabled)
- ✅ Containerd: active
- ✅ iSCSI: active (ready for Block Volume attachment)
- ✅ IP forwarding: 1
- ✅ iptables: intra-VCN traffic allowed

**Note**: right after instance creation, the bootstrap may still be running. Check again after 5–10 minutes.

#### 4-3. Attach the Block Volume (optional)

Attach a Block Volume if you need extra storage.

**How to attach:**
1. OCI Console → Compute → Instances → click the instance
2. Resources → Attached Block Volumes
3. Click the Block Volume → "iSCSI Commands and Information" tab
4. Copy the **three iSCSI commands** shown and run them on the instance

**Example commands** (get the real values from the OCI Console for each node):
```bash
sudo iscsiadm -m node -o new -T iqn.2015-12.com.oracleiaas:xxxxxx -p xxx.xxx.x.x:3260
sudo iscsiadm -m node -o update -T iqn.2015-12.com.oracleiaas:xxxxxx -n node.startup -v automatic
sudo iscsiadm -m node -T iqn.2015-12.com.oracleiaas:xxxxxx -p xxx.xxx.x.x:3260 -l
```

**Format and mount the disk** (first time only):
```bash
# Find the attached device
lsblk

# Create a filesystem (device name from lsblk)
sudo mkfs.ext4 /dev/sdb

# Mount
sudo mkdir -p /data
sudo mount /dev/sdb /data

# Auto-mount after reboot
UUID=$(sudo blkid -s UUID -o value /dev/sdb)
echo "UUID=$UUID /data ext4 defaults,nofail,_netdev 0 2" | sudo tee -a /etc/fstab
```

**Note**: skip this step if you don't need the Block Volume.

### Step 5: Initialize the Kubernetes cluster (master node)

```bash
# Get the master node's private IP
MASTER_IP=$(hostname -I | awk '{print $1}')
echo $MASTER_IP  # e.g. 10.0.1.2

# Initialize with kubeadm
sudo kubeadm init \
  --pod-network-cidr=192.168.0.0/16 \
  --apiserver-advertise-address=$MASTER_IP \
  --control-plane-endpoint=$MASTER_IP

# Configure kubectl (use the printed commands, or the ones below)
mkdir -p $HOME/.kube
sudo cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
sudo chown $(id -u):$(id -g) $HOME/.kube/config

# Install the Calico CNI (enables the pod network)
kubectl apply -f https://raw.githubusercontent.com/projectcalico/calico/v3.28.0/manifests/calico.yaml

# Check cluster status (Ready after about 1-2 minutes)
kubectl get nodes
kubectl get pods -A
```

### Step 6: Join the worker node

#### 6-1. Generate the join command (on the master)
```bash
# Generate the command the worker will use to join the cluster
kubeadm token create --print-join-command

# Example output (copy this):
# kubeadm join 10.0.1.2:6443 --token abcdef.0123456789abcdef \
#   --discovery-token-ca-cert-hash sha256:1234567890abcdef...
```

#### 6-2. Connect to the worker node
```bash
# In a new terminal, connect directly (Ephemeral IP)
ssh ubuntu@<worker_node_public_ip>

# Or SSH from the master (private IP - recommended)
ssh ubuntu@<worker_node_private_ip>
```

**Note**: the worker's Ephemeral IP can change after a reboot, so connecting from the master via the private IP is recommended.

#### 6-3. Verify the worker node
```bash
# Check the bootstrap
sudo /usr/local/bin/verify-k8s-setup.sh
```

#### 6-4. Join the cluster (on the worker)
```bash
# Run the join command generated on the master (sudo required)
sudo kubeadm join 10.0.1.2:6443 --token <token> \
  --discovery-token-ca-cert-hash sha256:<hash>

# Success message:
# This node has joined the cluster:
# * Certificate signing request was sent to apiserver and a response was received.
# * The Kubelet was informed of the new secure connection details.
```

#### 6-5. Confirm from the master
```bash
# Back to the master node
exit

# Confirm the worker joined the cluster
kubectl get nodes

# Example output:
# NAME         STATUS   ROLES           AGE   VERSION
# k8s-master   Ready    control-plane   5m    v1.31.x
# k8s-worker   Ready    <none>          1m    v1.31.x
```

### Step 7: Deploy a sample application

```bash
# Deploy Nginx
kubectl create deployment nginx --image=nginx
kubectl expose deployment nginx --port=80 --type=NodePort

# Check the service
kubectl get svc nginx

# Example output:
# NAME    TYPE       CLUSTER-IP      EXTERNAL-IP   PORT(S)        AGE
# nginx   NodePort   10.96.123.45    <none>        80:31234/TCP   10s

# Access via the master's Reserved Public IP (browser or curl)
curl http://<master_public_ip>:31234

# Also reachable via the worker's Ephemeral Public IP
curl http://<worker_public_ip>:31234
```

## 📊 Free Tier Resource Usage

| Resource | Used by this project | Free Tier limit |
|--------|-------------------|--------------|
| **Compute (OCPU)** | 4 OCPU (2 instances × 2 OCPU) | 4 OCPU |
| **Memory** | 24 GB (2 instances × 12 GB) | 24 GB |
| **Block Volume** | 100 GB (2 × 50 GB) | 100 GB |
| **Boot Volume** | 100 GB (2 × 50 GB) | 100 GB |
| **Reserved Public IP** | 1 (master node) | 1 |
| **Ephemeral Public IP** | 1 (worker node) | unlimited |
| **VCN** | 1 | 2 |
| **Outbound data transfer** | usage-based | 10 TB/month |

**💰 Total cost**: **$0/month** (100% within the Free Tier)

## 🏗️ Network Architecture

```
Internet
  ↕
Internet Gateway (free)
  ↕
Public Subnet (10.0.1.0/24)
  ├─ k8s-master (10.0.1.x) + Reserved Public IP (fixed)
  │   └─ Block Volume 50GB → /data
  │
  └─ k8s-worker (10.0.1.x) + Ephemeral Public IP (temporary)
      └─ Block Volume 50GB → /data
```

### IP assignment
- **Master node**: Reserved Public IP
- **Worker node**: Ephemeral Public IP

## 🔧 Customization

### Change instance shape

Add these variables to `terraform.tfvars`:

```hcl
# Defaults: 2 OCPU, 12 GB RAM (per node)
instance_ocpus  = 1   # 1-4 OCPU
instance_memory = 6   # 1-24 GB per OCPU (minimum OCPU × 1 GB)
```

**Examples**:
- **Minimum**: 1 OCPU, 6 GB → 2 OCPU, 12 GB total (up to 4 nodes)
- **Maximum**: 2 OCPU, 12 GB → 4 OCPU, 24 GB total (2 nodes)

### Add worker nodes

Workers use Ephemeral IPs, so you can add as many as the OCPU/memory limits allow.

Copy the worker block in `main.tf`:

```hcl
# Add worker 2
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

Also add to `outputs.tf`:
```hcl
output "worker2_node_public_ip" {
  value = oci_core_instance.k8s_worker2.public_ip
}

output "worker2_node_private_ip" {
  value = oci_core_instance.k8s_worker2.private_ip
}
```

### Use a different CNI plugin

> ⚠️ **Warning**: install only one CNI. To use something other than Calico, install one of the following after `kubeadm init` instead of Calico.

**Flannel** (simplest):
```bash
# Install Flannel (when using pod-network-cidr 10.244.0.0/16)
kubectl apply -f https://github.com/flannel-io/flannel/releases/latest/download/kube-flannel.yml
```

**Cilium** (eBPF-based, high performance):
```bash
# Install the Cilium CLI
CILIUM_CLI_VERSION=$(curl -s https://raw.githubusercontent.com/cilium/cilium-cli/main/stable.txt)
CLI_ARCH=arm64  # for ARM instances (use amd64 on x86_64)
curl -L --fail --remote-name-all \
  https://github.com/cilium/cilium-cli/releases/download/${CILIUM_CLI_VERSION}/cilium-linux-${CLI_ARCH}.tar.gz
sudo tar xzvf cilium-linux-${CLI_ARCH}.tar.gz -C /usr/local/bin
rm cilium-linux-${CLI_ARCH}.tar.gz

# Install Cilium
cilium install

# Check installation status
cilium status --wait

# Connectivity test (optional)
cilium connectivity test
```

**Weave Net**:
```bash
kubectl apply -f https://github.com/weaveworks/weave/releases/download/v2.8.1/weave-daemonset-k8s.yaml
```

#### CNI comparison

| CNI | Pros | Cons | Recommended for |
|-----|------|------|-----------|
| **Calico** | Stable, NetworkPolicy support | Moderate memory usage | General use (default choice) |
| **Flannel** | Simplest, lightweight | No NetworkPolicy | Minimal resources, learning |
| **Cilium** | eBPF-based, fast, observable | Slightly heavier | When advanced features are needed |
| **Weave** | Easy install, encryption | Moderate performance | Multi-cloud |

## 🧹 Cleanup

```bash
# Destroy all resources
terraform destroy
# type "yes" to confirm

# Verify deletion
terraform show
# empty output means everything was destroyed
```

**Warning**:
- Data on Block Volumes is deleted permanently. Back up anything you need first.
- The Reserved Public IP is deleted as well.

## 📚 References

- [OCI Free Tier documentation](https://docs.oracle.com/en-us/iaas/Content/FreeTier/freetier.htm)
- [OCI Terraform Provider](https://registry.terraform.io/providers/oracle/oci/latest/docs)
- [Kubernetes documentation](https://kubernetes.io/docs/home/)
- [Calico networking](https://docs.tigera.io/calico/latest/about/)
- [Creating a cluster with kubeadm](https://kubernetes.io/docs/setup/production-environment/tools/kubeadm/create-cluster-kubeadm/)

## ⚠️ Caveats

1. **Free Tier limits**: this project uses 100% of the Free Tier OCPU/memory. Creating additional instances will incur charges.
2. **Reserved IP limit**: 1 used by the master node (Free Tier limit: 1).
3. **Worker IP changes**: the worker's Ephemeral IP can change after a reboot.
4. **Security**: SSH is reachable from any IP, but only holders of the private key can authenticate. Guard your keys.
5. **Region**: the Free Tier is only available in your Home Region.
6. **Data backup**: `terraform destroy` also deletes the Block Volumes and the Reserved IP.
7. **Cost**: completely free as long as you stay within the Free Tier.
8. **Bootstrap time**: automatic installation runs for 5–10 minutes after instance creation. It may not be finished if you connect immediately.
