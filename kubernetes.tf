# Kubernetes provider
# https://learn.hashicorp.com/terraform/kubernetes/provision-eks-cluster#optional-configure-terraform-kubernetes-provider
# To learn how to schedule deployments and services using the provider, go here: https://learn.hashicorp.com/terraform/kubernetes/deploy-nginx-kubernetes

# The Kubernetes provider is included in this file so the EKS module can complete successfully. Otherwise, it throws an error when creating `kubernetes_config_map.aws_auth`.
# You should **not** schedule deployments and services in this workspace. This keeps workspaces modular (one for provision EKS, another for scheduling Kubernetes resources) as per best practices.

provider "kubernetes" {
  host                   = data.aws_eks_cluster.cluster.endpoint
  token                  = data.aws_eks_cluster_auth.cluster.token
  cluster_ca_certificate = base64decode(data.aws_eks_cluster.cluster.certificate_authority.0.data)
  # config_path    = "~/.kube/config"
}

resource "kubernetes_cluster_role" "github_oidc_cluster_role" {
    metadata {
        name = "github-oidc-cluster-role"
    }

    rule {
        api_groups  = ["*"]
        resources   = ["deployments","pods","services"]
        verbs       = ["get", "list", "watch", "create", "update", "patch", "delete"]
    }
}

resource "kubernetes_cluster_role_binding" "github_oidc_cluster_role_binding" {
  metadata {
    name = "github-oidc-cluster-role-binding"
  }

  subject {
    kind = "User"
    name =  "github-oidc-auth-user"
    api_group = "rbac.authorization.k8s.io"
  }

  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "ClusterRole"
    name      = kubernetes_cluster_role.github_oidc_cluster_role.metadata[0].name
  }
}

resource "kubernetes_config_map" "aws-auth" {
  data = {
    "mapRoles" = yamlencode([
      {
        "groups": ["system:bootstrappers", "system:nodes"],
        "rolearn": data.aws_iam_role.workers.arn
        "username": "system:node:{{EC2PrivateDNSName}}"
      },
      {
        "groups": ["system:bootstrappers", "system:nodes", "system:node-proxier"],
        "rolearn": data.aws_iam_role.fargate.arn
        "username": "system:node:{{SessionName}}"
      },
      {
        "rolearn": aws_iam_role.github_oidc_auth_role.arn
        "username": "github-oidc-auth-user"
        
      }
    ])

    "mapAccounts" = yamlencode([])
    "mapUsers" = yamlencode([])
  }

  metadata {
    name      = "aws-auth"
    namespace = "kube-system"
    labels = {
      "app.kubernetes.io/managed-by" = "Terraform"
      "terraform.io/module"          = "terraform-aws-modules.eks.aws"
    }
  }
}

resource "kubernetes_namespace" "prometheus" {
  metadata {
    name = "prometheus"
  }
}

data "aws_secretsmanager_secret_version" "github_container_registry" {
  secret_id = "GithubContainerRegistryAccess"
}

resource "kubernetes_secret" "ghcr_cred" {
  metadata {
    name = "ghcr-cred"
    namespace = "default"
  }

  type = "kubernetes.io/dockerconfigjson"
  
  data = {
    ".dockerconfigjson" = jsonencode({
      auths = {
        "ghcr.io" = {
          "username" = jsondecode(data.aws_secretsmanager_secret_version.github_container_registry.secret_string)["username"]
          "password" = jsondecode(data.aws_secretsmanager_secret_version.github_container_registry.secret_string)["password"]
          "email"    = jsondecode(data.aws_secretsmanager_secret_version.github_container_registry.secret_string)["email"]
          "auth"     = base64encode("${jsondecode(data.aws_secretsmanager_secret_version.github_container_registry.secret_string)["username"]}:${jsondecode(data.aws_secretsmanager_secret_version.github_container_registry.secret_string)["password"]}")
        }
      }
    })
  }
}
