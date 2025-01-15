variable "eks_cluster_version" {
    description = "input intended cluster version"
    type = string
}
variable "instance_types" {
    description = "input intended instance types"
    type = list(string)
}
variable "capacity_type" {
    description = "input capacity type whether it is ON_DEMAND or SPOT"
    type = string
}
variable "region" {
    description = "input the AWS REGION"
    type = string
}
