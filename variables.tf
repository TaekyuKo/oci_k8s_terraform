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
  description = "OCI Region."
}

variable "compartment_ocid" {
  type        = string
  description = "Compartment OCID."
}

variable "ssh_public_key" {
  type        = string
  description = "SSH public key."
  sensitive   = true
}
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