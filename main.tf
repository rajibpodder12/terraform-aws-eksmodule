################################################################################
# Extract VPC default VPC ID, AWS Subntes and Generate Random ID and gather eks 
# cluster info
##############################################################################

data "aws_vpc" "vpc_id" {
  #filter {
  #name   = "tag:Name"
  #values = ["primaryvpc"]
  #}
  default = true
}

data "aws_subnets" "subnet_ids" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.vpc_id.id]
  }
  # filter {
  #   name   = "map-public-ip-on-launch"
  #   values = ["true"]
  # }
  # filter {
  #   name   = "tag:Name"
  #   values = ["primaryvpc-subnet-p*"]
  # }
}

data "aws_eks_cluster" "eks_cluster_info" {
  name = aws_eks_cluster.ekscluster.name
}

resource "random_id" "random_id" {
  byte_length = 8
}

################################################################################
# Create IAM Role for EKS Cluster
##############################################################################


locals {
  eks_cluster_role_name = "eks_cluster_role_${random_id.random_id.hex}"
}

resource "aws_iam_role" "eks_cluster_role" {
  assume_role_policy = jsonencode({
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "eks.amazonaws.com"
      }
      }, {
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "eks-fargate-pods.amazonaws.com"
      }
    }]
    Version = "2012-10-17"
  })
  description           = "Allows access to other AWS service resources that are required to operate clusters managed by EKS."
  force_detach_policies = false
  max_session_duration  = 3600
  name                  = local.eks_cluster_role_name
  name_prefix           = null
  path                  = "/"
  permissions_boundary  = null
  tags                  = {}
  tags_all              = {}
}

resource "aws_iam_role_policy_attachment" "attach_policy_with_eks_cluster_role" {
  for_each   = toset(["AmazonEKSVPCResourceController", "AmazonEKSClusterPolicy"])
  policy_arn = "arn:aws:iam::aws:policy/${each.value}"
  role       = aws_iam_role.eks_cluster_role.name
}

################################################################################
# Create EKS Cluster
##############################################################################


locals {
  eks_cluster_name = "terraform-${random_id.random_id.hex}"
}

resource "aws_eks_cluster" "ekscluster" {
  bootstrap_self_managed_addons = false
  enabled_cluster_log_types     = ["api", "audit", "authenticator", "controllerManager", "scheduler"]
  name                          = local.eks_cluster_name
  role_arn                      = aws_iam_role.eks_cluster_role.arn
  version                       = var.eks_cluster_version
  access_config {
    authentication_mode                         = "API_AND_CONFIG_MAP"
    bootstrap_cluster_creator_admin_permissions = true
  }
  kubernetes_network_config {
    ip_family         = "ipv4"
    service_ipv4_cidr = "10.100.0.0/16"
    elastic_load_balancing {
      enabled = false
    }
  }
  tags = {
    managedby   = "Terraform"
    auto-delete = "no"
  }
  upgrade_policy {
    support_type = "EXTENDED"
  }
  vpc_config {
    endpoint_private_access = true
    endpoint_public_access  = true
    public_access_cidrs     = ["0.0.0.0/0"]
    subnet_ids              = data.aws_subnets.subnet_ids.ids
  }
}

################################################################################
# OIDC Association
##############################################################################

data "external" "thumbprint" {
  depends_on = [aws_eks_cluster.ekscluster]
  program    = ["bash", "${path.module}/thumbprint.sh", var.region]
}

resource "aws_iam_openid_connect_provider" "aws_iam_openid_connect_provider" {
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = [data.external.thumbprint.result.thumbprint]
  url             = aws_eks_cluster.ekscluster.identity.0.oidc.0.issuer
}


################################################################################
# Create Worker Node Role for EKS Cluster
##############################################################################

locals {
  eks_worker_node_role_name = "eks_workernode_role_${random_id.random_id.hex}"
}

