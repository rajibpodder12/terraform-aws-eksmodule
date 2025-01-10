## Features
1. spin up EC2 instance based on amazon linux2 on default VPC public subnet

## Usage

```
module "ec2module" {
  source  = "rajibpodder12/eksmodule/aws"
  version = "1.0.0"
  # insert the 1 required variables here
  region = "<region_name>"
  eks_cluster_name = "<eks_cluster_name>"
  eks_cluster_version = "<eks_cluster_version>"
  eks_node_group_name = "<eks_node_group_name>"
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
