terraform {
  required_providers {
    proxmox = {
      source  = "telmate/proxmox"
      version = "3.0.2-rc04"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.0"
    }
  }
}

provider "proxmox" {
  pm_api_url          = var.api_url
  pm_api_token_id     = var.token_id
  pm_api_token_secret = var.token_secret
  pm_tls_insecure     = true
}

# Générer un ID aléatoire pour le nom de VM
resource "random_id" "desktop_id" {
  byte_length = 4
}

locals {
  vm_name = "desktop-${random_id.desktop_id.hex}"
}

resource "proxmox_vm_qemu" "ephemeral_desktop" {
  name        = local.vm_name
  target_node = var.proxmox_host
  clone       = var.template_name  # template-ubuntu-desktop
  full_clone  = true
  agent       = 1
  agent_timeout = 300
  os_type     = "cloud-init"
  
  vga {
    type = "std"
  }
  
  cpu {
    type    = "host"
    cores   = 2
    sockets = 1
  }
  
  memory   = 4096  # Plus de RAM pour desktop
  scsihw   = "virtio-scsi-pci"
  bootdisk = "scsi0"
  
  disks {
    scsi {
      scsi0 {
        disk {
          size    = "50G"
          storage = "local"
          discard = true
        }
      }
    }
    
    ide {
      ide2 {
        cloudinit {
          storage = "local"
        }
      }
    }
  }
  
  network {
    id     = 0
    model  = "virtio"
    bridge = var.nic_name
  }
  
  ipconfig0  = "ip=dhcp"
  ciuser     = "ubuntu"
  cipassword = "rocknroll"
  sshkeys    = var.ssh_key
  
  lifecycle {
    ignore_changes = [network]
  }
}

output "vm_id" {
  value = proxmox_vm_qemu.ephemeral_desktop.vmid
}

output "vm_name" {
  value = local.vm_name
}

output "vm_ip" {
  value = proxmox_vm_qemu.ephemeral_desktop.default_ipv4_address
}
