# DaaS Platform - Desktop as a Service

Plateforme d'automatisation pour le déploiement et la configuration de machines virtuelles Linux jointes à un domaine Active Directory.

## Vision du projet

Ce projet répond à une problématique concrète rencontrée en entreprise : le déploiement manuel de VMs Linux intégrées à un environnement Active Directory est chronophage, source d'erreurs et difficile à standardiser.

L'objectif est de fournir une solution **Infrastructure as Code** permettant :

- Le provisionnement automatisé de VMs sur Proxmox
- La configuration post-déploiement standardisée
- La jointure automatique au domaine AD
- Un point d'entrée unique pour les équipes techniques

## Évolution du projet

|Aspect|v1 - Deploy-Project|v2 - DaaS-Project|
|---|---|---|
|Orchestration|Script Bash interactif|API Flask + CLI|
|Provisionnement|Terraform|Terraform|
|Configuration|Ansible (AD join)|Ansible (AD join + desktop config)|
|Interface|Menu terminal|API REST|
|État|Fichier tfstate local|Gestion centralisée|

---

## v1 - Deploy-Project

> [**📁 Accéder au projet**](../Deploy-Project)

Première itération du projet, développée comme proof of concept pour valider l'approche IaC.

### Stack technique

- **Bash** : Script orchestrateur avec menu interactif
- **Terraform** : Provisionnement de VMs Ubuntu sur Proxmox via cloud-init
- **Ansible** : Jointure au domaine AD avec SSSD/realmd

### Points clés

- Menu CLI interactif permettant planification, déploiement et configuration
- Inventaire dynamique Python lisant le `terraform.tfstate`
- Gestion des secrets via Ansible Vault
- Mécanismes de sécurité : validation des entrées, backups automatiques, confirmations multiples

---

## v2 - DaaS-Project

> [**📁 Accéder au projet**](#../DaaS-Project)

Évolution vers une architecture orientée services, découplant l'orchestration de l'exécution.

### Stack technique

- **Python/Flask** : API REST pour l'orchestration
- **Terraform** : Provisionnement avec fichiers éphémères
- **Ansible** : Rôles étendus (AD join + configuration desktop)

### Améliorations par rapport à v1

- Architecture modulaire et extensible
- API REST permettant l'intégration avec d'autres outils
- Séparation des responsabilités (orchestrator, terraform, ansible)
- Gestion améliorée des configurations desktop (XRDP, environnement utilisateur)

---

## Technologies utilisées

|Catégorie|Outils|
|---|---|
|IaC|Terraform, Ansible|
|Virtualisation|Proxmox VE|
|Scripting|Bash, Python|
|Identity|Active Directory, SSSD, realmd|
|Backend|Flask (v2)|
