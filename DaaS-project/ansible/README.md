# Ansible Automation
# Ansible Configuration Management - Lab Proxmox

Automatisation de la configuration des serveurs Ubuntu du lab, notamment la jonction au domaine Active Directory proto.lan.

## Prérequis

- Ansible >= 2.9
- Python3-pexpect
- Accès SSH aux machines cibles (clé SSH configurée)
- Compte de service AD : `svc_ansible@proto.lan`

## Structure
```
.
├── inventory/
│   └── hosts.yml              # Inventaire des machines
├── playbooks/
│   ├── join-domain.yml        # Joindre au domaine AD
│   └── test-connection.yml    # Tester la connectivité
├── roles/
│   └── ad-join/               # Role de jonction AD
│       ├── tasks/
│       ├── defaults/
│       ├── handlers/
│       └── meta/
├── group_vars/
│   └── all/
│       ├── vars.yml           # Variables non-sensibles
│       └── vault.yml          # Secrets (chiffré)
└── README.md
```

## Usage

### 1. Ajouter des VMs à l'inventaire

Éditer `inventory/hosts.yml` :
```yaml
domain_vms:
  hosts:
    vm-1:
      ansible_host: 10.0.0.101
    vm-2:
      ansible_host: 10.0.0.102
```

### 2. Tester la connectivité
```bash
ansible-playbook -i inventory/hosts.yml playbooks/test-connection.yml
```

### 3. Joindre les VMs au domaine
```bash
ansible-playbook -i inventory/hosts.yml playbooks/join-domain.yml --ask-vault-pass
```

**Le vault password vous sera demandé pour déchiffrer les secrets.**

### 4. Vérifier qu'une VM est jointe
```bash
# SSH vers la VM
ssh ubuntu@<IP_VM>

# Vérifier
realm list
id ubuntu_admin@proto.lan
```

## Gestion des secrets

Les secrets (mot de passe AD) sont chiffrés avec Ansible Vault.

### Éditer le vault
```bash
ansible-vault edit group_vars/all/vault.yml
```

### Voir le contenu (sans éditer)
```bash
ansible-vault view group_vars/all/vault.yml
```

### Changer le mot de passe du vault
```bash
ansible-vault rekey group_vars/all/vault.yml
```

## Troubleshooting

### Erreur de connexion SSH
```bash
# Vérifier la clé SSH
ssh -i ~/.ssh/id_rsa ubuntu@<IP_VM>

# Vérifier l'inventaire
ansible-inventory -i inventory/hosts.yml --list
```

### Erreur de découverte du domaine
```bash
# Se connecter à la VM et tester
ssh ubuntu@<IP_VM>
realm discover proto.lan
ping 10.0.0.5
```

### VM déjà jointe

Le playbook détecte automatiquement si la VM est déjà jointe et skip la jonction.

## Auteur

TomGn1 - Lab personnel proto.lan
