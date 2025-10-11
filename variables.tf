# ---------------- OCI 인증 정보 변수 ----------------
variable "tenancy_ocid" {
  type        = string
  description = "OCI Tenancy OCID."
}
variable "user_ocid" {
  type        = string
  description = "OCI User OCID."
}
variable "fingerprint" {
  type        = string
  description = "API Key Fingerprint."
}
variable "private_key_path" {
  type        = string
  description = "Path to the OCI API private key file."
}
variable "region" {
  type        = string
  description = "OCI Region for the resources."
}

# ---------------- 공통 리소스 변수 ----------------
variable "compartment_ocid" {
  type        = string
  description = "Compartment OCID where resources will be created."
}
variable "ssh_public_key" {
  type        = string
  description = "Public SSH key for instance access."
  sensitive   = true
}
variable "admin_ip_cidr" {
  type        = string
  description = "CIDR block of the admin machine for SSH and kubectl access."
}


# ---------------- 인스턴스 사양 변수 ----------------
variable "instance_shape" {
  type    = string
  default = "VM.Standard.A1.Flex"
}
variable "instance_ocpus" {
  type    = number
  default = 2
}
variable "instance_memory" {
  type    = number
  default = 12
}