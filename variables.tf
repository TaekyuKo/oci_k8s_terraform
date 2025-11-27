# ---------------- OCI 인증 정보 ----------------
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

# ---------------- 공통 리소스 ----------------
variable "compartment_ocid" {
  type        = string
  description = "Compartment OCID where resources will be created."
}
variable "ssh_public_key" {
  type        = string
  description = "Public SSH key for instance access."
  sensitive   = true
}
# admin_ip_cidr 변수 제거 - SSH 키 기반 인증으로 모든 위치에서 접근 허용


# ---------------- 인스턴스 사양----------------
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