output "ec2_instance_id" {
  value = aws_instance.source_vm.id
}

output "ec2_public_ip" {
  value = aws_instance.source_vm.public_ip
}

output "ec2_private_ip" {
  value = aws_instance.source_vm.private_ip
}
