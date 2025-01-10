eks_cluster_role_name     = "eks_cluster_role"
eks_worker_node_role_name = "eks_worker_node_role"
instance_types            = ["t3a.medium"]
capacity_type             = "ON_DEMAND" #"SPOT" #ON_DEMAND
alb_controller_iam_policy = "TerraformAWSLoadBalancerControllerIAMPolicy"
