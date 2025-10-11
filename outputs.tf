output "master_node_public_ip" {
  value       = oci_core_public_ip.master_ip_assignment.ip_address
  description = "The reserved public IP of the master node."
}

output "master_node_private_ip" {
  value       = oci_core_instance.k8s_master.private_ip
  description = "The private IP of the master node."
}

output "worker_node_public_ip" {
  value       = oci_core_instance.k8s_worker.public_ip
  description = "The ephemeral public IP of the worker node."
}

output "worker_node_private_ip" {
  value       = oci_core_instance.k8s_worker.private_ip
  description = "The private IP of the worker node."
}

output "ssh_connection_commands" {
  value = <<-EOT
    # Master 노드 직접 접속 (Reserved IP)
    ssh ubuntu@${oci_core_public_ip.master_ip_assignment.ip_address}
    
    # Worker 노드 직접 접속 (Ephemeral IP)
    ssh ubuntu@${oci_core_instance.k8s_worker.public_ip}
  EOT
  description = "SSH connection commands for both nodes."
}