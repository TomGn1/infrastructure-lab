
## I. Structure du Projet :

```bash
/srv/samba/
├── terraform/
│   └── environments/
│       └── production/
│           ├── main.tf              # Clone VMs Ubuntu
│           ├── vars.tf              # Variables (proxmox_host, template, etc.)
│           ├── terraform.tfvars     # Secrets
│           └── terraform.tfstate    # État généré
│
├── ansible/
│   ├── inventory/
│   │   └── inventory.py             # Lit le tfstate
│   ├── playbooks/
│   │   └── join-domain.yml          # Appelle le rôle ad-join
│   ├── roles/
│   │   └── ad-join/
│   │       ├── tasks/main.yml
│   │       ├── defaults/main.yml    # proto.lan, packages realmd/sssd
│   │       └── handlers/main.yml
│   ├── group_vars/
│   │   └── all/
│   │       └── vault.yml            # Mot de passe AD chiffré
│   └── ansible.cfg
│
└── scripts/
    └── deploy-vm.sh                 # Menu interactif bash
```

## II. Terraform :

### 1. Création d'un template de VM sur Proxmox

- Créer un Template d'une VM Linux sur Proxmox (Ubuntu)
https://tcude.net/creating-a-vm-template-in-proxmox/
```bash
# Télécharger Ubuntu Cloud Image
wget https://cloud-images.ubuntu.com/jammy/current/jammy-server-cloudimg-amd64.img

# Créer le template
qm create 9000 --name ubuntu-2204-template --memory 2048 --cores 2 --net0 virtio,bridge=vmbr2
qm importdisk 9000 jammy-server-cloudimg-amd64.img local
qm set 9000 --scsihw virtio-scsi-pci --scsi0 local:9000/vm-9000-disk-0.raw
qm set 9000 --boot c --bootdisk scsi0
qm set 9000 --ide2 local:cloudinit
qm set 9000 --serial0 socket --vga serial0
qm set 9000 --agent enabled=1
qm template 9000
```

### 2. Installation et configurations de Terraform

```bash
# Sur le serveur
cd /tmp
wget https://releases.hashicorp.com/terraform/1.6.0/terraform_1.13.4_linux_amd64.zip
unzip terraform_1.13.4_linux_amd64.zip
sudo mv terraform /usr/local/bin/
terraform version
```

- Créer un utilisateur Terraform sur Proxmox et ajuster ses droits:

```bash
# Sur Proxmox
pveum user add terraform@pve
pveum passwd terraform@pve  # Définir un mot de passe
pveum aclmod / -user terraform@pve -role Administrator
```

- De retour sur notre serveur *ubuntu-srv* définir et organiser la structure pour Terraform

```bash
# Structure Terraform
mkdir -p /srv/samba/terraform/{modules,environments/production}
mkdir -p /srv/samba/terraform/modules/proxmox-vms

# Structure Ansible
mkdir -p /srv/samba/ansible/playbooks
mkdir -p /srv/samba/ansible/inventory
mkdir -p /srv/samba/ansible/templates

```

- On édite le fichier `/srv/samba/terraform/environments/production/terraform.tfvars`

```bash
# Configuration Proxmox
proxmox_api_url  = "<url_api>"
proxmox_user     = "terraform@pve"
proxmox_password = "<mot_de_passe_terraform@pve>"

# Configuration VMs
initial_password = "<mot_de_passe_localadmin>" 
ssh_public_key   = "<clé_ssh_générée>"  
```

>[!Rappel]
>Pour générer une clée SSH pour notre serveur ubuntu-srv
>```bash
># Si pas de clé SSH
ssh-keygen -t rsa -b 4096 -C "ubuntu_admin@ubuntu-srv"
cat ~/.ssh/id_rsa.pub

- Création des fichiers dans lesquels nous stockerons nos variables:
`/srv/samba/terraform/environments/production/terraform.tfvars`

```bash
token_secret = "XXXXXXXX-XXXX-XXXX-XXXX-XXXXXXXXXXXX"
token_id = "terraform@pve!terraform-token"
```

`/srv/samba/terraform/environments/production/vars.tf`

```bash
#Set your public SSH key here
variable "ssh_key" {
  default = "<clé_ssh_du_serveur>"
}
#Establish which Proxmox host you'd like to spin a VM up on
variable "proxmox_host" {
    default = "<nom_hôte>"
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
    default = "<url_api>"
}
#Blank var for use by terraform.tfvars
variable "token_secret" {
}
#Blank var for use by terraform.tfvars
variable "token_id" {
}

