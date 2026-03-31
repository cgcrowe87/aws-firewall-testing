# Simple AWS Network Firewall Terraform Lab

This example is intentionally simple and readable.

What it builds:
- 1 VPC
- 1 workload subnet
- 2 firewall subnets (2 AZs)
- 1 internet gateway
- 1 EC2 instance for testing
- 1 AWS Network Firewall
- 1 simple stateful rule group that only allows TLS SNI traffic to google.com / .google.com

Notes:
- The EC2 instance is in only one AZ.
- The firewall is mapped to two AZs, but the workload uses the firewall endpoint in its own AZ.
- This is for learning, not production.

## Files
- providers.tf
- variables.tf
- main.tf
- outputs.tf
- terraform.tfvars.example

## Usage

```bash
terraform init
terraform plan
terraform apply
```
