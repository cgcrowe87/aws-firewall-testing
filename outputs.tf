output "vpc_id" {
  value = aws_vpc.main.id
}

output "workload_subnet_id" {
  value = aws_subnet.workload.id
}

output "firewall_subnet_az1_id" {
  value = aws_subnet.firewall_az1.id
}

output "firewall_subnet_az2_id" {
  value = aws_subnet.firewall_az2.id
}

output "firewall_arn" {
  value = aws_networkfirewall_firewall.main.arn
}

output "firewall_endpoint_az1" {
  value = local.firewall_endpoint_az1
}

output "test_instance_id" {
  value = aws_instance.test.id
}