resource "aws_iam_role" "eks_node_role" {
  assume_role_policy = jsonencode({
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "ec2.amazonaws.com"
      }
    }]
    Version = "2012-10-17"
  })
  description           = "Allows access to other AWS service resources that are required to operate clusters managed by EKS."
  force_detach_policies = false
  max_session_duration  = 3600
  name                  = local.eks_worker_node_role_name
  name_prefix           = null
  path                  = "/"
  permissions_boundary  = null
  tags = {
    managedby   = "Terraform"
    auto-delete = "no"
  }
}

resource "aws_iam_role_policy_attachment" "attach_policy_with_eks_worker_node_role" {
  for_each   = toset(["AmazonEC2ContainerRegistryReadOnly", "AmazonEKS_CNI_Policy", "AmazonEKSWorkerNodePolicy", "AmazonSSMManagedInstanceCore", "service-role/AmazonEBSCSIDriverPolicy", "service-role/AmazonEFSCSIDriverPolicy"])
  policy_arn = "arn:aws:iam::aws:policy/${each.value}"
  role       = aws_iam_role.eks_node_role.name
}


################################################################################
# Create EKS Worker Node based on AL2023 EKS Optimized AMI
##############################################################################

locals {
  eks_node_group_name = "terraform-ng-${random_id.random_id.hex}"
}

resource "aws_eks_node_group" "eks_node_group" {
  ami_type       = "AL2023_x86_64_STANDARD"
  capacity_type  = var.capacity_type
  cluster_name   = aws_eks_cluster.ekscluster.name
  disk_size      = 20
  instance_types = var.instance_types
  labels = {
    "alpha.eksctl.io/cluster-name"   = aws_eks_cluster.ekscluster.name
    "alpha.eksctl.io/nodegroup-name" = local.eks_node_group_name
    role                             = "linuxworkers"
  }
  node_group_name = local.eks_node_group_name
  node_role_arn   = aws_iam_role.eks_node_role.arn
  subnet_ids      = data.aws_subnets.subnet_ids.ids
  tags = {
    auto-delete = "no"
    managedby   = "Terraform"
  }
  tags_all = {
    "alpha.eksctl.io/cluster-name"   = aws_eks_cluster.ekscluster.name
    "alpha.eksctl.io/nodegroup-name" = local.eks_node_group_name
    "alpha.eksctl.io/nodegroup-type" = "managed"
    auto-delete                      = "no"
    managedby                        = "Terraform"
  }
  version = var.eks_cluster_version

  scaling_config {
    desired_size = 1
    max_size     = 1
    min_size     = 1
  }
  update_config {
    max_unavailable = 1
  }

  depends_on = [
    aws_iam_role_policy_attachment.attach_policy_with_eks_worker_node_role,
    aws_eks_cluster.ekscluster
  ]
}

################################################################################
# Create EKS Add ON
##############################################################################

resource "aws_eks_addon" "core_dns" {
  depends_on = [aws_eks_node_group.eks_node_group]
  addon_name = "coredns"
  #addon_version               = "v1.11.4-eksbuild.2"
  cluster_name                = aws_eks_cluster.ekscluster.name
  resolve_conflicts_on_create = "OVERWRITE"
  configuration_values = jsonencode({
    replicaCount = 1
  })
}


resource "aws_eks_addon" "vpc_cni" {
  addon_name = "vpc-cni"
  #addon_version               = "v1.19.2-eksbuild.1"
  cluster_name = aws_eks_cluster.ekscluster.name
  #service_account_role_arn    = ""
  resolve_conflicts_on_create = "OVERWRITE"
}


resource "aws_eks_addon" "kube_proxy" {
  addon_name = "kube-proxy"
  #addon_version = "v1.30.7-eksbuild.2"
  cluster_name = aws_eks_cluster.ekscluster.name
}


resource "aws_eks_addon" "eks_pod_identity_agent" {
  addon_name = "eks-pod-identity-agent"
  #addon_version               = "v1.3.4-eksbuild.1"
  cluster_name                = aws_eks_cluster.ekscluster.name
  resolve_conflicts_on_create = "OVERWRITE"
}


