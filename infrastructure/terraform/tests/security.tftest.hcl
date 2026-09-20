mock_provider "aws" {}

override_data {
  target = data.aws_availability_zones.available
  values = {
    names = ["us-east-1a"]
  }
}

override_data {
  target = data.aws_ami.ubuntu
  values = {
    id = "ami-0123456789abcdef0"
  }
}

override_data {
  target = data.aws_iam_policy_document.ec2_assume_role
  values = {
    json = "{\"Version\":\"2012-10-17\",\"Statement\":[{\"Effect\":\"Allow\",\"Principal\":{\"Service\":\"ec2.amazonaws.com\"},\"Action\":\"sts:AssumeRole\"}]}"
  }
}

run "safe_default_plan" {
  command = plan

  variables {
    admin_cidr = "203.0.113.10/32"
  }

  assert {
    condition     = aws_vpc_security_group_ingress_rule.application.cidr_ipv4 == "203.0.113.10/32"
    error_message = "Application ingress must use the supplied restricted operator CIDR."
  }

  assert {
    condition     = length(aws_vpc_security_group_ingress_rule.ssh) == 0
    error_message = "SSH must be disabled by default."
  }

  assert {
    condition     = aws_instance.host.metadata_options[0].http_tokens == "required"
    error_message = "EC2 must require IMDSv2 tokens."
  }

  assert {
    condition     = aws_instance.host.root_block_device[0].encrypted
    error_message = "The EC2 root volume must be encrypted."
  }

  assert {
    condition     = aws_instance.host.instance_type == "t3.small"
    error_message = "The tested default must remain t3.small for this six-container lab."
  }
}

run "reject_world_open_admin_cidr" {
  command = plan

  variables {
    admin_cidr = "0.0.0.0/0"
  }

  expect_failures = [var.admin_cidr]
}
