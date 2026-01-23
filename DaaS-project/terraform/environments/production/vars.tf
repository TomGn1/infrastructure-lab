#Set your public SSH key here
variable "ssh_key" {
  default = "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAACAQCy+dEJOiqA+cpmg/HW8trxgSgZ6vTSVkF/0ypJWaH9pPF6zXtj2vqOdDW6b1kUHjHaKSHN10x5Rmu5u3ByfSoAzXwyd9pHxro/hxwKsNG0luJLCDrEBNo2ch/4bO6NnUPt7A0/+ECwvHx64cavRwA/JWleZyjgejMTjM3qJwAbV9zicRzY7ugFUGJZYB4NT0Gxe9ORKkFEuavm0gSyNlwPPLB1PWwl68tHk56RWrXY/sIVRo89fmYVoPKvv6Rkj3I2zhdy3lkQurJD7r7HiSHUlIOK9R2W95bz3XFIbv6H7kb2vegCMvaq3r4b6LK1VbVFj/saBdFNLC1QPIbJ+ne7lx5g8VAVk6Wd/+fxpIMbd1qxtsThr90tA9G3bYusAvyzr2j72nAzE3nwZwNIjjVRSz735q45cR7JcUoTULNR8q56MHOWUBbYOEsOAgx0zKS+QzbB1dpdeclW76eRdevdiSCd7ZC0Jpg9M11uUEHqyjGiaEc8HYYdJtVLH6qGVzAwmyhuScDMTGamehyw6hN2fb4YulqRGwkwT+tUoaDAUDMUPJY+NxnrZ0f0ncREyDCbQuEz3C6+UYrlqHLiKkXuCj6z8hWiVlG4C3sekvEvNgyNjvirhz0QOeCgjaXfBWyjBEPZ26zBiq0gS+Db3bY2KH+ZUuRoTwp2+W5Goxm/iw== ubuntu_admin@ubuntu-srv"
}
#Establish which Proxmox host you'd like to spin a VM up on
variable "proxmox_host" {
    default = "pve-lab-projet"
}
#Specify which template name you'd like to use
variable "template_name" {
    default = "template-ubuntu-2204"
}
#Establish which nic you would like to utilize
variable "nic_name" {
    default = "vmbr2"
}
#Establish the VLAN you'd like to use
#variable "vlan_num" {
#    default = "place_vlan_number_here"
#}
#Provide the url of the host you would like the API to communicate on.
#It is safe to default to setting this as the URL for what you used
#as your `proxmox_host`, although they can be different
variable "api_url" {
    default = "https://192.168.42.1:8006/api2/json"
}
#Blank var for use by terraform.tfvars
variable "token_secret" {
}
#Blank var for use by terraform.tfvars
variable "token_id" {
}
