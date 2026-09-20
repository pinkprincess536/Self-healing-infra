# DAY 5 — Terraform + AWS EC2

Date: 2026-09-20

## Daily build goals
- [x] Create AWS infrastructure with Terraform (config written and validated locally).
- [x] Provision EC2 and required security/network configuration (defined, pending `apply`).
- [x] Use IAM role instead of hard-coded credentials where appropriate.
- [x] Use configuration management to set up the stack (Ansible playbook + bootstrap script).
- [ ] Run the monitoring/recovery system on EC2 (blocked: AWS CLI not installed yet).
- [ ] Test reproducibility by recreating a component (requires AWS apply).

## Topics to refer to
- Terraform provider/resource
- Variables/outputs
- State
- init/plan/apply/destroy
- EC2
- Security Groups
- IAM roles

## Interview questions and answers

### What is Terraform state?
State is Terraform's record of which real-world resources it manages and what attributes they have. When you run `apply`, Terraform reads the state file, compares the desired configuration with the recorded reality, and generates only the differences (create/update/destroy).

Without state, Terraform could not know that an existing EC2 instance already belongs to this configuration versus one that should be deleted. In this lab the state is local and gitignored; a team setup would move it to a remote backend with locking so everyone shares one source of truth.

### Why is plan useful?
`terraform plan` is a dry-run that shows what Terraform will change before anything is touched. It reports which resources will be added, changed, or destroyed, and surfaces errors such as missing variables or invalid security-group rules before real (billable) AWS resources are created.

It is the inspection step. The README workflow requires reviewing the plan for wildcard ingress, NAT gateways, databases, or load balancers before ever running `apply`.

### Infrastructure creation vs configuration?
These are two different jobs owned by two tools:

- **Terraform creates infrastructure:** VPC, subnet, internet gateway, security group, IAM role, and the EC2 instance itself.
- **Ansible configures the operating system:** installs Docker/Compose/Git, writes the secret, installs the systemd unit, starts the Compose stack, and verifies NGINX/Prometheus/Alertmanager.

Terraform does not know how to install Docker; Ansible does not know how to create a subnet. Keeping them separate makes each step reproducible and independently testable.

### Why use an IAM role on EC2?
An IAM role attached through an instance profile lets AWS deliver short-lived, automatically rotating credentials to the instance instead of storing a long-lived access key on disk. The instance can assume the role without any key in code, config, or environment.

Here the role has only `AmazonSSMManagedInstanceCore`, so the operator can reach the host through Session Manager without opening SSH or embedding credentials. If the instance is compromised, the leaked credential is temporary and narrowly scoped, and the role can be removed.

### What network access is actually required?
Minimal inbound and only what is needed outbound:

- Inbound TCP 8083 from the operator's `/32` CIDR to reach the NGINX demo.
- No inbound SSH by default; access is via AWS SSM Session Manager.
- Outbound internet for `apt`, pulling container images, reaching GitHub, and the SSM agent.

Prometheus (9090), Alertmanager (9093), and the exporter bind to loopback only and are reached through SSM port forwarding. The recovery webhook stays on the Compose network and is never published.

### What should never be committed to Git?
Secrets and any credential-bearing or environment-specific state:

- AWS access/secret keys and private SSH keys (`.pem`).
- `terraform.tfvars` (real values) and Terraform state files.
- The generated webhook token (`secrets/webhook_token`).

Only examples/templates are committed (`terraform.tfvars.example`, `webhook_token.example`). If someone clones the repo, they must receive zero working secrets.

## Extra related topics — only if core work is stable
- Remote state
- Terraform modules
- SSM
- CloudWatch
- KMS

## Commands I actually learned / used

