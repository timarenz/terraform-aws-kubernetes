locals {
  common_tags = {
    environment = var.environment_name
    owner       = var.owner_name
    ttl         = var.ttl
  }
  kubeconfig = templatefile("${path.module}/templates/kubeconfig.yaml.tmpl", {
    endpoint              = aws_eks_cluster.main.endpoint
    certificate_authority = aws_eks_cluster.main.certificate_authority.0.data
    name                  = var.name
  })

  config_map_aws_auth = templatefile("${path.module}/templates/config-map-aws-auth.yaml.tmpl", {
    arn = aws_iam_role.worker.arn
  })
}

resource "aws_iam_role" "master" {
  name               = "eks-master-${var.name}"
  assume_role_policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Service": "eks.amazonaws.com"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
EOF
}

resource "aws_iam_role_policy_attachment" "AmazonEKSClusterPolicy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
  role = aws_iam_role.master.name
}

resource "aws_iam_role_policy_attachment" "AmazonEKSServicePolicy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSServicePolicy"
  role = aws_iam_role.master.name
}

resource "aws_security_group" "master" {
  name = "eks-master-${var.name}"
  vpc_id = var.vpc_id

  egress {
    from_port = 0
    to_port = 0
    protocol = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.common_tags, var.tags == null ? {} : var.tags, { Name = "eks-master-${var.name}" })
}

resource "aws_security_group_rule" "master" {
  type = "ingress"
  protocol = "tcp"
  from_port = 443
  to_port = 443
  security_group_id = "${aws_security_group.master.id}"
  cidr_blocks = var.api_access_cidr_blocks
}

resource "aws_cloudwatch_log_group" "main" {
  name = "/aws/eks/${var.name}/cluster"
  retention_in_days = 7
  tags = merge(local.common_tags, var.tags == null ? {} : var.tags, { Name = "eks-logging-${var.name}" })
}

resource "aws_eks_cluster" "main" {
  depends_on = [
    aws_iam_role_policy_attachment.AmazonEKSClusterPolicy,
    aws_iam_role_policy_attachment.AmazonEKSServicePolicy
  ]

  name = var.name
  version = var.kubernetes_version
  role_arn = aws_iam_role.master.arn

  enabled_cluster_log_types = [
    "api",
    "audit",
    "authenticator",
    "controllerManager",
    "scheduler"
  ]

  vpc_config {
    security_group_ids = ["${aws_security_group.master.id}"]
    subnet_ids = var.subnet_ids
  }
}

resource "aws_iam_role" "worker" {
  name = "eks-worker-${var.name}"

  assume_role_policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Service": "ec2.amazonaws.com"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
EOF
}

resource "aws_iam_role_policy_attachment" "AmazonEKSWorkerNodePolicy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"
  role       = "${aws_iam_role.worker.name}"
}

resource "aws_iam_role_policy_attachment" "AmazonEKS_CNI_Policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
  role       = "${aws_iam_role.worker.name}"
}

resource "aws_iam_role_policy_attachment" "AmazonEC2ContainerRegistryReadOnly" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
  role       = "${aws_iam_role.worker.name}"
}

resource "aws_iam_instance_profile" "worker" {
  name = "eks-worker-${var.name}"
  role = "${aws_iam_role.worker.name}"
}

resource "aws_security_group" "worker" {
  name   = "eks-worker-${var.name}"
  vpc_id = var.vpc_id

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.common_tags, var.tags == null ? {} : var.tags, {
    Name                                = "eks-worker-${var.name}"
    "kubernetes.io/cluster/${var.name}" = "owned"
  })
}

resource "aws_security_group_rule" "worker_self" {
  type                     = "ingress"
  protocol                 = "-1"
  from_port                = 0
  to_port                  = 65535
  security_group_id        = aws_security_group.worker.id
  source_security_group_id = aws_security_group.worker.id
}

resource "aws_security_group_rule" "worker_master" {
  type                     = "ingress"
  protocol                 = "tcp"
  from_port                = 1025
  to_port                  = 65535
  security_group_id        = aws_security_group.worker.id
  source_security_group_id = aws_security_group.master.id
}

resource "aws_security_group_rule" "master_worker" {
  type                     = "ingress"
  protocol                 = "tcp"
  from_port                = 443
  to_port                  = 443
  security_group_id        = aws_security_group.master.id
  source_security_group_id = aws_security_group.worker.id
}

data "aws_ami" "worker" {
  filter {
    name   = "name"
    values = ["amazon-eks-node-${aws_eks_cluster.main.version}-v*"]
  }

  most_recent = true
  owners      = ["602401143452"] # Amazon EKS AMI Account ID
}

data "aws_region" "current" {}

locals {
  worker-userdata = <<EOF
#!/bin/bash
set -o xtrace
/etc/eks/bootstrap.sh --apiserver-endpoint '${aws_eks_cluster.main.endpoint}' --b64-cluster-ca '${aws_eks_cluster.main.certificate_authority.0.data}' '${var.name}'
EOF
}

resource "aws_launch_configuration" "worker" {
  associate_public_ip_address = true
  iam_instance_profile = aws_iam_instance_profile.worker.name
  image_id = data.aws_ami.worker.id
  instance_type = var.instance_type
  name_prefix = "${var.name}-worker-"
  security_groups = [aws_security_group.worker.id]
  user_data_base64 = base64encode(local.worker-userdata)

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_autoscaling_group" "worker" {
  desired_capacity = var.init_worker_count
  launch_configuration = aws_launch_configuration.worker.id
  max_size = var.max_worker_count
  min_size = var.min_worker_count
  name = "${var.name}-worker"
  vpc_zone_identifier = var.subnet_ids

  tag {
    key = "Name"
    value = "${var.name}-worker"
    propagate_at_launch = true
  }

  tag {
    key = "kubernetes.io/cluster/${var.name}"
    value = "owned"
    propagate_at_launch = true
  }
}

resource "null_resource" "config_map_aws_auth" {
  depends_on = [aws_eks_cluster.main]

  triggers = {
    kubeconfig = local.kubeconfig
    config_map_aws_auth = local.config_map_aws_auth
    endpoint = aws_eks_cluster.main.endpoint
  }

  provisioner "local-exec" {
    working_dir = path.module
    command = <<EOF
echo "${null_resource.config_map_aws_auth.triggers.kubeconfig}" > eks-tmp-kubeconfig.yaml & \
echo "${null_resource.config_map_aws_auth.triggers.config_map_aws_auth}" > eks-tmp-config-map-aws-auth.yaml & \
kubectl apply -f eks-tmp-config-map-aws-auth.yaml --kubeconfig eks-tmp-kubeconfig.yaml &\
sleep 1; \
# rm -rf eks-tmp-config-map-aws-auth.yaml eks-tmp-kubeconfig.yaml;
EOF
}
}
