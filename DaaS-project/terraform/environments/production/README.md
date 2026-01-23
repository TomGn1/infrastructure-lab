# Infrastructure Terraform - Lab Proxmox

Infrastructure as Code pour le déploiement automatisé de VMs sur Proxmox VE.

## 📋 Prérequis

- Proxmox VE 8.x
- Terraform >= 1.5
- Template Ubuntu 22.04 avec cloud-init configuré
- Accès API Proxmox (token)

## 🚀 Déploiement

### Configuration initiale

1. Copier le fichier d'exemple :
```bash
cp terraform.tfvars.example terraform.tfvars
```

2. Éditer `terraform.tfvars` avec vos valeurs

3. Initialiser Terraform :
```bash
terraform init
```

### Déployer les VMs
```bash
terraform plan    # Prévisualiser les changements
terraform apply   # Appliquer les changements
```

### Détruire les VMs
```bash
terraform destroy
```

## 🔄 Rollback

En cas de problème après un déploiement :
```bash
./rollback.sh
```

Le script vous guidera pour revenir à un état stable précédent.

## 📁 Structure
```
.
├── main.tf                    # Configuration principale
├── vars.tf                    # Déclaration des variables
├── terraform.tfvars          # Valeurs des variables (non versionné)
├── terraform.tfvars.example  # Exemple de configuration
├── rollback.sh               # Script de rollback d'urgence
└── README.md                 # Cette documentation
```

## 🔒 Sécurité

- Les fichiers `terraform.tfvars` et `terraform.tfstate` ne sont **PAS** versionnés (secrets)
- Utiliser des tokens Proxmox avec permissions minimales
- Backups automatiques du state avant chaque rollback

## 📝 Auteur

TomGn1 - Lab personnel

## 📄 Licence

Usage personnel - Lab de formation
