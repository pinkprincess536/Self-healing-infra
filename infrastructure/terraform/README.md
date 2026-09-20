# Day 5 — Terraform AWS EC2 Lab

This configuration creates a disposable, single-instance learning environment for the self-healing stack. Terraform owns AWS infrastructure; Ansible configures the operating system and starts Compose.

## Architecture

```text
Operator /32 ──TCP 8083──> Internet Gateway ──> public subnet ──> Ubuntu EC2
                                                          ├── NGINX :8083
                                                          ├── Prometheus 127.0.0.1:9090
                                                          ├── Alertmanager 127.0.0.1:9093
                                                          └── recovery webhook (Compose-only :5000)

Operator ──AWS SSM Session Manager──> EC2 (no inbound SSH by default)
```

Terraform creates:

- a dedicated VPC, public subnet, internet gateway, route table and association;
- a security group allowing application port 8083 only from `admin_cidr`;
- optional SSH from the same restricted CIDR (disabled by default);
- an EC2 trust role, `AmazonSSMManagedInstanceCore` attachment and instance profile;
- one Canonical Ubuntu 24.04 LTS `t3.small` instance;
- an encrypted, delete-on-termination gp3 root disk;
- IMDSv2-required instance metadata settings.

Prometheus, Alertmanager and the exporter bind only to EC2 loopback. Access their UIs using SSM port forwarding, not public security-group rules. The recovery webhook remains available only on the Compose network.

## Cost and safety warning

`terraform apply` creates billable AWS resources. Review the plan, use a lab account/budget, and run `terraform destroy` when finished. A public IPv4 address, EC2 usage and EBS storage can incur charges. This project does not run `apply` automatically.

## Prerequisites

1. Terraform `1.16.2` (the newest exact version currently available through Windows Package Manager).
2. AWS CLI configured with a lab identity able to manage VPC, EC2 and the specific IAM resources in this configuration.
3. AWS Session Manager plugin for interactive sessions/port forwarding.
4. Your current public IPv4 address in `/32` form.

Do not add AWS access keys, private keys, the webhook token, `.tfvars`, or Terraform state to Git.

## Configure

```powershell
Copy-Item terraform.tfvars.example terraform.tfvars
```

Edit `terraform.tfvars` and replace the documentation CIDR with your current public IP, for example `198.51.100.24/32`. Keep `enable_ssh = false` unless SSM cannot be used.

Authenticate through your normal AWS mechanism (SSO/profile/environment) and verify without printing credentials:

```powershell
aws sts get-caller-identity
```

## Safe workflow

```powershell
terraform init
terraform fmt -check -recursive
terraform validate
terraform test
terraform plan -out day5.tfplan
terraform show day5.tfplan
```

Stop and inspect the plan. Expected resource categories are VPC/subnet/routing, security-group rules, IAM role/profile/policy attachment and one EC2 instance. There should be no secrets, wildcard inbound access, NAT gateway, database or load balancer.

Only after explicit approval:

```powershell
terraform apply day5.tfplan
terraform output
```

## Configure EC2 through SSM

Get the command:

```powershell
terraform output -raw ssm_session_command
```

Run it, then in the EC2 shell:

```bash
curl -fsSLo /tmp/bootstrap-ec2.sh \
  https://raw.githubusercontent.com/pinkprincess536/Self-healing-infra/main/infrastructure/ansible/bootstrap-ec2.sh
sudo bash /tmp/bootstrap-ec2.sh
```

The Ansible playbook prompts twice for a random webhook token using hidden input. It stores the token as `/opt/self-healing/secrets/webhook_token` with root ownership, Alertmanager's pinned group `65534`, and mode `0640`; Terraform never sees it. This gives Alertmanager read-only access while denying all unrelated users.

Ansible then installs Docker/Compose, enables Docker, installs a systemd unit for the stack, starts it, and verifies NGINX, Prometheus, Alertmanager and the internal webhook.

## Access

Application (restricted to `admin_cidr`):

```powershell
terraform output -raw application_url
```

Prometheus tunnel:

```powershell
terraform output -raw prometheus_tunnel_command
```

Then open `http://localhost:9090` while the session runs. Alertmanager works similarly using `alertmanager_tunnel_command` and `http://localhost:9093`.

## Destroy

```powershell
terraform plan -destroy
terraform destroy
```

Afterward, verify the EC2 instance, VPC and IAM role are gone. Terraform state is local and gitignored; delete it only after confirming AWS resources were destroyed.

## Deliberate lab limitation

The recovery webhook still controls the local Docker daemon through `/var/run/docker.sock`, which is effectively root-level host access. The endpoint is authenticated and Compose-internal, but this remains a learning-lab design—not a production security boundary. A production design should replace it with a narrowly privileged host service or remote recovery mechanism.
