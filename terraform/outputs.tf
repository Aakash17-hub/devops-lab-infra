output "bastion_public_ip" {
  description = "Public IP of the bastion host — your entry point"
  value       = aws_instance.bastion.public_ip
}

output "app_server_private_ip" {
  value = aws_instance.app_server.private_ip
}

output "git_server_private_ip" {
  value = aws_instance.git_server.private_ip
}