```

- Création de fichier `/srv/samba/terraform/environments/production/main.tf` Dans lequel se trouvera la configuration pour déployer nos machines virtuel. Dans notre cas on va configurer le déploiement d'une seule machine de teste.

```bash
terraform {
  required_providers {
    proxmox = {
      source = "telmate/proxmox"
      version = "3.0.2-rc04"
    }
  }
}

provider "proxmox" {
  pm_api_url = var.api_url
  pm_api_token_id = var.token_id
  pm_api_token_secret = var.token_secret
  pm_tls_insecure = true
}

resource "proxmox_vm_qemu" "test_environnement_dev" {
  name = "UBUNTU-DEV${count.index + 1}"
  count = 1
  target_node = var.proxmox_host

  clone = var.template_name
  full_clone = "true"

  agent = 1
  agent_timeout = 300
  os_type = "cloud-init"

  vga {
    type = "std"  # ou "qxl" ou "virtio" 
  }

  cpu {
    type = "host"
    cores = 2
    sockets = 1
  }

  memory = 2048
  scsihw = "virtio-scsi-pci"
  bootdisk = "scsi0"

  disks {
    scsi {
      scsi0 {
        disk {
          size = "50G"
          storage = "local"
          discard = true
        }
      }
    }


  # FORCE LE DISQUE CLOUDINIT
  ide {
    ide2 {
      cloudinit {
        storage = "local"
      }
    }
  }
}

  network {
    id = 0
    model = "virtio"
    bridge = var.nic_name
    #tag = var.vlan_num
  }

  ipconfig0 = "ip=dhcp"

  ciuser = "ubuntu"
  cipassword = "<mot_de_passe>"
  sshkeys = var.ssh_key

  lifecycle {
    ignore_changes = [
      network,
    ]
  }
}


```

>[!ATTENTION]
>Dans les versions récentes de Telmate/Proxmox (3.0.2-rc04) il faut forcer le montage du disque Cloud-init, sans quoi il ne sera pas créer durant le clonage de la VM et celle-ci ne fonctionnera pas.
>```bash
>  # FORCER LE DISQUE CLOUDINIT
>  ide {
>   ide2 {
>      cloudinit {
>        storage = "local"
>      }
>    }
>  }
>}
>```

- Il nous reste plus qu'a tester notre déploiement:

```bash
cd /srv/samba/terraform/environments/production
sudo terraform init
sudo terraform plan
sudo terraform plan -out plan
sudo terraform apply plan
```

---
## III. Ansible :

### 1. Installation

- Installation via PPA officiel :
```bash
sudo apt update && sudo apt upgrade -y
sudo apt install software-properties-common -y 
sudo add-apt-repository --yes --update ppa:ansible/ansible
sudo apt install ansible -y
```

- Vérifier l'installation :
```bash
ansible --version
```

- Installation des dépendances, pour l'inventaire dynamique Python qui lit le fichier *tfstate* :
```bash
sudo apt install python3 python3-pip -y
```

### 2. Configurations

- Création de l'arborescence et définition des permissions :
```bash
sudo mkdir -p /srv/samba/ansible/{inventory,playbooks,roles,group_vars/all}
sudo chown -R ubuntu_admin:ubuntu_admin /srv/samba/ansible
``` 

- Configurer les fichier de configuration d'Ansible *ansible.cfg*
```ini
[defaults]
inventory = inventory/inventory.yaml
host_key_checking = False
retry_files_enabled = False
roles_path = roles
vault_password_file = .vault_pass

[privilege_escalation]
become = True
become_method = sudo
become_user = root
become_ask_pass = False

[ssh_connection]
pipelining = True
```

### 3. Inventaire Ansible :

- Création de l'inventaire `ansible/inventory/inventory.yaml`
```python
#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Inventaire dynamique Ansible qui lit le terraform.tfstate
"""

import json
import sys
import os

# Chemin vers le tfstate
TFSTATE_PATH = "/srv/samba/terraform/environments/production/terraform.tfstate"

def read_tfstate():
    """Lit le fichier terraform.tfstate"""
    if not os.path.exists(TFSTATE_PATH):
        return {"_meta": {"hostvars": {}}}
    
    with open(TFSTATE_PATH, 'r') as f:
        return json.load(f)

def generate_inventory():
    """Génère l'inventaire Ansible depuis le tfstate"""
    tfstate = read_tfstate()
    
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
        }
    }
    
    # Parcourt les ressources dans le tfstate
    for resource in tfstate.get("resources", []):
        if resource.get("type") == "proxmox_vm_qemu":
            for instance in resource.get("instances", []):
                attributes = instance.get("attributes", {})
                
                # Récupère le nom et l'IP
                vm_name = attributes.get("name", "unknown")
                vm_ip = attributes.get("default_ipv4_address")
                
                if vm_ip:
                    # Ajoute au groupe domain_vms
                    inventory["domain_vms"]["hosts"].append(vm_name)
                    
                    # Ajoute les variables spécifiques à cet host
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

