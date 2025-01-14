output "aws_vpc_id" {
  value = data.aws_vpc.vpc_id.id
}

output "aws_subnets_id" {
  value = data.aws_subnets.subnet_ids.ids
}

output "eks_cluster_role_arn" {
  value = aws_iam_role.eks_cluster_role.arn
}

output "eks_cluster_worker_node_role_arn" {
  value = aws_iam_role.eks_node_role.arn
}

output "alb_controller_policy_arn" {
  value = aws_iam_policy.alb_controller_policy.arn
}

output "aws_eks_cluster_oidc_info" {
  #value = split("://",data.aws_eks_cluster.eks_cluster_info.identity[0]["oidc"][*].issuer)[1]
  value = [for i in data.aws_eks_cluster.eks_cluster_info.identity[0]["oidc"][*].issuer : split("://", i)[1]][0]
}

output "ekscluster_endpoint" {
  value = aws_eks_cluster.ekscluster.endpoint
}

# output "managed_node_group_asg" {
#   value = [for asg in flatten(
#     [for resources in aws_eks_node_group.eks_node_group.resources : resources.autoscaling_groups]
#   ) : asg.name]
# }

output "eks_node_group_name" {
  value = aws_eks_node_group.eks_node_group.node_group_name
}

output "managed_node_group_asg" {
  value = [for i in aws_eks_node_group.eks_node_group.resources[0].autoscaling_groups : i.name]
}
