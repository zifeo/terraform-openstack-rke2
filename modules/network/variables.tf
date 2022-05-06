variable "name" {
  type = string
}

variable "external_net" {
  type = string
}

variable "ip_version" {
  type = number
}

variable "cidr" {
  type = string
}

variable "dns_nameservers" {
  type = list(string)
}