- Rendre l'inventaire exécutable :
```bash
chmod +x /srv/samba/ansible/inventory/inventory.yaml
```

- Tester l'inventaire :
```bash
cd /srv/samba/ansible
./inventory/inventory.yaml --list
```

- Création du *vault* pour les secrets :
```bash
cd /srv/samba/ansible
ansible-vault create group_vars/all/vault.yml
```

- Saisir les secrets :
```yaml
--- 
ad_join_password: "MotDePasseDuCompteSvcAnsible"
```

- Tester la connectivité :
```bash
cd /srv/samba/ansible
ansible domain_vms -m ping --ask-vault-pass
```

### 4. Playbook Ansible et rôles

- Création du playbook `ansible/playbooks/join-domain.yml`
```yaml
---
- name: Joindre les VMs Ubuntu au domaine Active Directory proto.lan
  hosts: all
  gather_facts: yes
  become: yes
  
  vars_files:
    - ../group_vars/all/vault.yml  # Charge explicitement le vault
  
  vars:
    ad_domain: "proto.lan"
    ad_dc_ip: "10.0.0.5"
    ad_join_user: "svc_ansible"
    # ad_join_password vient du vault chargé ci-dessus
  
  pre_tasks:
    - name: Vérifier que le mot de passe vault est chargé
      assert:
        that:
          - ad_join_password is defined
          - ad_join_password != "PLACEHOLDER"
        fail_msg: "Le mot de passe du vault n'est pas chargé !"
        success_msg: "Mot de passe vault chargé avec succès"
    
    - name: Afficher les informations de la cible
      debug:
        msg:
          - "Cible: {{ inventory_hostname }}"
          - "IP: {{ ansible_host }}"
          - "User AD: {{ ad_join_user }}"
          - "Password: [CACHÉ]"
  
  roles:
    - ad-join
  
  post_tasks:
    - name: Message de succès
      debug:
        msg:
          - "==========================================="
          - "   VM {{ inventory_hostname }} jointe au domaine !"
          - "==========================================="
          - ""
          - "   Vous pouvez maintenant vous connecter avec :"
          - "   ssh ubuntu_admin@{{ ansible_host }}"
```

Création du rôle *ad-join* :

```bash
mkdir -p /srv/samba/ansible/roles/ad-join/defaults
nano /srv/samba/ansible/roles/ad-join/defaults/main.yml
```

Contenu :
```yaml
---
# Defaults pour le role ad-join

# Configuration du domaine Active Directory
ad_domain: "proto.lan"
ad_realm: "PROTO.LAN"  # En MAJUSCULES
ad_dc_ip: "<ip_serveur>"

# Compte de service pour joindre le domaine
ad_join_user: "svc_ansible"
# Le mot de passe est dans group_vars/all/vault.yml (chiffré)

# Configuration SSSD
ad_use_fqdn: false  # Permet de se connecter avec juste "ubuntu_admin" au lieu de "ubuntu_admin@proto.lan"
ad_fallback_homedir: "/home/%u"  # Crée /home/ubuntu_admin

# Packages nécessaires
ad_packages:
  - realmd
  - sssd
  - sssd-tools
  - libnss-sss
  - libpam-sss
  - adcli
  - samba-common-bin
  - packagekit
  - chrony  # Pour la synchro temps (important pour Kerberos!)
```

```bash
mkdir -p /srv/samba/ansible/roles/ad-join/handlers
nano /srv/samba/ansible/roles/ad-join/handlers/main.yml
```

Contenu :
```yaml
---
# Handlers pour le role ad-join

- name: restart sssd
  service:
    name: sssd
    state: restarted

- name: restart sshd
  service:
    name: sshd
    state: restarted
```

```bash
mkdir -p /srv/samba/ansible/roles/ad-join/tasks
nano /srv/samba/ansible/roles/ad-join/tasks/main.yml
```

