# 📦 Guide d'installation - DaaS Orchestrator

Ce guide détaille l'installation complète du système Desktop as a Service, de A à Z.

---

## Table des matières

- [Prérequis](#prérequis)
- [Architecture cible](#architecture-cible)
- [Étape 1 : Préparation de l'infrastructure](#étape-1--préparation-de-linfrastructure)
- [Étape 2 : Installation du serveur orchestrateur](#étape-2--installation-du-serveur-orchestrateur)
- [Étape 3 : Configuration Terraform](#étape-3--configuration-terraform)
- [Étape 4 : Configuration Ansible](#étape-4--configuration-ansible)
- [Étape 5 : Déploiement de l'orchestrateur](#étape-5--déploiement-de-lorchestre)
- [Étape 6 : Installation des clients](#étape-6--installation-des-clients)
- [Étape 7 : Tests et validation](#étape-7--tests-et-validation)
- [Dépannage](#dépannage)

---

## Prérequis

### Infrastructure minimale

| Composant | Spécifications |
|-----------|----------------|
| **Serveur orchestrateur** | Ubuntu Server 22.04 LTS, 2 CPU, 4 Go RAM, 20 Go disk |
| **Hyperviseur Proxmox** | Proxmox VE 8.x, 8+ CPU, 32+ Go RAM, 500+ Go storage |
| **Serveur Active Directory** | Windows Server avec AD DS configuré |
| **Serveur Samba** | Samba 4.x avec partages configurés |
| **Réseau** | VLAN/subnet dédié, DHCP fonctionnel |

### Connaissances requises

- Administration Linux (bash, systemd, SSH)
- Notions de réseau (IP, DNS, DHCP)
- Base Active Directory (domaine, utilisateurs)
- Git (clone, commit, push)

### Accès requis

- ✅ Accès SSH root/sudo sur serveur orchestrateur
- ✅ Accès Web à Proxmox (https://proxmox:8006)
- ✅ Compte administrateur AD pour jointure domaine
- ✅ Token API Proxmox avec droits VM.*

---

## Architecture cible
```
┌─────────────────────────────────────────────────────────────┐
│  Réseau 10.0.0.0/24 (vmbr2)                                 │
│                                                              │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐     │
│  │ ubuntu-srv   │  │   Proxmox    │  │  AD Server   │     │
│  │ 10.0.0.7     │  │  10.0.0.1    │  │  10.0.0.2    │     │
│  │ Orchestrateur│  │  Hyperviseur │  │  proto.lan   │     │
│  └──────────────┘  └──────────────┘  └──────────────┘     │
│                                                              │
│  ┌──────────────┐  ┌──────────────────────────────────┐   │
│  │ Samba Server │  │  Desktop VMs (pool dynamique)    │   │
│  │ 10.0.0.3     │  │  10.0.0.150-200                  │   │
│  └──────────────┘  └──────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────┘
```

**DNS** : Tous les serveurs doivent résoudre `proto.lan`

---

## Étape 1 : Préparation de l'infrastructure

### 1.1 Créer le template Ubuntu sur Proxmox
```bash
# Se connecter à Proxmox via SSH
ssh root@10.0.0.1

# Télécharger Ubuntu 22.04 cloud image
cd /var/lib/vz/template/iso
wget https://cloud-images.ubuntu.com/jammy/current/jammy-server-cloudimg-amd64.img

# Créer la VM template
qm create 9000 --name ubuntu-22.04-template --memory 4096 --cores 2 --net0 virtio,bridge=vmbr2

# Importer le disque
qm importdisk 9000 /var/lib/vz/template/iso/jammy-server-cloudimg-amd64.img local-lvm

# Attacher le disque
qm set 9000 --scsihw virtio-scsi-pci --scsi0 local-lvm:vm-9000-disk-0

# Configurer cloud-init
qm set 9000 --ide2 local-lvm:cloudinit
qm set 9000 --boot c --bootdisk scsi0
qm set 9000 --serial0 socket --vga serial0

# Agrandir le disque
qm resize 9000 scsi0 32G

# Convertir en template
qm template 9000
```

### 1.2 Créer le token API Proxmox
```bash
# Via l'interface web Proxmox
# Datacenter → Permissions → API Tokens
# User: root@pam
# Token ID: terraform
# Privileges: VM.* (toutes les permissions VM)

# Sauvegarder le token secret quelque part de sûr
# Format: root@pam!terraform=xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx
```

### 1.3 Vérifier Active Directory
```powershell
# Sur le serveur AD (PowerShell)

# Vérifier le domaine
Get-ADDomain

# Créer un utilisateur de test (si pas déjà fait)
New-ADUser -Name "Test User" `
           -SamAccountName "testuser" `
           -UserPrincipalName "testuser@proto.lan" `
           -AccountPassword (ConvertTo-SecureString "Password123!" -AsPlainText -Force) `
           -Enabled $true

# Vérifier la résolution DNS
nslookup ubuntu-srv.proto.lan
```

### 1.4 Configurer Samba
```bash
# Sur le serveur Samba
# Créer le partage principal si pas déjà fait

# /etc/samba/smb.conf
[Partage]
    path = /srv/samba/partage
    browseable = yes
    read only = no
    valid users = @"PROTO\Domain Users"
    force create mode = 0770
    force directory mode = 0770

# Redémarrer Samba
sudo systemctl restart smbd
```

---

## Étape 2 : Installation du serveur orchestrateur

### 2.1 Préparer le serveur
```bash
# Se connecter au serveur
ssh ubuntu_admin@10.0.0.7

# Mettre à jour le système
sudo apt update && sudo apt upgrade -y

# Installer les dépendances de base
sudo apt install -y git curl wget vim python3 python3-pip python3-venv
```

### 2.2 Installer Terraform
```bash
# Ajouter le repository HashiCorp
wget -O- https://apt.releases.hashicorp.com/gpg | sudo gpg --dearmor -o /usr/share/keyrings/hashicorp-archive-keyring.gpg

echo "deb [signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com $(lsb_release -cs) main" | sudo tee /etc/apt/sources.list.d/hashicorp.list

# Installer Terraform
sudo apt update
sudo apt install terraform -y

# Vérifier l'installation
terraform version
# Output: Terraform v1.x.x
```

### 2.3 Installer Ansible
```bash
# Installer Ansible
sudo apt install -y ansible

# Vérifier l'installation
ansible --version
# Output: ansible [core 2.x.x]

# Installer des collections utiles
ansible-galaxy collection install ansible.posix
ansible-galaxy collection install community.general
```

### 2.4 Créer la structure de dossiers
```bash
# Créer l'arborescence
sudo mkdir -p /srv/samba/{terraform,ansible,orchestrator}
sudo chown -R ubuntu_admin:g_linux_admins /srv/samba

# Vérifier
tree -L 1 /srv/samba
```

---

## Étape 3 : Configuration Terraform

### 3.1 Cloner ou créer les fichiers Terraform
```bash
cd /srv/samba/terraform
mkdir -p ephemeral
cd ephemeral
```

### 3.2 Créer main.tf
```bash
nano main.tf
```
```hcl
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
  pm_api_url      = "https://10.0.0.1:8006/api2/json"
  pm_api_token_id = var.token_id
  pm_api_token_secret = var.token_secret
  pm_tls_insecure = true
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
  target_node = "pve"
  clone       = "ubuntu-22.04-template"
  full_clone  = false
  
  cores   = 2
  memory  = 4096
  sockets = 1
  
  network {
    model  = "virtio"
    bridge = "vmbr2"
  }
  
  disk {
    type    = "scsi"
    storage = "local-lvm"
    size    = "32G"
  }
  
  os_type = "cloud-init"
  
  ipconfig0 = "ip=dhcp"
  
  sshkeys = var.ssh_key
  
  lifecycle {
    ignore_changes = [
      network,
      disk,
    ]
  }
}

output "vm_name" {
  value = local.vm_name
}

output "vm_ip" {
  value = proxmox_vm_qemu.ephemeral_desktop.default_ipv4_address
}

output "vm_id" {
  value = proxmox_vm_qemu.ephemeral_desktop.vmid
}
```

### 3.3 Créer variables.tf
```bash
nano variables.tf
```
```hcl
variable "token_id" {
  description = "Proxmox API Token ID"
  type        = string
  sensitive   = true
}

variable "token_secret" {
  description = "Proxmox API Token Secret"
  type        = string
  sensitive   = true
}

variable "ssh_key" {
  description = "SSH public key for cloud-init"
  type        = string
  default     = "ssh-rsa AAAAB3NzaC1... votre-clé-publique"
}
```

### 3.4 Créer terraform.tfvars (SECRETS)
```bash
nano terraform.tfvars
```
```hcl
token_id     = "root@pam!terraform"
token_secret = "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"
```

**⚠️ IMPORTANT** : Ne JAMAIS commiter ce fichier sur Git !
```bash
# Créer .gitignore
echo "terraform.tfvars" >> .gitignore
echo "*.tfstate*" >> .gitignore
echo ".terraform/" >> .gitignore
```

### 3.5 Initialiser et tester Terraform
```bash
# Initialiser Terraform
terraform init

# Vérifier la configuration
terraform validate

# Prévisualiser
terraform plan

# Test de création (optionnel)
terraform apply -auto-approve

# Vérifier les outputs
terraform output

# Détruire le test
terraform destroy -auto-approve
```

---

## Étape 4 : Configuration Ansible

### 4.1 Créer la structure Ansible
```bash
cd /srv/samba/ansible
mkdir -p {playbooks,roles,inventory,group_vars/all}
```

### 4.2 Créer ansible.cfg
```bash
nano ansible.cfg
```
```ini
[defaults]
inventory = ./inventory/inventory.yaml
vault_password_file = .vault_pass
host_key_checking = False
retry_files_enabled = False
roles_path = ./roles

[privilege_escalation]
become = True
become_method = sudo
become_user = root

[ssh_connection]
pipelining = True
```

### 4.3 Créer le mot de passe Ansible Vault
```bash
# Créer le fichier (JAMAIS commiter sur Git !)
nano .vault_pass
# Taper un mot de passe fort
# Sauvegarder et quitter

chmod 600 .vault_pass
echo ".vault_pass" >> .gitignore
```

### 4.4 Créer le fichier vault.yml (secrets)
```bash
# Créer le fichier chiffré
ansible-vault create group_vars/all/vault.yml
```

Contenu :
```yaml
---
ad_join_password: "MotDePasseAdminAD"
```

### 4.5 Créer l'inventaire dynamique
```bash
nano inventory/inventory.yaml
chmod +x inventory/inventory.yaml
```
```python
#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Inventaire dynamique Ansible qui lit plusieurs terraform.tfstate
"""
import json
import sys
import os

# Chemins vers les tfstate
TFSTATE_PATHS = [
    "/srv/samba/terraform/environments/production/terraform.tfstate",
    "/srv/samba/terraform/ephemeral/terraform.tfstate"
]

def read_tfstate(path):
    """Lit un fichier terraform.tfstate"""
    if not os.path.exists(path):
        return {"resources": []}
    
    with open(path, 'r') as f:
        return json.load(f)

def generate_inventory():
    """Génère l'inventaire Ansible depuis plusieurs tfstate"""
    inventory = {
        "_meta": {
            "hostvars": {}
        },
        "domain_vms": {
            "hosts": [],
            "vars": {
                "ansible_user": "ubuntu",
                "ansible_ssh_private_key_file": "~/.ssh/id_rsa",
                "ansible_python_interpreter": "/usr/bin/python3",
                "ansible_become": True,
                "ansible_become_method": "sudo"
            }
        },
        "ephemeral_desktop": {
            "hosts": [],
            "vars": {
                "ansible_user": "ubuntu",
                "ansible_ssh_private_key_file": "~/.ssh/id_rsa",
                "ansible_python_interpreter": "/usr/bin/python3",
                "ansible_become": True,
                "ansible_become_method": "sudo"
            }
        }
    }
    
    # Parcourir tous les tfstate
    for tfstate_path in TFSTATE_PATHS:
        tfstate = read_tfstate(tfstate_path)
        
        # Déterminer le groupe selon le chemin
        if "ephemeral" in tfstate_path:
            group = "ephemeral_desktop"
        else:
            group = "domain_vms"
        
        # Parcourir les ressources dans le tfstate
        for resource in tfstate.get("resources", []):
            if resource.get("type") == "proxmox_vm_qemu":
                for instance in resource.get("instances", []):
                    attributes = instance.get("attributes", {})
                    
                    # Récupérer le nom et l'IP
                    vm_name = attributes.get("name", "unknown")
                    vm_ip = attributes.get("default_ipv4_address")
                    
                    if vm_ip:
                        # Ajouter au groupe approprié
                        inventory[group]["hosts"].append(vm_name)
                        
                        # Ajouter les variables spécifiques à cet host
                        inventory["_meta"]["hostvars"][vm_name] = {
                            "ansible_host": vm_ip
                        }
    
    return inventory

if __name__ == "__main__":
    if len(sys.argv) == 2 and sys.argv[1] == "--list":
        inventory = generate_inventory()
        print(json.dumps(inventory, indent=2))
    elif len(sys.argv) == 3 and sys.argv[1] == "--host":
        print(json.dumps({}))
    else:
        print("Usage: inventory.yaml --list")
        sys.exit(1)
```

### 4.6 Tester l'inventaire
```bash
# Lister l'inventaire
./inventory/inventory.yaml --list

# Avec ansible
ansible-inventory --list
```

### 4.7 Créer les rôles Ansible

**Note** : Les rôles `ad-join` et `desktop-config` devraient déjà être créés. Vérifier leur présence :
```bash
tree roles/
```

Si manquants, se référer aux fichiers existants ou les recréer selon la documentation technique.

### 4.8 Créer le playbook principal
```bash
nano playbooks/deploy-desktop.yml
```
```yaml
---
- name: Configurer un desktop éphémère
  hosts: ephemeral_desktop
  gather_facts: yes
  become: yes
  
  vars_files:
    - ../group_vars/all/vault.yml
  
  vars:
    vm_name: "{{ inventory_hostname }}"
    orchestrator_url: "http://10.0.0.7:5000"
  
  roles:
    - ad-join
    - desktop-config

  post_tasks:
    - name: Afficher les informations de connexion
      debug:
        msg:
          - "✅ =========================================="
          - "   Desktop {{ vm_name }} prêt !"
          - "==========================================="
          - ""
          - "🖥️  Connexion RDP :"
          - "   Adresse: {{ ansible_host }}:3389"
          - "   Domaine: PROTO"
          - ""
          - "📁 Partage réseau monté automatiquement sur: ~/Partage"
```

### 4.9 Tester Ansible
```bash
# Créer une VM de test avec Terraform
cd /srv/samba/terraform/ephemeral
terraform apply -auto-approve

# Lancer Ansible
cd /srv/samba/ansible
ansible-playbook playbooks/deploy-desktop.yml

# Vérifier que ça fonctionne
# Se connecter en RDP à l'IP affichée

# Nettoyer
cd /srv/samba/terraform/ephemeral
terraform destroy -auto-approve
```

---

## Étape 5 : Déploiement de l'orchestrateur

### 5.1 Créer l'application Flask
```bash
cd /srv/samba/orchestrator
```

**Créer app.py** (utiliser le fichier app.py complet créé précédemment)
```bash
nano app.py
```

Coller le contenu complet de l'orchestrateur Flask.

### 5.2 Créer l'environnement virtuel Python
```bash
# Créer le venv
python3 -m venv venv

# Activer
source venv/bin/activate

# Installer Flask
pip install flask

# Désactiver (pour utiliser le service systemd)
deactivate
```

### 5.3 Tester Flask manuellement
```bash
# Activer le venv
source venv/bin/activate

# Lancer Flask
python app.py

# Dans un autre terminal, tester
curl http://10.0.0.7:5000/
curl http://10.0.0.7:5000/api/sessions

# Arrêter Flask (Ctrl+C)
deactivate
```

### 5.4 Créer le service systemd
```bash
sudo nano /etc/systemd/system/orchestrator-daas.service
```
```ini
[Unit]
Description=Orchestrateur DaaS - Desktop as a Service
After=network.target

[Service]
Type=simple
User=ubuntu_admin
Group=g_linux_admins
WorkingDirectory=/srv/samba/orchestrator
Environment="PATH=/srv/samba/orchestrator/venv/bin:/usr/local/bin:/usr/bin:/bin"
ExecStart=/srv/samba/orchestrator/venv/bin/python /srv/samba/orchestrator/app.py
Restart=always
RestartSec=10

# Logs
StandardOutput=journal
StandardError=journal
SyslogIdentifier=orchestrator-daas

[Install]
WantedBy=multi-user.target
```

### 5.5 Activer et démarrer le service
```bash
# Recharger systemd
sudo systemctl daemon-reload

# Activer au démarrage
sudo systemctl enable orchestrator-daas

# Démarrer
sudo systemctl start orchestrator-daas

# Vérifier le statut
sudo systemctl status orchestrator-daas

# Voir les logs
sudo journalctl -u orchestrator-daas -f
```

### 5.6 Tester l'API
```bash
# Test simple
curl http://10.0.0.7:5000/

# Lister les sessions
curl http://10.0.0.7:5000/api/sessions

# Créer une session (test complet - ça va créer une vraie VM !)
curl -X POST http://10.0.0.7:5000/api/session/create \
  -H "Content-Type: application/json" \
  -d '{"username": "testuser"}'
```

---

## Étape 6 : Installation des clients

### 6.1 Client Windows (PowerShell)

**Sur un poste Windows du domaine** :
```powershell
# Créer le dossier
New-Item -Path "C:\Scripts" -ItemType Directory -Force
```

```powershell
# Créer Request-Desktop.ps1
<#
.SYNOPSIS
    Demande un desktop éphémère via l'orchestrateur DaaS
.DESCRIPTION
    Ce script appelle l'API de l'orchestrateur pour créer un desktop,
    puis lance automatiquement la connexion RDP.
.EXAMPLE
    .\Request-Desktop.ps1
    .\Request-Desktop.ps1 -Username "tom"
#>

param(
    [string]$OrchestratorUrl = "http://10.0.0.7:5000",
    [string]$Username = $env:USERNAME,
    [string]$Domain = "PROTO"
)

# ========================================
# Configuration
# ========================================

$ErrorActionPreference = "Stop"

# Couleurs pour les messages
function Write-Success { Write-Host $args -ForegroundColor Green }
function Write-Info { Write-Host $args -ForegroundColor Cyan }
function Write-Warning { Write-Host $args -ForegroundColor Yellow }
function Write-Error { Write-Host $args -ForegroundColor Red }

# ========================================
# Bannière
# ========================================

Clear-Host
Write-Host @"
╔══════════════════════════════════════════╗
║     Desktop as a Service (DaaS)          ║
║     Orchestrateur Desktop Éphémère       ║
╚══════════════════════════════════════════╝
"@ -ForegroundColor Cyan

Write-Info "`n🚀 Demande de desktop en cours pour: $Username"
Write-Info "📡 Orchestrateur: $OrchestratorUrl`n"

# ========================================
# Étape 1 : Créer la session
# ========================================

Write-Info "📦 Étape 1/3 : Création du desktop..."

try {
    $body = @{
        username = $Username
    } | ConvertTo-Json
    
    $response = Invoke-RestMethod `
        -Uri "$OrchestratorUrl/api/session/create" `
        -Method POST `
        -Body $body `
        -ContentType "application/json" `
        -TimeoutSec 600  # 10 minutes max
    
    Write-Success "✅ Desktop créé avec succès !`n"
    
}
catch {
    Write-Error "❌ Erreur lors de la création du desktop:"
    Write-Error $_.Exception.Message
    Write-Host "`nAppuyez sur une touche pour quitter..."
    $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
    exit 1
}

# ========================================
# Étape 2 : Afficher les informations
# ========================================

Write-Info "📋 Informations de connexion:"
Write-Host "   Session ID  : $($response.session_id)" -ForegroundColor White
Write-Host "   Adresse IP  : $($response.vm_ip)" -ForegroundColor White
Write-Host "   Port RDP    : $($response.rdp_port)" -ForegroundColor White
Write-Host "   Utilisateur : $Username@$Domain" -ForegroundColor White
Write-Host ""

# Sauvegarder le session_id pour la destruction
$SessionId = $response.session_id
$VmIp = $response.vm_ip

# ========================================
# Étape 3 : Connexion RDP
# ========================================

Write-Info "🖥️  Étape 2/3 : Lancement de la connexion RDP..."

# Ajouter le serveur aux hôtes de confiance (supprime la popup)
$registryPath = "HKCU:\Software\Microsoft\Terminal Server Client\Servers\$VmIp"

if (-not (Test-Path $registryPath)) {
    New-Item -Path $registryPath -Force | Out-Null
}

New-ItemProperty -Path $registryPath -Name "CertHash" -Value "00" -PropertyType String -Force | Out-Null

Write-Host "   ✅ Serveur ajouté aux hôtes de confiance" -ForegroundColor Green

# Créer un fichier .rdp temporaire avec configuration
$rdpFile = "$env:TEMP\daas-session-$SessionId.rdp"

$rdpContent = @"
full address:s:$VmIp`:3389
username:s:$Domain\$Username
authentication level:i:0
prompt for credentials:i:0
prompt for credentials on client:i:0
enablecredsspsupport:i:0
disable wallpaper:i:1
disable full window drag:i:1
disable menu anims:i:1
disable themes:i:0
disable cursor setting:i:0
bitmapcachepersistenable:i:1
compression:i:1
audiomode:i:0
redirectprinters:i:0
redirectcomports:i:0
redirectsmartcards:i:0
redirectclipboard:i:1
displayconnectionbar:i:1
autoreconnection enabled:i:1
negotiate security layer:i:1
screen mode id:i:2
use multimon:i:0
desktopwidth:i:1920
desktopheight:i:1080
session bpp:i:32
winposstr:s:0,1,0,0,800,600
allow font smoothing:i:1
"@

# Écrire le fichier .rdp
$rdpContent | Out-File -FilePath $rdpFile -Encoding ASCII

Write-Success "✅ Configuration RDP créée`n"

Write-Info "Utilisez ces credentials pour vous connecter :"
Write-Host "   Domaine     : $Domain" -ForegroundColor Yellow
Write-Host "   Utilisateur : $Username" -ForegroundColor Yellow
Write-Host "   Mot de passe: [Votre mot de passe AD]" -ForegroundColor Yellow
Write-Host ""

Write-Warning "⏳ Lancement du bureau à distance...`n"
Start-Sleep -Seconds 2

# Lancer mstsc avec le fichier .rdp
$mstscProcess = Start-Process mstsc.exe -ArgumentList $rdpFile -PassThru

Write-Success "✅ Connexion RDP lancée !`n"

# ========================================
# Étape 4 : Surveiller la session RDP
# ========================================

Write-Info "📌 Surveillance de la session en cours..."
Write-Info "   (La fenêtre se fermera automatiquement à la déconnexion)`n"

# Attendre que le processus mstsc se termine
$mstscProcess.WaitForExit()

Write-Success "✅ Session RDP terminée !`n"

# Nettoyer le fichier .rdp temporaire
Remove-Item -Path $rdpFile -Force -ErrorAction SilentlyContinue

# ========================================
# Étape 5 : Proposer la destruction
# ========================================

Write-Info "💥 Destruction automatique du desktop..."
Write-Warning "⏳ La VM sera détruite dans 10 secondes (Ctrl+C pour annuler)`n"

# Countdown
for ($i = 10; $i -gt 0; $i--) {
    Write-Host "   ⏱️  $i secondes..." -ForegroundColor Yellow
    Start-Sleep -Seconds 1
}

Write-Host ""

try {
    $destroyBody = "{`"session_id`": `"$SessionId`"}"
    
    $destroyResponse = Invoke-WebRequest `
        -Uri "$OrchestratorUrl/api/session/destroy" `
        -Method POST `
        -Body ([System.Text.Encoding]::UTF8.GetBytes($destroyBody)) `
        -ContentType "application/json; charset=utf-8" `
        -TimeoutSec 300
    
    Write-Success "✅ Desktop détruit avec succès !`n"
    
}
catch {
    Write-Error "❌ Erreur lors de la destruction:"
    Write-Error $_.Exception.Message
}

Write-Host ""
Write-Success "🎉 Terminé !"
Write-Host "Appuyez sur une touche pour quitter..."
$null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
```

**Créer le lanceur VBScript** :
```powershell
# C:\Scripts\Launch-DaaS.vbs
```
```vbscript
Set objShell = CreateObject("Wscript.Shell")
objShell.Run "powershell.exe -NoProfile -ExecutionPolicy Bypass -File ""C:\Scripts\Request-Desktop.ps1""", 1, True
```

**Créer un raccourci sur le bureau** :

1. Clic droit sur le bureau → Nouveau → Raccourci
2. Emplacement : `C:\Scripts\Launch-DaaS.vbs`
3. Nom : "Desktop Éphémère"
4. Changer l'icône (optionnel) : Clic droit → Propriétés → Changer l'icône

### 6.2 Client Linux (bash)

**Sur un poste Linux** :
```bash
# Installer les dépendances
sudo apt install -y curl jq freerdp2-x11

# Créer le script
nano ~/request-desktop.sh
```

```bash
#!/bin/bash
# ========================================
# request-desktop.sh
# Script client pour demander un desktop éphémère via l'orchestrateur DaaS
# ========================================

set -euo pipefail  # Arrêter si une commande échoue

# ========================================
# Configuration
# ========================================

ORCHESTRATOR_URL="${ORCHESTRATOR_URL:-http://10.0.0.7:5000}"
USERNAME="${USER}"
DOMAIN="PROTO"

# Couleurs pour les messages
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Fonctions d'affichage
log_success() { echo -e "${GREEN}✅ $1${NC}"; }
log_info() { echo -e "${CYAN}ℹ️  $1${NC}"; }
log_warning() { echo -e "${YELLOW}⚠️  $1${NC}"; }
log_error() { echo -e "${RED}❌ $1${NC}"; }

# ========================================
# Vérifications préalables
# ========================================

# Vérifier que curl est installé
if ! command -v curl &> /dev/null; then
    log_error "curl n'est pas installé. Installez-le avec: sudo apt install curl"
    exit 1
fi

# Vérifier que xfreerdp est installé
if ! command -v xfreerdp &> /dev/null; then
    log_error "xfreerdp n'est pas installé. Installez-le avec: sudo apt install freerdp2-x11"
    exit 1
fi

# Vérifier que jq est installé (pour parser JSON)
if ! command -v jq &> /dev/null; then
    log_warning "jq n'est pas installé. Installation recommandée: sudo apt install jq"
    USE_JQ=false
else
    USE_JQ=true
fi

# ========================================
# Bannière
# ========================================

clear
echo -e "${CYAN}"
cat << "EOF"
╔══════════════════════════════════════════╗
║     Desktop as a Service (DaaS)          ║
║     Orchestrateur Desktop Éphémère       ║
╚══════════════════════════════════════════╝
EOF
echo -e "${NC}"

log_info "🚀 Demande de desktop en cours pour: $USERNAME"
log_info "📡 Orchestrateur: $ORCHESTRATOR_URL"
echo ""

# ========================================
# Étape 1 : Créer la session
# ========================================

log_info "📦 Étape 1/3 : Création du desktop..."
echo ""

# Créer le body JSON
JSON_BODY=$(cat <<EOF
{
    "username": "$USERNAME"
}
EOF
)

# Appeler l'API
RESPONSE=$(curl -s -X POST \
    -H "Content-Type: application/json" \
    -d "$JSON_BODY" \
    "$ORCHESTRATOR_URL/api/session/create" \
    --max-time 600 \
    -w "\nHTTP_CODE:%{http_code}")

# Extraire le code HTTP
HTTP_CODE=$(echo "$RESPONSE" | grep "HTTP_CODE:" | cut -d: -f2)
RESPONSE_BODY=$(echo "$RESPONSE" | sed '/HTTP_CODE:/d')

# Vérifier le succès
if [ "$HTTP_CODE" != "200" ]; then
    log_error "Échec de la création du desktop"
    log_error "Code HTTP: $HTTP_CODE"
    echo "$RESPONSE_BODY"
    exit 1
fi

log_success "Desktop créé avec succès !"
echo ""

# ========================================
# Étape 2 : Extraire les informations
# ========================================

log_info "📋 Extraction des informations..."

if [ "$USE_JQ" = true ]; then
    # Parser avec jq (propre)
    SESSION_ID=$(echo "$RESPONSE_BODY" | jq -r '.session_id')
    VM_IP=$(echo "$RESPONSE_BODY" | jq -r '.vm_ip')
    RDP_PORT=$(echo "$RESPONSE_BODY" | jq -r '.rdp_port // 3389')
else
    # Parser manuellement (fallback)
    SESSION_ID=$(echo "$RESPONSE_BODY" | grep -o '"session_id":"[^"]*"' | cut -d'"' -f4)
    VM_IP=$(echo "$RESPONSE_BODY" | grep -o '"vm_ip":"[^"]*"' | cut -d'"' -f4)
    RDP_PORT=3389
fi

# Vérifier que les infos sont bien récupérées
if [ -z "$SESSION_ID" ] || [ -z "$VM_IP" ]; then
    log_error "Impossible d'extraire les informations de la réponse"
    echo "$RESPONSE_BODY"
    exit 1
fi

echo ""
log_info "📋 Informations de connexion:"
echo "   Session ID  : $SESSION_ID"
echo "   Adresse IP  : $VM_IP"
echo "   Port RDP    : $RDP_PORT"
echo "   Utilisateur : $USERNAME@$DOMAIN"
echo ""

# ========================================
# Étape 3 : Connexion RDP
# ========================================

log_info "🖥️  Étape 2/3 : Lancement de la connexion RDP..."
log_warning "⏳ Patientez pendant le chargement du bureau distant..."
echo ""

sleep 2

# Options xfreerdp
# /v: = adresse
# /u: = username
# /d: = domain
# /cert:ignore = ignorer les certificats
# /f = fullscreen
# +clipboard = activer le presse-papier
# /dynamic-resolution = résolution dynamique
# /sound:sys:pulse = son via PulseAudio

log_info "Utilisez ces credentials pour vous connecter :"
echo -e "   ${YELLOW}Domaine     : $DOMAIN${NC}"
echo -e "   ${YELLOW}Utilisateur : $USERNAME${NC}"
echo -e "   ${YELLOW}Mot de passe: [Votre mot de passe AD]${NC}"
echo ""

# Lancer xfreerdp en arrière-plan et capturer son PID
xfreerdp /v:$VM_IP:$RDP_PORT \
    /u:$USERNAME \
    /d:$DOMAIN \
    /cert:ignore \
    /dynamic-resolution \
    +clipboard \
    /sound:sys:pulse \
    /f \
    > /dev/null 2>&1 &

XFREERDP_PID=$!

log_success "Connexion RDP lancée (PID: $XFREERDP_PID) !"
echo ""

# ========================================
# Étape 4 : Surveiller la session
# ========================================

log_info "📌 Surveillance de la session en cours..."
log_info "   (Le script attendra la fin de votre session)"
echo ""

# Attendre que xfreerdp se termine
wait $XFREERDP_PID

log_success "Session RDP terminée !"
echo ""

# ========================================
# Étape 5 : Destruction automatique
# ========================================

log_info "💥 Destruction automatique du desktop..."
log_warning "⏳ La VM sera détruite dans 10 secondes (Ctrl+C pour annuler)"
echo ""

# Countdown
for i in {10..1}; do
    echo -ne "   ⏱️  $i secondes...\r"
    sleep 1
done
echo ""

# Appeler l'API de destruction
DESTROY_JSON=$(cat <<EOF
{
    "session_id": "$SESSION_ID"
}
EOF
)

DESTROY_RESPONSE=$(curl -s -X POST \
    -H "Content-Type: application/json" \
    -d "$DESTROY_JSON" \
    "$ORCHESTRATOR_URL/api/session/destroy" \
    --max-time 300 \
    -w "\nHTTP_CODE:%{http_code}")

DESTROY_HTTP_CODE=$(echo "$DESTROY_RESPONSE" | grep "HTTP_CODE:" | cut -d: -f2)

if [ "$DESTROY_HTTP_CODE" = "200" ]; then
    log_success "Desktop détruit avec succès !"
else
    log_error "Erreur lors de la destruction (Code: $DESTROY_HTTP_CODE)"
    echo "$DESTROY_RESPONSE"
fi

echo ""
log_success "🎉 Terminé !"
echo ""
```
```
# Rendre exécutable
chmod +x ~/request-desktop.sh

# Tester
./request-desktop.sh
```

**Créer le raccourci bureau** :
```bash
nano ~/Desktop/DaaS-Desktop.desktop
```
```ini
[Desktop Entry]
Version=1.0
Type=Application
Name=Desktop Éphémère
Comment=Créer un desktop Linux éphémère
Exec=x-terminal-emulator -e '/home/USERNAME/request-desktop.sh; read -p "Appuyez sur Entrée..."'
Icon=computer
Terminal=true
Categories=Network;RemoteAccess;
```

Remplacer `USERNAME` par ton nom d'utilisateur.
```bash
# Rendre exécutable et fiable
chmod +x ~/Desktop/DaaS-Desktop.desktop
gio set ~/Desktop/DaaS-Desktop.desktop metadata::trusted true
```

---

## Étape 7 : Tests et validation

### 7.1 Test de bout en bout

#### Depuis Windows

1. Double-cliquer sur "Desktop Éphémère"
2. Observer la console PowerShell :
   - Création du desktop (2-3 min)
   - Ouverture RDP automatique
3. Se connecter avec credentials AD (Domaine: PROTO)
4. Vérifier :
   - Interface XFCE fonctionne
   - Partage `~/Partage` est monté
   - Applications disponibles
5. Fermer RDP
6. Observer la destruction automatique

#### Depuis Linux

1. Double-cliquer sur l'icône bureau
2. Observer le terminal :
   - Création du desktop
   - Ouverture xfreerdp
3. Se connecter avec credentials AD
4. Vérifier le système
5. Fermer xfreerdp
6. Observer la destruction

### 7.2 Vérifications côté serveur
```bash
# Sur ubuntu-srv

# Vérifier l'orchestrateur
sudo systemctl status orchestrator-daas
sudo journalctl -u orchestrator-daas -n 50

# Vérifier les sessions actives
curl http://10.0.0.7:5000/api/sessions

# Sur Proxmox, vérifier les VMs
# Interface web → VMs
```

### 7.3 Test de charge (optionnel)
```bash
# Créer 3 desktops en parallèle (depuis 3 terminaux)

# Terminal 1
curl -X POST http://10.0.0.7:5000/api/session/create \
  -H "Content-Type: application/json" \
  -d '{"username": "user1"}'

# Terminal 2
curl -X POST http://10.0.0.7:5000/api/session/create \
  -H "Content-Type: application/json" \
  -d '{"username": "user2"}'

# Terminal 3
curl -X POST http://10.0.0.7:5000/api/session/create \
  -H "Content-Type: application/json" \
  -d '{"username": "user3"}'

# Observer les logs
sudo journalctl -u orchestrator-daas -f
```

---

## Dépannage

### Problème : Terraform ne trouve pas le template
```bash
# Vérifier que le template existe
ssh root@10.0.0.1
qm list | grep template

# Si manquant, recréer le template (voir étape 1.1)
```

### Problème : Ansible ne peut pas SSH vers la VM
```bash
# Vérifier que la clé SSH est bien injectée
terraform output

# Vérifier cloud-init sur la VM
ssh ubuntu@<VM_IP>
sudo cloud-init status

# Vérifier la clé
cat ~/.ssh/authorized_keys
```

### Problème : La VM ne rejoint pas le domaine AD
```bash
# SSH sur la VM
ssh ubuntu@<VM_IP>

# Vérifier DNS
nslookup proto.lan

# Vérifier la jointure
realm list

# Tester manuellement
sudo realm join -U Administrator proto.lan
```

### Problème : Le partage Samba ne monte pas
```bash
# SSH sur la VM
ssh ubuntu@<VM_IP>

# Vérifier pam_mount
sudo nano /etc/security/pam_mount.conf.xml

# Tester manuellement
sudo mount -t cifs //10.0.0.3/Partage /mnt/test -o username=testuser,domain=PROTO
```

### Problème : L'orchestrateur ne démarre pas
```bash
# Voir les logs
sudo journalctl -u orchestrator-daas -n 100

# Vérifier les permissions
ls -la /srv/samba/orchestrator/

# Vérifier le PATH
sudo systemctl cat orchestrator-daas | grep Environment

# Tester manuellement
cd /srv/samba/orchestrator
source venv/bin/activate
python app.py
```

### Problème : Le monitoring ne détruit pas la VM
```bash
# SSH sur la VM
ssh ubuntu@<VM_IP>

# Vérifier le service
sudo systemctl status inactivity-monitor

# Voir les logs
sudo journalctl -u inactivity-monitor -f

# Vérifier la connectivité vers l'orchestrateur
curl http://10.0.0.7:5000/api/sessions
```

---

## Maintenance

### Mise à jour du template Ubuntu
```bash
# SSH sur Proxmox
ssh root@10.0.0.1

# Supprimer l'ancien template
qm destroy 9000

# Télécharger la nouvelle image
cd /var/lib/vz/template/iso
wget https://cloud-images.ubuntu.com/jammy/current/jammy-server-cloudimg-amd64.img

# Recréer le template (voir étape 1.1)
```

### Mise à jour de l'orchestrateur
```bash
# Arrêter le service
sudo systemctl stop orchestrator-daas

# Mettre à jour le code
cd /srv/samba/orchestrator
git pull  # Si versionné

# Redémarrer
sudo systemctl start orchestrator-daas
```

### Backup des configurations
```bash
# Créer un backup
cd /srv/samba
tar czf daas-backup-$(date +%Y%m%d).tar.gz \
  terraform/ \
  ansible/ \
  orchestrator/ \
  --exclude="*.tfstate*" \
  --exclude="venv" \
  --exclude=".terraform"

# Sauvegarder ailleurs
scp daas-backup-*.tar.gz user@backup-server:/backups/
```

---

## Prochaines étapes

Après l'installation, consulter :

- [USER_GUIDE.md](USER_GUIDE.md) - Guide utilisateur
- [TECHNICAL.md](TECHNICAL.md) - Documentation technique développeur

---

**🎉 Félicitations ! Votre système DaaS est maintenant opérationnel !**