| # | Command | Why / what it does |
|---|---|---|
| 1 | `terraform fmt -check -recursive` | Checks whether every `.tf`/`.tftest.hcl` file follows canonical formatting. Exit 0 confirmed the code is already formatted. |
| 2 | `terraform validate` | Parses and type-checks the whole configuration without contacting AWS. Returned `Success! The configuration is valid.` |
| 3 | `terraform test` | Runs the mock-plan tests in `tests/security.tftest.hcl` using a mocked AWS provider. Passed 2/2: safe defaults and rejection of `0.0.0.0/0`. |
| 4 | `terraform init` | Initializes the working directory and installs the pinned `hashicorp/aws` 6.65.0 provider from the dependency lock file. |
| 5 | `terraform plan -var "admin_cidr=203.0.113.10/32"` | Generates the change plan. It correctly passed variable validation, then stopped with `No valid credential sources found` — the expected result with no AWS CLI, proving only credentials are missing. |
| 6 | `python -m py_compile recovery/webhook/app.py` | Compiles the webhook without running it, catching Python syntax errors after the hardening edits. Exit 0. |
| 7 | `python -c "import yaml; yaml.safe_load(...configure_ec2.yml)"` | Parses the Ansible playbook as YAML to confirm it is well-formed before it ever runs on EC2. |
| 8 | `docker compose config --quiet` | Validates `docker-compose.yml` after the loopback-only port and restart-policy changes. Exit 0. |

## What I achieved today

- Wrote a complete Terraform configuration split across `versions.tf`, `providers.tf`, `variables.tf`, `main.tf`, `outputs.tf`, `terraform.tfvars.example`, and `tests/security.tftest.hcl`.
- Defined a disposable lab: dedicated VPC, public subnet, internet gateway, route table, and a security group that allows only TCP 8083 from the operator CIDR (SSH opt-in, default off; `0.0.0.0/0` rejected by validation).
- Attached an EC2 IAM role with only `AmazonSSMManagedInstanceCore`, enforced IMDSv2 tokens, and used an encrypted gp3 root volume.
- Wrote an Ansible bootstrap script (`bootstrap-ec2.sh`) and playbook (`configure_ec2.yml`) that clone the repo, install Docker/Compose/Git, write the webhook token with `0600` perms, install a systemd unit for the stack, and verify all four services.
- Hardened the existing stack for EC2: Prometheus/Alertmanager/exporter bind loopback-only, all services got `restart: unless-stopped`, and the webhook now rejects non-firing or non-`NginxDown` payloads.
- Added `.gitattributes` to force LF line endings for shell/YAML/Terraform files so `bootstrap-ec2.sh` executes correctly on Linux.
- Validated locally: `terraform fmt`, `validate`, and `test` all pass, and the plan stops only at the missing AWS credential step (expected until AWS CLI is installed).

## What I learned / what broke / what I want to remember

1. **`terraform test` is the local dry-run.** It uses a mocked provider and overridden data sources so the whole plan path is exercised without AWS credentials or billable resources. It proved the restricted CIDR, SSH-off default, IMDSv2, encrypted root volume, and instance type before any real apply.
2. **A missing credential is a good failure.** `terraform plan` failing with `No valid credential sources found` after passing variable validation means the configuration and provider wiring are correct — the only gap is authentication, which is exactly the documented prerequisite.
3. **Terraform and Ansible own different halves.** Terraform builds the VPC/EC2/IAM; Ansible turns that bare instance into a working host. The bootstrap script bridges them by cloning the repo and running Ansible locally over SSM.
4. **SSM replaces SSH as the safe path.** No key pair, no inbound 22, no long-lived AWS key on the instance. The role grants only Session Manager, and the UIs are reached via SSM port forwarding instead of public security-group rules.
5. **Loopback-only is the correct default on EC2.** Prometheus, Alertmanager, and the exporter must not be world-reachable. Only NGINX on 8083 is exposed, and only to the operator's `/32`.

do we need all .tf files

 ![alt text](image-11.png)

 versions.tf — "What versions can I use?"

Specifies the required Terraform version.
Specifies which providers the project needs and their versions.


roviders.tf — "How do I connect to AWS?"

Configures the AWS provider.
Tells Terraform that you're going to work with AWS

variables.tf — "What values can I customize?"

Defines variables that your Terraform configuration can use.
Instead of hardcoding values everywhere, you create variables.

Example:

variable "instance_type" {
  type    = string
  default = "t2.micro"
}

Then your main.tf can use:

instance_type = var.instance_type
Think: "What inputs does my infrastructure need?"

main.tf — "What infrastructure should I create?"

This is usually where your actual AWS resources are defined.

terraform.tfvars.example — "Here is an example of the input values."

Provides sample values for the variables defined in variables.tf.

Example:

instance_type = "t2.micro"
region        = "ap-south-1"
The .example part is important: it's usually a template, not the actual configuration you use.