resource "aws_eks_addon" "aws_efs_csi_driver" {
  depends_on = [aws_eks_addon.core_dns, aws_eks_addon.vpc_cni, aws_eks_addon.kube_proxy]
  addon_name = "aws-efs-csi-driver"
  #addon_version = "v2.1.3-eksbuild.1"
  cluster_name = aws_eks_cluster.ekscluster.name
  #service_account_role_arn    = ""
  resolve_conflicts_on_create = "OVERWRITE"
}


resource "aws_eks_addon" "aws_ebs_csi_driver" {
  depends_on = [aws_eks_addon.core_dns, aws_eks_addon.vpc_cni, aws_eks_addon.kube_proxy]
  addon_name = "aws-ebs-csi-driver"
  #addon_version = "v1.38.1-eksbuild.1"
  cluster_name = aws_eks_cluster.ekscluster.name
  #service_account_role_arn    = ""
  resolve_conflicts_on_create = "OVERWRITE"
}





################################################################################
# Tags for the ASG to support cluster-autoscaler scale up from 0
##############################################################################

data "aws_autoscaling_group" "eks_nodegroup_asg" {
  name = aws_eks_node_group.eks_node_group.resources[0].autoscaling_groups[0].name
}

locals {
  cluster_autoscaler_asg_tags = {
    "Name" = "${aws_eks_node_group.eks_node_group.node_group_name}_${random_id.random_id.hex}"
  }

}

resource "aws_autoscaling_group_tag" "cluster_autoscaler_label_tags" {
  for_each = local.cluster_autoscaler_asg_tags

  autoscaling_group_name = aws_eks_node_group.eks_node_group.resources[0].autoscaling_groups[0].name

  tag {
    key   = each.key
    value = each.value

    propagate_at_launch = true
  }
}

resource "null_resource" "action" {
  depends_on = [
    aws_eks_node_group.eks_node_group,
    aws_eks_addon.core_dns,
    aws_eks_addon.kube_proxy,
    aws_eks_addon.vpc_cni,
    aws_eks_addon.aws_ebs_csi_driver,
    aws_eks_addon.aws_efs_csi_driver
  ]
  provisioner "local-exec" {
    command = <<-EOT
    aws autoscaling update-auto-scaling-group --auto-scaling-group-name  ${aws_eks_node_group.eks_node_group.resources[0].autoscaling_groups[0].name} --min-size 0 --region ${var.region}
    aws autoscaling update-auto-scaling-group --auto-scaling-group-name  ${aws_eks_node_group.eks_node_group.resources[0].autoscaling_groups[0].name} --desired-capacity 0 --region ${var.region}
    sleep 20
    aws autoscaling update-auto-scaling-group --auto-scaling-group-name  ${aws_eks_node_group.eks_node_group.resources[0].autoscaling_groups[0].name} --min-size ${data.aws_autoscaling_group.eks_nodegroup_asg.min_size} --region ${var.region}
    aws autoscaling update-auto-scaling-group --auto-scaling-group-name  ${aws_eks_node_group.eks_node_group.resources[0].autoscaling_groups[0].name} --desired-capacity ${data.aws_autoscaling_group.eks_nodegroup_asg.desired_capacity} --region ${var.region}
    EOT
  }
}

################################################################################
# Create ALB Controller IAM Role
##############################################################################


data "aws_caller_identity" "current" {}

locals {
  alb_controller_iam_policy = "alb_controller_iam_policy_${random_id.random_id.hex}"
}

resource "aws_iam_policy" "alb_controller_policy" {
  name        = local.alb_controller_iam_policy
  path        = "/"
  description = local.alb_controller_iam_policy

  policy = file(("${path.module}/alb_iam_policy.json"))
}

locals {
  oidc_issuer = [for i in data.aws_eks_cluster.eks_cluster_info.identity[0]["oidc"][*].issuer : split("://", i)[1]][0]
}


data "aws_iam_policy_document" "alb_controller_assume" {

  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = ["arn:aws:iam::${data.aws_caller_identity.current.account_id}:oidc-provider/${local.oidc_issuer}"]
    }

    condition {
      test     = "StringEquals"
      variable = "${local.oidc_issuer}:sub"

      values = [
        "system:serviceaccount:kube-system:aws-load-balancer-controller",
      ]
    }

    condition {
      test     = "StringEquals"
      variable = "${local.oidc_issuer}:aud"

      values = [
        "sts.amazonaws.com"
      ]
    }

    effect = "Allow"
  }
}

