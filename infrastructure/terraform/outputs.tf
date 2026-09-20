output "instance_id" {
  description = "EC2 instance ID used by AWS Systems Manager."
  value       = aws_instance.host.id
}

output "public_ip" {
  description = "Public IPv4 address. Access remains restricted by the security group."
  value       = aws_instance.host.public_ip
}

output "private_ip" {
  description = "Private VPC address of the EC2 host."
  value       = aws_instance.host.private_ip
}

output "application_url" {
  description = "NGINX demo URL, reachable only from admin_cidr."
  value       = "http://${aws_instance.host.public_ip}:8083"
}

output "security_group_id" {
  description = "Security group attached to the EC2 host."
  value       = aws_security_group.host.id
}

output "instance_profile_name" {
  description = "SSM-enabled IAM instance profile attached to EC2."
  value       = aws_iam_instance_profile.host.name
}

output "ssm_session_command" {
  description = "Command to open an interactive SSM shell after the instance registers."
  value       = "aws ssm start-session --target ${aws_instance.host.id} --region ${var.aws_region}"
}

output "prometheus_tunnel_command" {
  description = "SSM port-forward command for the private Prometheus UI."
  value       = "aws ssm start-session --target ${aws_instance.host.id} --region ${var.aws_region} --document-name AWS-StartPortForwardingSession --parameters portNumber=9090,localPortNumber=9090"
}

output "alertmanager_tunnel_command" {
  description = "SSM port-forward command for the private Alertmanager UI."
  value       = "aws ssm start-session --target ${aws_instance.host.id} --region ${var.aws_region} --document-name AWS-StartPortForwardingSession --parameters portNumber=9093,localPortNumber=9093"
}
