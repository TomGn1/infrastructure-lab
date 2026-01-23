# Guide d'installation - DaaS Orchestrator

Ce guide détaille l'installation complète du système Desktop as a Service, de A à Z.

---

## Table des matières

- [Prérequis](#prérequis)
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
- ✅ Token API Proxmox avec droits VM.

---

## Étape 1 : Préparation de l'infrastructure

### 1.1 Créer le template Ubuntu sur Proxmox
```bash
# Se connecter à Proxmox via SSH
ssh root@<ip_hôte>

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
ssh ubuntu_admin@<ip_serveur>

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

>[!CAUTION]
>**IMPORTANT** : Ne JAMAIS commiter ce fichier sur Git !

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
    # Si appelé avec --list, retourne l'inventaire complet
    if len(sys.argv) == 2 and sys.argv[1] == "--list":
        inventory = generate_inventory()
        print(json.dumps(inventory, indent=2))
    
    # Si appelé avec --host, retourne les vars de l'host
    elif len(sys.argv) == 3 and sys.argv[1] == "--host":
        # Les hostvars sont déjà dans _meta, donc on retourne un dict vide
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
  hosts: all
  gather_facts: yes
  become: yes
  
  vars_files:
    - ../group_vars/all/vault.yml
  
  vars:
    vm_name: "{{ inventory_hostname }}"
    # Ces variables seront passées en extra-vars
    # session_user: "user123"
    # session_password: "MotDePasseTemporaire"
    # vm_name: "desktop-abc123"
    
  roles:
    - ad-join          # Réutilise ton rôle existant
    - desktop-config   # Nouveau rôle pour la config desktop

  post_tasks:
    - name: Afficher les informations de connexion
      debug:
        msg:
          - "==========================================="
          - "   Desktop {{ vm_name }} prêt !"
          - "==========================================="
          - ""
          - "   Connexion RDP :"
          - "   Adresse: {{ ansible_host }}:3389"
          - "   Utilisateur: {{ session_user | default('ubuntu_admin@domaine.name') }}"
          - ""
          - "   Partage réseau monté sur: ~/Partage"
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
curl http://<ip_serveur>:5000/
curl http://<ip_serveur>:5000/api/sessions

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
curl http://<ip_serveur>:5000/

# Lister les sessions
curl http://<ip_serveur>:5000/api/sessions

# Créer une session (test complet - ça va créer une vraie VM !)
curl -X POST http://<ip_serveur>:5000/api/session/create \
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

- Placer le script [Request-Desktop-GUI.ps1](../scripts/Request-Desktop-GUI.ps1) dans le nouveau dossier.
- Placer le lanceur VBScript [run_request-desktop-gui.vbs](../scripts/run_request-desktop-gui.vbs)

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

- Coller le contenu du script [request-desktop.sh](../scripts/request-desktop.sh)

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
curl http://<ip_serveur>:5000/api/sessions

# Sur Proxmox, vérifier les VMs
# Interface web → VMs
```

### 7.3 Test de charge (optionnel)
```bash
# Créer 3 desktops en parallèle (depuis 3 terminaux)

# Terminal 1
curl -X POST http://<ip_serveur>:5000/api/session/create \
  -H "Content-Type: application/json" \
  -d '{"username": "user1"}'

# Terminal 2
curl -X POST http://<ip_serveur>:5000/api/session/create \
  -H "Content-Type: application/json" \
  -d '{"username": "user2"}'

# Terminal 3
curl -X POST http://<ip_serveur>:5000/api/session/create \
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
ssh root@<ip_hôte>
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
sudo mount -t cifs //<ip_samba>/Partage /mnt/test -o username=testuser,domain=PROTO
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
curl http://<ip_serveur>:5000/api/sessions
```

---

## Maintenance

### Mise à jour du template Ubuntu
```bash
# SSH sur Proxmox
ssh root@<ip_hôte>

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

