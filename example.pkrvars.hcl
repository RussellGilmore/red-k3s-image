region        = "us-east-1"
instance_type = "t4g.small"

vpc_id    = "vpc-xxxxxxxxxxxxxxxxx"
subnet_id = "subnet-xxxxxxxxxxxxxxxxx"

# Override any defaults from variables.pkr.hcl here:
# k3s_version          = "v1.34.6+k3s1"
# cert_manager_version = "v1.20.2"
# ami_name_prefix      = "red-k3s"
# root_volume_size     = 20

extra_tags = {
  Owner   = "russell"
  Project = "red-infra"
}