Contenu:
```yaml
---
# Tasks pour joindre une VM Ubuntu au domaine Active Directory

- name: Mettre à jour le cache APT
  apt:
    update_cache: yes
    cache_valid_time: 3600
  tags: packages

- name: Installer les packages nécessaires pour AD
  apt:
    name: "{{ ad_packages }}"
    state: present
  tags: packages

- name: Configurer le DNS pour pointer vers le DC
  lineinfile:
    path: /etc/resolv.conf
    line: "nameserver {{ ad_dc_ip }}"
    insertbefore: BOF
    state: present
  tags: dns

- name: Vérifier que le DC est accessible
  command: "ping -c 2 {{ ad_dc_ip }}"
  register: ping_dc
  changed_when: false
  failed_when: ping_dc.rc != 0
  tags: connectivity

- name: Synchroniser l'heure avec le DC (critique pour Kerberos)
  service:
    name: chrony
    state: started
    enabled: yes
  tags: time

- name: Découvrir le domaine Active Directory
  command: "realm discover {{ ad_domain }}"
  register: realm_discover
  changed_when: false
  failed_when:
    - realm_discover.rc != 0
    - "'configured' not in realm_discover.stdout"
  tags: discovery

- name: Afficher les informations du domaine découvert
  debug:
    var: realm_discover.stdout_lines
  tags: discovery

- name: Vérifier si déjà joint au domaine
  command: "realm list"
  register: realm_list
  changed_when: false
  failed_when: false
  tags: check

- name: Joindre le domaine Active Directory
  shell: |
    echo "{{ ad_join_password }}" | realm join --user={{ ad_join_user }} {{ ad_domain }}
  register: join_result
  when: "ad_domain not in realm_list.stdout"
  failed_when:
    - join_result.rc != 0
    - "'Already joined' not in join_result.stderr"
  notify: restart sssd
  tags: join
  #no_log: true  # Cache le mot de passe dans les logs

- name: Configurer SSSD pour utiliser les noms courts
  lineinfile:
    path: /etc/sssd/sssd.conf
    regexp: '^use_fully_qualified_names'
    line: 'use_fully_qualified_names = {{ ad_use_fqdn | lower }}'
    state: present
  notify: restart sssd
  tags: sssd

- name: Configurer SSSD pour le répertoire home
  lineinfile:
    path: /etc/sssd/sssd.conf
    regexp: '^fallback_homedir'
    line: 'fallback_homedir = {{ ad_fallback_homedir }}'
    insertafter: '^\[domain'
    state: present
  notify: restart sssd
  tags: sssd

- name: Autoriser tous les utilisateurs AD à se connecter
  command: "realm permit --all"
  changed_when: false
  tags: permissions

- name: Configurer PAM pour créer les home directories automatiquement
  lineinfile:
    path: /etc/pam.d/common-session
    line: 'session required pam_mkhomedir.so skel=/etc/skel/ umask=0077'
    insertafter: '^session.*pam_unix.so'
    state: present
  tags: pam

- name: Activer l'authentification par mot de passe SSH
  lineinfile:
    path: /etc/ssh/sshd_config
    regexp: '^#?PasswordAuthentication'
    line: 'PasswordAuthentication yes'
  notify: restart sshd
  tags: ssh

- name: Activer KbdInteractive pour PAM/SSSD (nécessaire pour users AD)
  lineinfile:
    path: /etc/ssh/sshd_config
    regexp: '^#?KbdInteractiveAuthentication'
    line: 'KbdInteractiveAuthentication yes'
    state: present
  notify: restart sshd
  tags: ssh

- name: Autoriser le groupe g_linux_admins dans SSH
  lineinfile:
    path: /etc/ssh/sshd_config
    line: 'AllowGroups g_linux_admins sudo'
    regexp: '^AllowGroups'
    insertafter: '^#?PasswordAuthentication'
  notify: restart sshd
  tags: ssh

- name: Vérifier que la jonction a réussi
  command: "realm list"
  register: final_check
  changed_when: false
  tags: verify

- name: Afficher le statut final
  debug:
    msg:
      - "Machine jointe au domaine {{ ad_domain }}"
      - "{{ final_check.stdout_lines }}"
  when: "ad_domain in final_check.stdout"
  tags: verify
```

---

## IV. Script de déploiement de machines virtuelles reliées à un domaine:

