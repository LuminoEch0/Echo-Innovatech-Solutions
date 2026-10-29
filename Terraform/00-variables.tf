variable "ssh_public_key" {
  type        = string
  description = "Public SSH key string for administrative SSH access to the VPN host"
}

variable "aws_region" {
  type    = string
  default = "eu-central-1"
}

variable "tunnel_psk" {
  type        = string
  sensitive   = true
  description = "IPsec PSK — injected by pipeline from GitHub secret TUNNEL_PSK"
}

variable "onprem_cidr" {
  type    = string
  default = "192.168.121.0/24"
}

variable "onprem_dns" {
  type    = string
  default = "192.168.121.120"
}

variable "onprem_domain" {
  type    = string
  default = "pfSense.localnetlab" #
}

variable "tunnel_eip_allocation_id" {
  type        = string
  description = "Allocation ID of the manually created Elastic IP for the tunnel"
}

variable "tunnel_private_ip" {
  type        = string
  description = "Allocation of the private IP address for the tunnel and dnsmasq server"
}