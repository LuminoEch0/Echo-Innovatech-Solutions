variable "ssh_public_key" {
  type        = string
  description = "Public SSH key string for administrative SSH access to the VPN host"
}

variable "aws_region" {
  type    = string
  default = "eu-central-1"
}