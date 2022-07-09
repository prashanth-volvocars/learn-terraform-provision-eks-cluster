resource "aws_grafana_workspace" "grafana" {
  account_access_type      = "CURRENT_ACCOUNT"
  authentication_providers = ["AWS_SSO"]
  permission_type          = "CUSTOMER_MANAGED"
  name                     = "grafana"
  data_sources             = ["CLOUDWATCH", "PROMETHEUS"]
  role_arn                 = aws_iam_role.grafana_assume.arn
}

resource "aws_iam_role" "grafana_assume" {
  name = "grafana-assume"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Sid    = ""
        Principal = {
          Service = "grafana.amazonaws.com"
        }
      },
    ]
  })
}

resource "aws_iam_policy" "amazon_cloudwatch_policy" {
  name = "AmazonGrafanaCloudWatchPolicy"
  policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "AllowReadingMetricsFromCloudWatch",
      "Effect": "Allow",
      "Action": [
        "cloudwatch:DescribeAlarmsForMetric",
        "cloudwatch:DescribeAlarmHistory",
        "cloudwatch:DescribeAlarms",
        "cloudwatch:ListMetrics",
        "cloudwatch:GetMetricStatistics",
        "cloudwatch:GetMetricData"
      ],
      "Resource": "*"
    },
    {
      "Sid": "AllowReadingLogsFromCloudWatch",
      "Effect": "Allow",
      "Action": [
        "logs:DescribeLogGroups",
        "logs:GetLogGroupFields",
        "logs:StartQuery",
        "logs:StopQuery",
        "logs:GetQueryResults",
        "logs:GetLogEvents"
      ],
      "Resource": "*"
    },
    {
      "Sid": "AllowReadingTagsInstancesRegionsFromEC2",
      "Effect": "Allow",
      "Action": [
        "ec2:DescribeTags",
        "ec2:DescribeInstances",
        "ec2:DescribeRegions"
      ],
      "Resource": "*"
    },
    {
      "Sid": "AllowReadingResourcesForTags",
      "Effect": "Allow",
      "Action": "tag:GetResources",
      "Resource": "*"
    }
  ]
}
EOF
}

resource "aws_iam_role_policy_attachment" "grafana_amazon_cloudwatch_policy_attachment" {
  policy_arn = aws_iam_policy.amazon_cloudwatch_policy.arn
  role       = aws_iam_role.grafana_assume.name
}

resource "aws_iam_role_policy_attachment" "grafana_amazon_prometheus_query_access_policy_attachment" {
  policy_arn = data.aws_iam_policy.amazon_prometheus_query_access.arn
  role       = aws_iam_role.grafana_assume.name
}

resource "aws_iam_role_policy_attachment" "grafana_amazon_prometheus_console_full_access_policy_attachment" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonPrometheusConsoleFullAccess"
  role = aws_iam_role.grafana_assume.name
}
