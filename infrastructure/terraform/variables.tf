variable "aws_region" {
  description = "AWS region in which the disposable lab is created."
  type        = string
  default     = "us-east-1"
}

variable "project_name" {
  description = "Short name used in resource names and tags."
  type        = string
  default     = "self-healing-infra"

  validation {
    condition     = can(regex("^[a-z0-9-]{3,32}$", var.project_name))
    error_message = "project_name must contain 3-32 lowercase letters, numbers, or hyphens."
  }
}

variable "environment" {
  description = "Environment label used in names and tags."
  type        = string
  default     = "lab"

  validation {
    condition     = can(regex("^[a-z0-9-]{2,16}$", var.environment))
    error_message = "environment must contain 2-16 lowercase letters, numbers, or hyphens."
  }
}

variable "admin_cidr" {
  description = "Trusted operator IPv4 CIDR allowed to reach NGINX (and SSH only when explicitly enabled). Use your public IP with /32."
  type        = string

  validation {
    condition = (
      can(cidrhost(var.admin_cidr, 0)) &&
      can(regex("^([0-9]{1,3}\\.){3}[0-9]{1,3}/([0-9]|[12][0-9]|3[0-2])$", var.admin_cidr)) &&
      var.admin_cidr != "0.0.0.0/0"
    )
    error_message = "admin_cidr must be a valid restricted IPv4 CIDR; 0.0.0.0/0 is intentionally rejected."
  }
}

variable "vpc_cidr" {
  description = "IPv4 CIDR for the dedicated lab VPC."
  type        = string
  default     = "10.42.0.0/16"
}

variable "public_subnet_cidr" {
  description = "IPv4 CIDR for the single public lab subnet."
  type        = string
  default     = "10.42.1.0/24"
}

variable "instance_type" {
  description = "EC2 instance type. t3.small is the practical minimum for the six-container learning stack."
  type        = string
  default     = "t3.small"
}

variable "root_volume_gb" {
  description = "Encrypted gp3 root volume size in GiB."
  type        = number
  default     = 20

  validation {
    condition     = var.root_volume_gb >= 12 && var.root_volume_gb <= 100
    error_message = "root_volume_gb must be between 12 and 100 GiB."
  }
}

variable "enable_ssh" {
  description = "Whether to create a source-restricted SSH ingress rule and EC2 key pair. SSM is preferred and this defaults to false."
  type        = bool
  default     = false
}

variable "ssh_public_key" {
  description = "OpenSSH public key text used only when enable_ssh=true. Never provide a private key."
  type        = string
  default     = null
  nullable    = true

  validation {
    condition     = var.ssh_public_key == null || length(trimspace(var.ssh_public_key)) > 0
    error_message = "ssh_public_key must be null or non-empty public key text."
  }
}

variable "additional_tags" {
  description = "Optional extra tags applied to all supported resources."
  type        = map(string)
  default     = {}
}

check "ssh_configuration" {
  assert {
    condition     = !var.enable_ssh || var.ssh_public_key != null
    error_message = "ssh_public_key is required when enable_ssh=true."
  }
}
