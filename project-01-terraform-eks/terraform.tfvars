aws_region             = "us-east-1"
environment            = "prod"
project                = "cleerly"
cluster_name           = "cleerly-prod"
kubernetes_version     = "1.30"

vpc_cidr               = "10.0.0.0/16"
availability_zones     = ["us-east-1a", "us-east-1b", "us-east-1c"]
private_subnet_cidrs   = ["10.0.1.0/24", "10.0.2.0/24", "10.0.3.0/24"]
public_subnet_cidrs    = ["10.0.101.0/24", "10.0.102.0/24", "10.0.103.0/24"]

node_min_size          = 2
node_max_size          = 10
node_desired_size      = 3
node_instance_types    = ["m5.xlarge"]
