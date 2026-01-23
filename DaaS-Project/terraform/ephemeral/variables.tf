#variable "vm_name" {
#  description = "desktop-000001"
#  type        = string
#}

variable "ssh_key" {
  default = "<ssh_key>"
}

variable "proxmox_host" {
  default = "pve-lab-projet"
}

variable "template_name" {
  default = "template-ubuntu-desktop"
}

variable "nic_name" {
  default = "vmbr2"
}

variable "api_url" {
  default = "<api_url>"
}

variable "token_secret" {}
variable "token_id" {}
