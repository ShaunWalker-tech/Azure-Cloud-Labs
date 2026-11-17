output "ec2_instance_id" {
  value = aws_instance.source_vm.id
}

output "ec2_public_ip" {
  description = "Used for RDP, the appliance discovery source, and the Azure 9443 NSG rule."
  value       = aws_instance.source_vm.public_ip
}

output "ec2_private_ip" {
  description = "Push install targets this address, which Azure can't reach without a VPN."
  value       = aws_instance.source_vm.private_ip
}
