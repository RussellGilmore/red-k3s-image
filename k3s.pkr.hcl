locals {
  timestamp      = formatdate("YYYYMMDD-hhmmss", timestamp())
  ami_name       = "${var.ami_name_prefix}-${local.timestamp}"
  ubuntu_release = "noble-24.04"
  architecture   = "arm64"
}

# Always pick the newest Canonical Noble 24.04 arm64 image at build time
# instead of pinning to a dated snapshot. This way every bake starts from
# a fresh, fully-patched base.
data "amazon-ami" "ubuntu_noble_arm64" {
  filters = {
    name                = "ubuntu/images/hvm-ssd-gp3/ubuntu-${local.ubuntu_release}-${local.architecture}-server-*"
    root-device-type    = "ebs"
    virtualization-type = "hvm"
  }
  owners      = [var.source_ami_owner]
  most_recent = true
  region      = var.region
}

source "amazon-ebs" "k3s" {
  region                      = var.region
  instance_type               = var.instance_type
  vpc_id                      = var.vpc_id
  subnet_id                   = var.subnet_id
  associate_public_ip_address = var.associate_public_ip_address

  iam_instance_profile = var.iam_instance_profile
  communicator         = "ssh"
  ssh_interface        = "session_manager"
  ssh_username         = var.ssh_username

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

  provisioner "shell" {
    script          = "scripts/00-wait-cloud-init.sh"
    execute_command = "sudo -E bash '{{ .Path }}'"
  }

  provisioner "shell" {
    script          = "scripts/10-apt-baseline.sh"
    execute_command = "sudo -E bash '{{ .Path }}'"
    # apt can take a few minutes after a fresh release
    timeout = "15m"
  }

  provisioner "shell" {
    script          = "scripts/15-install-ssm-agent.sh"
    execute_command = "sudo -E bash '{{ .Path }}'"
  }

  provisioner "shell" {
    script          = "scripts/20-system-tuning.sh"
    execute_command = "sudo -E bash '{{ .Path }}'"
  }

  provisioner "shell" {
    script          = "scripts/30-install-k3s.sh"
    execute_command = "{{.Vars}} sudo --preserve-env=K3S_VERSION bash '{{ .Path }}'"
    environment_vars = [
      "K3S_VERSION=${var.k3s_version}",
    ]
  }

  # NOTE: source = "files" copies the *contents* of files/ directly into
  # the destination — no nested files/ dir. STAGING in script 40 matches this.
  provisioner "file" {
    source      = "files"
    destination = "/tmp/red-k3s-staging"
  }

  provisioner "shell" {
    script          = "scripts/40-install-helm-and-stage-assets.sh"
    execute_command = "{{.Vars}} sudo --preserve-env=CERT_MANAGER_VERSION,HELM_VERSION bash '{{ .Path }}'"
    environment_vars = [
      "CERT_MANAGER_VERSION=${var.cert_manager_version}",
      "HELM_VERSION=${var.helm_version}",
    ]
  }

  provisioner "shell" {
    script          = "scripts/50-install-bootstrap.sh"
    execute_command = "sudo -E bash '{{ .Path }}'"
  }


  provisioner "shell" {
    script          = "scripts/99-cleanup.sh"
    execute_command = "sudo -E bash '{{ .Path }}'"
  }
}
