#!/bin/bash
# Script de rollback Terraform d'urgence
# Usage: ./rollback.sh [commit_sha]

set -e  # Arrête si erreur

echo "=========================================="
echo "   SCRIPT DE ROLLBACK TERRAFORM"
echo "=========================================="
echo ""

# Couleurs
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Vérifie qu'on est dans le bon dossier
if [ ! -f "main.tf" ]; then
    echo -e "${RED}Erreur: main.tf non trouvé. Es-tu dans le bon dossier ?${NC}"
    exit 1
fi

# Sauvegarde de sécurité du state actuel
BACKUP_FILE="terraform.tfstate.rollback-$(date +%Y%m%d-%H%M%S)"
if [ -f "terraform.tfstate" ]; then
    cp terraform.tfstate "$BACKUP_FILE"
    echo -e "${GREEN}Backup du state créé: $BACKUP_FILE${NC}"
fi

echo ""
echo "Derniers commits disponibles:"
echo "---"
git log --oneline -10
echo ""

# Demande le commit cible
if [ -z "$1" ]; then
    read -p "SHA du commit vers lequel revenir (ou ENTER pour HEAD~1): " COMMIT
    COMMIT=${COMMIT:-HEAD~1}
else
    COMMIT=$1
fi

echo ""
echo -e "${YELLOW} ATTENTION: Tu vas revenir au commit: $COMMIT${NC}"
git show --stat $COMMIT
echo ""

read -p "Confirmer le rollback vers ce commit ? (yes/no): " CONFIRM

if [ "$CONFIRM" != "yes" ]; then
    echo -e "${RED}Rollback annulé${NC}"
    exit 0
fi

echo ""
echo "Retour au commit $COMMIT..."

# Crée une branche de sauvegarde avant de bouger
CURRENT_BRANCH=$(git branch --show-current)
BACKUP_BRANCH="backup-before-rollback-$(date +%Y%m%d-%H%M%S)"
git branch $BACKUP_BRANCH
echo -e "${GREEN}Branche de backup créée: $BACKUP_BRANCH${NC}"

# Revient au commit voulu
git checkout $COMMIT -- .

echo ""
echo "Changements qui vont être appliqués:"
terraform plan

echo ""
read -p "Appliquer ces changements ? (yes/no): " APPLY_CONFIRM

if [ "$APPLY_CONFIRM" != "yes" ]; then
    echo -e "${RED}Application annulée. Retour à l'état précédent...${NC}"
    git checkout $CURRENT_BRANCH
    exit 0
fi

echo ""
echo "Application du rollback..."
terraform apply -auto-approve

echo ""
echo -e "${GREEN}=========================================="
echo "   ROLLBACK TERMINÉ AVEC SUCCÈS !"
echo "==========================================${NC}"
echo ""
echo "   Informations:"
echo "   - State backup: $BACKUP_FILE"
echo "   - Branche backup: $BACKUP_BRANCH"
echo ""
echo "   Pour annuler ce rollback:"
echo "   git checkout $BACKUP_BRANCH"
echo "   terraform apply"
echo -e "${NC}"
tput sgr0
