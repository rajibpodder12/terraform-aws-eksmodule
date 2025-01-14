variable "eks_cluster_version" {
    description = "input intended cluster version"
}
variable "instance_types" {
    description = "input intended intended instance types"
}
variable "capacity_type" {
    description = "input capacity type whether it is ON_DEMAND or SPOT"
}
variable "region" {
    description = "input the AWS REGION"
}
