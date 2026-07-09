variable "cluster_name" {
  description = "Name of the EKS cluster"
  type        = string
  default     = "helios"
}

variable "region" {
  description = "AWS region to provision into"
  type        = string
  default     = "us-east-1"
}

variable "kubernetes_version" {
  description = "EKS Kubernetes version"
  type        = string
  default     = "1.30"
}

variable "node_instance_types" {
  description = "Instance types for the default managed node group"
  type        = list(string)
  default     = ["m6i.large"]
}

variable "min_nodes" {
  type    = number
  default = 3
}

variable "max_nodes" {
  type    = number
  default = 10
}

variable "desired_nodes" {
  type    = number
  default = 3
}

variable "vpc_cidr" {
  type    = string
  default = "10.42.0.0/16"
}
