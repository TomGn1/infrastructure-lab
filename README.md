# Infrastructure Lab

Mon laboratoire d'apprentissage Infrastructure as Code et automatisation.

## À propos

TSSR certifié, c'est en cherchant à automatiser mes déploiements que j'ai découvert le DevOps. Aujourd'hui je gère un homelab où je mets en pratique Terraform, Ansible et Proxmox. 

Objectif 2026-2027 : 
- Décrocher l'AIS pour sécuriser ces infrastructures.
- Déployer un cluster Kubernetes dans mon homelab

## Projets

### Automatisation & IaC
| Projet                                 | Stack                     | Description                             |
| -------------------------------------- | ------------------------- | --------------------------------------- |
| [DaaS Platform](./DaaS-Project/)       | Flask, Terraform, Ansible | Desktop-as-a-Service avec orchestration |
| [Deploy Automation](./Deploy-Project/) | Bash, Terraform, Ansible  | Déploiement automatisé + AD Join        |

### Infrastructure & Réseau  
| Projet               | Stack              | Description                                                 |
| -------------------- | ------------------ | ----------------------------------------------------------- |
| Migration Proxmox    | Proxmox, pfSense   | [Migration cluster OVH](./docs/migration-proxmox.md)        |
| Architecture Homelab | Proxmox, VLANs, HA | [Voir diagramme](./diagrams/diagrammeReseauDoubleNAT.png)   |
| Sauvegarde Homelab   | Veeam, TrueNAS     | [Architecture de Sauvegarde](./docs/backup-architecture.md) |

### Apprentissage en cours

| Sujet      | Ressource                                                          | Statut   |
| ---------- | ------------------------------------------------------------------ | -------- |
| Kubernetes | [Notes & Labs](https://github.com/TomGn1/kubernetes-apprentissage) | En cours |

## Compétences démontrées
- Infrastructure as Code (Terraform)
- Configuration Management (Ansible)
- Virtualisation (Proxmox, VMware)
- Réseau (pfSense, VLANs, HA)
- Scripting (Bash, Python, PowerShell)
- Sauvegarde et stockage (Veeam, TrueNAS)