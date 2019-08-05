variable "environment_name" {
  type = string
}

variable "owner_name" {
  type = string
}

variable "ttl" {
  type    = number
  default = 48
}

variable "name" {
  type = string
}

variable "instance_type" {
  type    = string
  default = "t3.medium"
}

variable "init_worker_count" {
  type    = number
  default = 3
}

variable "min_worker_count" {
  type    = number
  default = 1
}

variable "max_worker_count" {
  type    = number
  default = 3
}

variable "kubernetes_version" {
  type    = string
  default = null
}


variable "vpc_id" {
  type = string
}

variable "subnet_ids" {
  type = list(string)
}

variable "api_access_cidr_blocks" {
  type    = list(string)
  default = ["0.0.0.0/0"]
}

variable "tags" {
  type    = map
  default = null
}