resource "aws_iam_role" "alb_controller" {
  name               = "${aws_eks_cluster.ekscluster.name}-alb-controller"
  assume_role_policy = data.aws_iam_policy_document.alb_controller_assume.json
}

resource "aws_iam_role_policy_attachment" "alb_controller" {
  role       = aws_iam_role.alb_controller.name
  policy_arn = aws_iam_policy.alb_controller_policy.arn
}


################################################################################
# ALB Controller installation via Helm and Kubernetes provider
##############################################################################


data "aws_eks_cluster" "default" {
  name = aws_eks_cluster.ekscluster.name
}

data "aws_eks_cluster_auth" "default" {
  name = aws_eks_cluster.ekscluster.name
}

provider "kubernetes" {

  host                   = data.aws_eks_cluster.default.endpoint
  cluster_ca_certificate = base64decode(data.aws_eks_cluster.default.certificate_authority[0].data)
  token                  = data.aws_eks_cluster_auth.default.token
}

provider "helm" {
  kubernetes {
    host                   = data.aws_eks_cluster.default.endpoint
    cluster_ca_certificate = base64decode(data.aws_eks_cluster.default.certificate_authority[0].data)
    token                  = data.aws_eks_cluster_auth.default.token
  }
}

resource "local_file" "kubeconfig" {
  content = templatefile("${path.module}/kubeconfig.tpl", {
    cluster_name = aws_eks_cluster.ekscluster.name,
    clusterca    = data.aws_eks_cluster.default.certificate_authority[0].data,
    endpoint     = data.aws_eks_cluster.default.endpoint,
  })
  filename = "./kubeconfig-${aws_eks_cluster.ekscluster.name}"

}

resource "kubernetes_service_account" "alb_controller" {
  metadata {
    name      = "aws-load-balancer-controller"
    namespace = "kube-system"
    annotations = {
      "eks.amazonaws.com/role-arn" = aws_iam_role.alb_controller.arn
    }
  }
}

resource "helm_release" "alb-controller" {
  depends_on = [kubernetes_service_account.alb_controller, aws_eks_addon.core_dns]
  name       = "aws-load-balancer-controller"
  repository = "https://aws.github.io/eks-charts"
  chart      = "aws-load-balancer-controller"
  #version    = "1.5.4" #"1.11.0"
  namespace  = "kube-system"

  set {
    name  = "clusterName"
    value = aws_eks_cluster.ekscluster.name
  }
  set {
    name  = "serviceAccount.create"
    value = "false"
  }
  set {
    name  = "serviceAccount.name"
    value = "aws-load-balancer-controller"
  }

  set {
    name  = "region"
    value = var.region
  }
  set {
    name  = "vpcId"
    value = data.aws_vpc.vpc_id.id
  }

}


################################################################################
# Integrate AMP with EKS Cluster
##############################################################################

resource "aws_prometheus_workspace" "example" {
  alias = "example"

  tags = {
    Environment = "Dev"
  }
}

