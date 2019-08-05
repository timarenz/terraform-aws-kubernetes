output "id" {
  value = aws_eks_cluster.main.id
}

output "version" {
  value = aws_eks_cluster.main.version
}

output "endpoint" {
  value = aws_eks_cluster.main.endpoint
}

output "certificate_authority" {
  value = aws_eks_cluster.main.certificate_authority.0.data
}

output "kubeconfig" {
  value = local.kubeconfig
}

output "config_map_aws_auth" {
  value = local.config_map_aws_auth
}
