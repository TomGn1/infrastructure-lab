#!/bin/bash
BACKUP_DIR=~/terraform-backups
DATE=$(date +%Y%m%d-%H%M%S)
cp /srv/samba/terraform/environments/production/terraform.tfstate \
   $BACKUP_DIR/terraform.tfstate.$DATE

# Rétention de 30 jours
ls -t $BACKUP_DIR/terraform.tfstate.* | tail -n +31 | xargs rm -f
echo "State backed up to $BACKUP_DIR/terraform.tfstate.$DATE"
