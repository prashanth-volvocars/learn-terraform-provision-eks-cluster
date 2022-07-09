# Create amazon managed prometheus 
resource "aws_prometheus_workspace" "prometheus" {
  alias = "prometheus"
}

provider "helm" {
  kubernetes {
    host                   = data.aws_eks_cluster.cluster.endpoint
    cluster_ca_certificate = base64decode(data.aws_eks_cluster.cluster.certificate_authority.0.data)
    token                  = data.aws_eks_cluster_auth.cluster.token
  }
}

# Create a OIDC provider based on the OIDC url in the cluster
resource "aws_iam_openid_connect_provider" "cluster_oidc" {
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = ["9e99a48a9960b14926bb7f3b02e22da2b0ab7280"]
  url             = data.aws_eks_cluster.cluster.identity.0.oidc.0.issuer
}

# Policy that makes it possible for the kubernetes service accounts to access amazon managed prometheus
data "aws_iam_policy_document" "prometheus_assume_role_policy" {
  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]
    effect  = "Allow"
    condition {
      test     = "StringEquals"
      variable = "${replace(aws_iam_openid_connect_provider.cluster_oidc.url, "https://", "")}:sub"
      values   = ["system:serviceaccount:prometheus:prometheus-service-account"]
    }
    principals {
      identifiers = [aws_iam_openid_connect_provider.cluster_oidc.arn]
      type        = "Federated"
    }
  }
}

# Create a IAM role attach the above role policy.
resource "aws_iam_role" "prometheus_iam_role" {
  assume_role_policy = data.aws_iam_policy_document.prometheus_assume_role_policy.json
  name               = "prometheus-iam-role"
}

data "aws_iam_policy" "amazon_prometheus_query_access" {
  arn = "arn:aws:iam::aws:policy/AmazonPrometheusQueryAccess"
}

data "aws_iam_policy" "amazon_prometheus_remote_write_access" {
  arn = "arn:aws:iam::aws:policy/AmazonPrometheusRemoteWriteAccess"
}

# Attach AmazonPrometheusQueryAccess to prometheus-iam-role
resource "aws_iam_role_policy_attachment" "amazon_prometheus_query_access_policy_attachment" {
  policy_arn = data.aws_iam_policy.amazon_prometheus_query_access.arn
  role       = aws_iam_role.prometheus_iam_role.name
}

# Attach AmazonPrometheusRemoteWriteAccess to prometheus-iam-role
resource "aws_iam_role_policy_attachment" "amazon_prometheus_remote_write_access_policy_attachment" {
  policy_arn = data.aws_iam_policy.amazon_prometheus_remote_write_access.arn
  role       = aws_iam_role.prometheus_iam_role.name
}

resource "helm_release" "prometheus-for-amp" {
  name = "prometheus-for-amp"
  chart = "prometheus-community/prometheus"
  namespace = kubernetes_namespace.prometheus.metadata.0.name
  values = [
    yamlencode(var.prometheus_settings)
  ]
  set {
    name = "serviceAccounts.server.name"
    value = "prometheus-service-account"
  }
  set {
    name = "serviceAccounts.server.annotations.eks\\.amazonaws\\.com/role-arn"
    value = aws_iam_role.prometheus_iam_role.arn
  }
  set {
    name = "server.remoteWrite[0].url"
    value = "https://aps-workspaces.${var.region}.amazonaws.com/workspaces/${aws_prometheus_workspace.prometheus.id}/api/v1/remote_write"
  }
  set {
    name = "server.remoteWrite[0].sigv4.region"
    value = var.region
  }
}

variable "prometheus_settings" {
  default = {
    "kube-state-metrics": {
        "nodeSelector": {
            # "nodename": "prometheus_node"
        }
    }
    "serviceAccounts": {
        "server": {
            "name": "",
            "annotations": {
                "eks.amazonaws.com/role-arn": ""
            }
        },
        "alertmanager": {
            "create": false
        },
        "pushgateway": {
            "create": false
        }
    },
    "server": {
        "nodeSelector": {
            # "nodename": "prometheus_node"
        },
        "remoteWrite": [
            {
                "url": "",
                "sigv4": {
                    "region": ""
                },
                "queue_config": {
                    "max_samples_per_send": 1000,
                    "max_shards": 200,
                    "capacity": 2500
                }
            }
        ],
        "statefulSet": {
            "enabled": true
        },
        "retention": "1h"
    },
    "alertmanager": {
        "enabled": false
    },
    "pushgateway": {
        "enabled": false
    },
    "nodeExporter": {
        "nodeSelector": {
            # "nodename": "prometheus_node"
        }
    }
  }
}



