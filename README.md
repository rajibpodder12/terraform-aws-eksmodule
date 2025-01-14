## Features

Create EKS Cluster, Single managed Node group on Default VPC with multiple EKS Add on [ coredns, vpc-cni, ebs-csi-drive, efs-csi-driver, kube-proxy, ALB controller ] 

## Usage

```
module "eksmodule" {
  source  = "rajibpodder12/eksmodule/aws"
  version = "2.0.0"
  # insert the required variables here
  region = "<region_name>"
  eks_cluster_name = "<eks_cluster_name>"
  eks_cluster_version = "<eks_cluster_version>"
  capacity_type = "<ON_DEMAND|SPOT>"
}

```

## Providers

| Name | Version |
|------|---------|
| aws | 5.82.2 |
|external| 2.3.4 |
|helm| 2.17.0 |
|kubernetes| 2.35.1 |
|local|2.5.2|
|random|3.6.3|
