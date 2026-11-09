output "private_ips" {
  description = "Fixed private IPs of the instances."
  value       = { for k, i in aws_instance.lab : k => i.private_ip }
}

output "bastion_public_ip" {
  description = "Empty while the bastion is stopped (no Elastic IP)."
  value       = aws_instance.lab["bastion"].public_ip
}
