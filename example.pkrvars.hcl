region        = "us-east-1"
instance_type = "t4g.small"

vpc_id    = "vpc-xxxxxxxxxxxxxxxxx"
subnet_id = "subnet-xxxxxxxxxxxxxxxxx"

iam_instance_profile = "PackerBuildRole"
# Network resources to get around this cost money :(
associate_public_ip_address = true

# Override any defaults from variables.pkr.hcl here:
# k3s_version          = "v1.34.6+k3s1"
# helm_version         = "v3.20.1"
# ami_name_prefix      = "red-k3s"
# root_volume_size     = 20

extra_tags = {
  Owner   = "russell"
  Project = "red-infra"
}