resource "aws_prometheus_scraper" "example" {
  depends_on = [ null_resource.action ]
  source {
    eks {
      cluster_arn = data.aws_eks_cluster.eks_cluster_info.arn
      subnet_ids  = data.aws_eks_cluster.eks_cluster_info.vpc_config[0].subnet_ids
    }
  }

  destination {
    amp {
      workspace_arn = aws_prometheus_workspace.example.arn
    }
  }

  scrape_configuration = <<EOT
global:
   scrape_interval: 30s
   external_labels:
     clusterArn: ${data.aws_eks_cluster.eks_cluster_info.arn}
scrape_configs:
  - job_name: pod_exporter
    kubernetes_sd_configs:
      - role: pod
  - job_name: cadvisor
    scheme: https
    authorization:
      type: Bearer
      credentials_file: /var/run/secrets/kubernetes.io/serviceaccount/token
    kubernetes_sd_configs:
      - role: node
    relabel_configs:
      - action: labelmap
        regex: __meta_kubernetes_node_label_(.+)
      - replacement: kubernetes.default.svc:443
        target_label: __address__
      - source_labels: [__meta_kubernetes_node_name]
        regex: (.+)
        target_label: __metrics_path__
        replacement: /api/v1/nodes/$1/proxy/metrics/cadvisor
  # apiserver metrics
  - scheme: https
    authorization:
      type: Bearer
      credentials_file: /var/run/secrets/kubernetes.io/serviceaccount/token
    job_name: kubernetes-apiservers
    kubernetes_sd_configs:
    - role: endpoints
    relabel_configs:
    - action: keep
      regex: default;kubernetes;https
      source_labels:
      - __meta_kubernetes_namespace
      - __meta_kubernetes_service_name
      - __meta_kubernetes_endpoint_port_name
  # kube proxy metrics
  - job_name: kube-proxy
    honor_labels: true
    kubernetes_sd_configs:
    - role: pod
    relabel_configs:
    - action: keep
      source_labels:
      - __meta_kubernetes_namespace
      - __meta_kubernetes_pod_name
      separator: '/'
      regex: 'kube-system/kube-proxy.+'
    - source_labels:
      - __address__
      action: replace
      target_label: __address__
      regex: (.+?)(\\:\\d+)?
      replacement: $1:10249
  # Scheduler metrics
  - job_name: 'ksh-metrics'
    kubernetes_sd_configs:
    - role: endpoints
    metrics_path: /apis/metrics.eks.amazonaws.com/v1/ksh/container/metrics
    scheme: https
    bearer_token_file: /var/run/secrets/kubernetes.io/serviceaccount/token
    relabel_configs:
    - source_labels:
      - __meta_kubernetes_namespace
      - __meta_kubernetes_service_name
      - __meta_kubernetes_endpoint_port_name
      action: keep
      regex: default;kubernetes;https
  # Controller Manager metrics
  - job_name: 'kcm-metrics'
    kubernetes_sd_configs:
    - role: endpoints
    metrics_path: /apis/metrics.eks.amazonaws.com/v1/kcm/container/metrics
    scheme: https
    bearer_token_file: /var/run/secrets/kubernetes.io/serviceaccount/token
    relabel_configs:
    - source_labels:
      - __meta_kubernetes_namespace
      - __meta_kubernetes_service_name
      - __meta_kubernetes_endpoint_port_name
      action: keep
      regex: default;kubernetes;https
EOT
}

######Creating amp-iamproxy-ingest-role Role

data "aws_iam_policy_document" "amp_iamproxy_ingest_assume" {

  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = ["arn:aws:iam::${data.aws_caller_identity.current.account_id}:oidc-provider/${local.oidc_issuer}"]
    }

    condition {
      test     = "StringEquals"
      variable = "${local.oidc_issuer}:sub"

      values = [
        "system:serviceaccount:prometheus:amp-iamproxy-ingest-service-account",
      ]
    }

    condition {
      test     = "StringEquals"
      variable = "${local.oidc_issuer}:aud"

      values = [
        "sts.amazonaws.com"
      ]
    }

    effect = "Allow"
  }
}

resource "aws_iam_policy" "PermissionPolicyIngest" {
  name        = "PermissionPolicyIngest_${random_id.random_id.hex}"
  path        = "/"
  description = "PermissionPolicyIngest"

  # Terraform's "jsonencode" function converts a
  # Terraform expression result to valid JSON syntax.
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [
          "aps:RemoteWrite", 
          "aps:GetSeries", 
          "aps:GetLabels",
          "aps:GetMetricMetadata"
        ]
        Effect   = "Allow"
        Resource = "*"
      },
    ]
  })
}


resource "aws_iam_role" "amp_iamproxy_ingest_role" {
  name               = "amp_iamproxy_ingest_role_${random_id.random_id.hex}"
  assume_role_policy = data.aws_iam_policy_document.amp_iamproxy_ingest_assume.json
}

