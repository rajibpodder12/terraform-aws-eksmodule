output "aws_vpc_id" {
  description = "dispaly default vpc id"
  value = data.aws_vpc.vpc_id.id
}

output "aws_subnets_id" {
  description = "display subnets associated with default vpc"
  value = data.aws_subnets.subnet_ids.ids
}

output "eks_cluster_role_arn" {
  description = "display create eks cluster arn"
  value = aws_iam_role.eks_cluster_role.arn
}

output "eks_cluster_worker_node_role_arn" {
  description = "display eks worker node role arn"
  value = aws_iam_role.eks_node_role.arn
}

output "alb_controller_policy_arn" {
  description = "display alb controller ploicy arn"
  value = aws_iam_policy.alb_controller_policy.arn
}

output "aws_eks_cluster_oidc_info" {
  description = "display oidc provider info"
  #value = split("://",data.aws_eks_cluster.eks_cluster_info.identity[0]["oidc"][*].issuer)[1]
  value = [for i in data.aws_eks_cluster.eks_cluster_info.identity[0]["oidc"][*].issuer : split("://", i)[1]][0]
}

output "ekscluster_endpoint" {
  description = "display eks cluster endpoint"
  value = aws_eks_cluster.ekscluster.endpoint
}

# output "managed_node_group_asg" {
#   value = [for asg in flatten(
#     [for resources in aws_eks_node_group.eks_node_group.resources : resources.autoscaling_groups]
#   ) : asg.name]
# }

output "eks_node_group_name" {
  description = "display eks managed node group name"
  value = aws_eks_node_group.eks_node_group.node_group_name
}

output "managed_node_group_asg" {
  description = "display autoscaling group associated with created managed node group"
  value = [for i in aws_eks_node_group.eks_node_group.resources[0].autoscaling_groups : i.name]
}