- Créer le script `/srv/samba/scripts/deploy.sh` 
```bash
#!/bin/bash

INITIAL_DIR=$(pwd)
TERRAFORM_DIR="/srv/samba/terraform/environments/production"
ANSIBLE_DIR="/srv/samba/ansible"

function printHeader ()
{
    echo -e "\n╔════════════════════════════════════════╗"
    echo -e "║         Déploiement de Machines        ║"
    echo -e "║         Virtuelles sur Proxmox         ║"
    echo -e "╚════════════════════════════════════════╝\n"

}

function enterVm ()
{
    while true; do
        read -p "Combien de machines virtuelles voulez-vous déployer ? " vmCount
        if [[ ! $vmCount =~ ^[0-9]+$ ]]; then
            echo "Erreur. Veuillez entrer un nombre valide."
            continue
        fi

        if [[ $vmCount -lt 1 ]]; then
            echo "Erreur. Le nombre doit être supérieur à 0."
            continue
        fi

        if [[ $vmCount -gt 10 ]]; then
            echo "Attention : un nombre important de machines virtuelles va être créé."
            read -p "Voulez-vous continuer ? (Y/n) " -n 1 -r
            echo
            if [[ ! $REPLY =~ ^[Yy]$ ]]; then
                continue
            fi
        fi
        break
    done
    cd "$TERRAFORM_DIR"
    backupFile="main.tf.backup.$(date +%Y%m%d-%H%M%S)"
    cp main.tf "$backupFile"
    echo "Fichier de restauration créé : $backupFile"
    sed -i '/resource "proxmox_vm_qemu"/,/^}/ s/count = [0-9]*/count = '$vmCount'/' main.tf
    echo "Vérification de la modification :"
    grep "count = " main.tf
    read -p "$vmCount machine(s) virtuelle(s) vont être créée(s), voulez-vous continuez ?" -n 1 -r
        echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo -e "Déploiement annulé, restauration du fichier original..."
        mv "$backupFile" main.tf
        return 1
    fi
    return 0
}

function initTerraform ()
{
    echo -e "Initialisation de Terraform..."
    cd "$TERRAFORM_DIR"
    terraform init
    echo -e "Terraform initialisé avec succès" 
}

function planTerraform ()
{
    echo -e "Planification de l'infrastructure..."
    cd "$TERRAFORM_DIR"
    terraform plan -out plan
    read -p "Voulez-vous appliquer ces changements ? (Y/n): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo -e "Déploiement annulé"
        return 1
    fi
}

function deployTerraform ()
{
    echo -e "Déploiement de l'infrastructure..."
    cd "$TERRAFORM_DIR"
    terraform apply plan
    echo -e "Infrastructure déployée avec succès !"
}

function destroyTerraform ()
{
    echo -e "Destruction des machines virtuelles..."
    cd "$TERRAFORM_DIR"
    terraform destroy
    echo -e "Machines virtuelles détruites."
}

function configurationVm ()
{
    echo -e "Jointure au domaine PROTO.LAN"
    cd "$ANSIBLE_DIR"
    ansible-playbook playbooks/join-domain.yml
    echo -e "Machines jointes au domaine PROTO.LAN."
}

function menuPrincipal ()
{
echo "Quelle tâche voulez vous accomplir ?"
echo "1 - Planification de l'environnement."
echo "2 - Déploiement de machines virtuelles."
echo "3 - Joindre le domaine PROTO.LAN."
echo "4 - Déploiement et jointure au domaine de machines virtuelles."
echo "5 - Destruction des machines virtuelles"
echo "6 - Quitter"
read -p "Choisissez une option [1-6]: " choice
}

printHeader

while true; do
    menuPrincipal

    if [ $choice == "1" ]; then
        initTerraform
        if enterVm; then
            planTerraform
        fi
    elif [ $choice == "2" ]; then
        initTerraform
        if enterVm; then
            if planTerraform; then
                deployTerraform
            fi
        fi
    elif [ $choice == "3" ]; then
        configurationVm
    elif [ $choice == "4" ]; then
        initTerraform
        if enterVm; then
            if planTerraform; then
                deployTerraform
                configurationVm
            fi
        fi
    elif [ $choice == "5" ]; then
        destroyTerraform
    elif [ $choice == "6" ]; then
        cd "$INITIAL_DIR"
        exit 0
    else
        echo -e "Option invalide"
    fi

    if [[ $choice =~ ^[1-5]$ ]]; then
        echo ""
        read -p "Appuyez sur ENTRÉE pour revenir au menu..."
        echo ""
    fi    

done
```


- Rendre le script exécutable :
```bash
chmod +x /srv/samba/scripts/deploy.sh
```

 - Lancer le déploiement en exécutant le script :
 ```bash
 cd /srv/samba/scripts/
 ./deploy.sh
 ```
 