resource "aws_iam_role_policy_attachment" "amp_iamproxy_ingest_role" {
  role       = aws_iam_role.amp_iamproxy_ingest_role.name
  policy_arn = aws_iam_policy.PermissionPolicyIngest.arn
}

##create  amp_iamproxy_role.yaml file


resource "local_file" "amp_prometheus_tpl" {
  content = templatefile("${path.module}/amp_prometheus.tpl", {
    amp_ingest_role = aws_iam_role.amp_iamproxy_ingest_role.arn,
    prometheus_endpoint = aws_prometheus_workspace.example.prometheus_endpoint
    region = var.region
  })
  filename = "${path.cwd}/amp_prometheus_${random_id.random_id.hex}.yaml"

}

### Deploying prometheus

resource "kubernetes_namespace" "prometheus" {
  depends_on = [ aws_prometheus_workspace.example,aws_prometheus_scraper.example ]
  metadata {
    name = "prometheus"
  }
}

resource "helm_release" "prometheus" {
  depends_on = [ kubernetes_namespace.prometheus,aws_prometheus_workspace.example,aws_prometheus_scraper.example ]
  name = "prometheus"
  repository = "https://prometheus-community.github.io/helm-charts"
  chart = "prometheus"
  namespace = kubernetes_namespace.prometheus.id
  create_namespace = true
  values = [file("${path.cwd}/amp_prometheus_${random_id.random_id.hex}.yaml")]
  timeout = 3000
  set {
    name = "server.persistentVolume.enabled"
    value = false
  }
  set {
    name = "alertmanager.enabled"
    value = false
  }
  set {
    name = "prometheus-pushgateway.enabled"
    value = false
  }
}

#######Create Grafana

######Creating amp-iamproxy-ingest-role Role

data "aws_iam_policy_document" "prometheus_query" {

  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = ["arn:aws:iam::${data.aws_caller_identity.current.account_id}:oidc-provider/${local.oidc_issuer}"]
    }

    condition {
      test     = "StringEquals"
      variable = "${local.oidc_issuer}:sub"

      values = [
       "system:serviceaccount:grafana:amp-iamproxy-query-service-account"
      ]
    }

    condition {
      test     = "StringEquals"
      variable = "${local.oidc_issuer}:aud"

      values = [
        "sts.amazonaws.com"
      ]
    }

    effect = "Allow"
  }
}

resource "aws_iam_policy" "prometheus_query" {
  name        = "prometheus_query_${random_id.random_id.hex}"
  path        = "/"
  description = "prometheus_query"

  # Terraform's "jsonencode" function converts a
  # Terraform expression result to valid JSON syntax.
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [
                "aps:GetLabels",
                "aps:GetMetricMetadata",
                "aps:GetSeries",
                "aps:QueryMetrics"
        ]
        Effect   = "Allow"
        Resource = "*"
      },
    ]
  })
}


resource "aws_iam_role" "grafana_query_role" {
  name               = "grafana_role_${random_id.random_id.hex}"
  assume_role_policy = data.aws_iam_policy_document.prometheus_query.json
}

resource "aws_iam_role_policy_attachment" "grafana_query_role" {
  role       = aws_iam_role.grafana_query_role.name
  policy_arn = aws_iam_policy.prometheus_query.arn
}

##create  amp_iamproxy_role.yaml file


resource "local_file" "grafana_query_override_values" {
  content = templatefile("${path.module}/amp_query_override_values.tpl", {
    grafana_ingest_role = aws_iam_role.grafana_query_role.arn
  })
  filename = "${path.cwd}/amp_query_override_values_${random_id.random_id.hex}.yaml"

}

### Deploying grafana

resource "kubernetes_namespace" "grafana" {
  depends_on = [null_resource.action]
  metadata {
    name = "grafana"
  }
}

resource "helm_release" "grafana" {
  depends_on = [ kubernetes_namespace.grafana]
  name = "grafana"
  repository = "https://grafana.github.io/helm-charts"
  chart = "grafana"
  namespace = kubernetes_namespace.grafana.id
  create_namespace = true
  values = [file("${path.cwd}/amp_query_override_values_${random_id.random_id.hex}.yaml")]
}
