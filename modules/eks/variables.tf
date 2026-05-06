variable "cluster_name" {
  description = "EKS cluster name"
  type        = string
}

variable "kubernetes_version" {
  description = "Kubernetes version"
  type        = string
  default     = "1.30"
}

variable "vpc_id" {
  description = "VPC ID where the cluster will be deployed"
  type        = string
}

variable "private_subnet_ids" {
  description = "List of private subnet IDs for the cluster"
  type        = list(string)
}

variable "environment" {
  description = "Deployment environment"
  type        = string
}

variable "node_min_size" {
  description = "Minimum nodes in general node group"
  type        = number
  default     = 2
}

variable "node_max_size" {
  description = "Maximum nodes in general node group"
  type        = number
  default     = 10
}

variable "node_desired_size" {
  description = "Desired nodes in general node group"
  type        = number
  default     = 3
}

variable "node_instance_types" {
  description = "Instance types for general node group"
  type        = list(string)
  default     = ["m5.xlarge"]
}
