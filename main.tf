data "oci_identity_availability_domains" "ads" {
  compartment_id = var.compartment_ocid
}

data "oci_core_images" "ubuntu_image" {
  compartment_id           = var.compartment_ocid
  operating_system         = "Canonical Ubuntu"
  operating_system_version = "22.04"
  shape                    = var.instance_shape
  sort_by                  = "TIMECREATED"
  sort_order               = "DESC"
}

# =================================================================
# 네트워크
# ================================================================= 
resource "oci_core_vcn" "k8s_vcn" {
  compartment_id = var.compartment_ocid
  cidr_block     = "10.0.0.0/16"
  display_name   = "k8s-vcn"
  dns_label      = "k8svcn"
}

resource "oci_core_internet_gateway" "k8s_igw" {
  compartment_id = var.compartment_ocid
  vcn_id         = oci_core_vcn.k8s_vcn.id
  display_name   = "k8s-igw"
}

resource "oci_core_subnet" "public_subnet" {
  compartment_id    = var.compartment_ocid
  vcn_id            = oci_core_vcn.k8s_vcn.id
  cidr_block        = "10.0.1.0/24"
  display_name      = "k8s-public-subnet"
  dns_label         = "public"
  route_table_id    = oci_core_route_table.public_rt.id
  security_list_ids = [oci_core_security_list.k8s_sl.id]
}

resource "oci_core_route_table" "public_rt" {
  compartment_id = var.compartment_ocid
  vcn_id         = oci_core_vcn.k8s_vcn.id
  display_name   = "k8s-public-rt"
  
  route_rules {
    destination       = "0.0.0.0/0"
    network_entity_id = oci_core_internet_gateway.k8s_igw.id
  }
}

# =================================================================
# 보안
# =================================================================

resource "oci_core_security_list" "k8s_sl" {
  compartment_id = var.compartment_ocid
  vcn_id         = oci_core_vcn.k8s_vcn.id
  display_name   = "k8s-cluster-sl"
  
  egress_security_rules {
    protocol    = "all"
    destination = "0.0.0.0/0"
    description = "Allow all outbound traffic."
  }
  
  ingress_security_rules {
    protocol    = "all"
    source      = "10.0.0.0/16"
    description = "VCN internal traffic for Kubernetes."
  }
  
  ingress_security_rules {
    protocol    = "6"
    source      = "0.0.0.0/0"
    tcp_options { 
      min = 22 
      max = 22 
    }
    description = "SSH access."
  }
  
  ingress_security_rules {
    protocol    = "6"
    source      = "0.0.0.0/0"
    tcp_options { 
      min = 6443 
      max = 6443 
    }
    description = "Kubernetes API Server."
  }
  
  ingress_security_rules {
    protocol    = "1"
    source      = "0.0.0.0/0"
    description = "ICMP (ping)."
  }
  
  ingress_security_rules {
    protocol    = "6"
    source      = "0.0.0.0/0"
    tcp_options { 
      min = 80 
      max = 80 
    }
    description = "HTTP."
  }
  
  ingress_security_rules {
    protocol    = "6"
    source      = "0.0.0.0/0"
    tcp_options { 
      min = 443 
      max = 443 
    }
    description = "HTTPS."
  }
  
  ingress_security_rules {
    protocol    = "6"
    source      = "0.0.0.0/0"
    tcp_options { 
      min = 30000 
      max = 32767 
    }
    description = "NodePort services."
  }
}

# =================================================================
# 컴퓨트 및 스토리지
# =================================================================
resource "oci_core_instance" "k8s_master" {
  availability_domain = data.oci_identity_availability_domains.ads.availability_domains[0].name
  compartment_id      = var.compartment_ocid
  display_name        = "k8s-master"
  shape               = var.instance_shape
  
  shape_config {
    ocpus         = var.instance_ocpus
    memory_in_gbs = var.instance_memory
  }
  
  create_vnic_details {
    subnet_id                 = oci_core_subnet.public_subnet.id
    assign_public_ip          = false
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

# Master Node에 Reserved IP 할당
resource "oci_core_public_ip" "master_ip_assignment" {
  compartment_id = var.compartment_ocid
  lifetime       = "RESERVED"
  display_name   = "k8s-master-reserved-ip"
  private_ip_id  = data.oci_core_private_ips.master_private_ip.private_ips[0].id

  depends_on = [oci_core_instance.k8s_master]
}

data "oci_core_private_ips" "master_private_ip" {
  vnic_id = data.oci_core_vnic_attachments.master_vnic_attachment.vnic_attachments[0].vnic_id
}

data "oci_core_vnic_attachments" "master_vnic_attachment" {
  compartment_id      = var.compartment_ocid
  instance_id         = oci_core_instance.k8s_master.id
}

resource "oci_core_volume" "master_bv" {
  availability_domain = data.oci_identity_availability_domains.ads.availability_domains[0].name
  compartment_id      = var.compartment_ocid
  display_name        = "k8s-master-bv"
  size_in_gbs         = 50
}

resource "oci_core_volume_attachment" "master_bv_attachment" {
  attachment_type = "iscsi"
  instance_id     = oci_core_instance.k8s_master.id
  volume_id       = oci_core_volume.master_bv.id
  display_name    = "k8s-master-bv-attachment"
  device          = "/dev/oracleoci/oraclevdb"
}
resource "oci_core_instance" "k8s_worker" {
  availability_domain = data.oci_identity_availability_domains.ads.availability_domains[0].name
  compartment_id      = var.compartment_ocid
  display_name        = "k8s-worker"
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

# Worker Node Block Volume
resource "oci_core_volume" "worker_bv" {
  availability_domain = data.oci_identity_availability_domains.ads.availability_domains[0].name
  compartment_id      = var.compartment_ocid
  display_name        = "k8s-worker-bv"
  size_in_gbs         = 50
}

resource "oci_core_volume_attachment" "worker_bv_attachment" {
  attachment_type = "iscsi"
  instance_id     = oci_core_instance.k8s_worker.id
  volume_id       = oci_core_volume.worker_bv.id
  display_name    = "k8s-worker-bv-attachment"
  device          = "/dev/oracleoci/oraclevdc"
}