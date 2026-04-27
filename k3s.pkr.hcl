locals {
  timestamp      = formatdate("YYYYMMDD-hhmmss", timestamp())
  ami_name       = "${var.ami_name_prefix}-${local.timestamp}"
  ubuntu_release = "noble-24.04"
  architecture   = "arm64"
}

source "amazon-ebs" "k3s" {
  region        = var.region
  instance_type = var.instance_type
  ssh_username  = var.ssh_username

  source_ami      = data.amazon-ami.ubuntu_noble_arm64.id
  ami_name        = local.ami_name
  ami_description = "K3s ${var.k3s_version} single-node image on Ubuntu ${local.ubuntu_release} ${local.architecture}"

  launch_block_device_mappings {
    device_name           = "/dev/sda1"
    volume_size           = var.root_volume_size
    volume_type           = "gp3"
    delete_on_termination = true
  }

  # Require IMDSv2 on instances launched from this AMI.
  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 1
    instance_metadata_tags      = "enabled"
  }

  tags = merge({
    Name               = local.ami_name
    OS                 = "ubuntu-${local.ubuntu_release}"
    Architecture       = local.architecture
    K3sVersion         = var.k3s_version
    CertManagerVersion = var.cert_manager_version
    SourceAMI          = data.amazon-ami.ubuntu_noble_arm64.id
    BuildDate          = local.timestamp
    ManagedBy          = "Packer"
  }, var.extra_tags)

  run_tags = {
    Name = "packer-builder-${local.ami_name}"
  }

  run_volume_tags = {
    Name = "packer-builder-${local.ami_name}"
  }

  snapshot_tags = {
    Name       = local.ami_name
    K3sVersion = var.k3s_version
  }
}

build {
  name    = "red-k3s"
  sources = ["source.amazon-ebs.k3s"]

  # Phase 1 skeleton only — provisioners land in Phase 2.
}
