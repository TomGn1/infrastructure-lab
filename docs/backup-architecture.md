
# I. **Composants de l’infrastructure**

J’ai commencé par mettre en place l’environnement de backup. Ainsi, j’ai installé et configuré un serveur de stockage réseau (Network Attached Storage - NAS) à l’aide de la solution TrueNAS. Les sauvegardes sont stockées dans un dataset hébergé au sein d’un pool configuré en RAIDZ1.

Dans un second temps, j’ai mis en place un serveur Veeam Backup & Replication 12. Il est important de noter que ce serveur n’est pas joint au domaine, afin de se prémunir contre la propagation d'attaques en cas de compromission du domaine.

L’agent Veeam, déployé sur le contrôleur de domaine, communique avec le serveur Veeam B&R via le port TCP 6160. Les données sauvegardées transitent par le serveur Veeam qui les écrit sur TrueNAS via le protocole NFSv4.1, dans le dataset « backup », prévu à cet effet.

Afin de respecter la règle de sauvegarde 3-2-1, les backups sont copiés vers un second serveur TrueNAS situé hors du datacenter OVH. Cette réplication s’effectue via une connexion VPN WireGuard sécurisée entre le serveur Veeam et ce NAS.

Schéma de l’architecture mise en place en **[Annexe n°11](#Annexe11)**.

# II. **Infrastructure de stockage**

## 1. **Niveau de RAID**

Les deux NAS ont leurs pools configurés en RAIDZ1 (un équivalent du RAID5, utilisé par le système de fichiers ZFS) qui permet de tolérer la panne d’un seul disque sans perte de données. Celui-ci assure un niveau de protection des données grâce à un système de parité distribuée. Si un disque vient à tomber en panne, les données sont reconstruites automatiquement à partir des disques restants.

Même si d’autres niveaux de RAID plus élevés renforcent la tolérance aux pannes, le RAIDZ1 offre un compromis suffisant entre performance, capacité de stockage et sécurité dans le contexte de cet exemple.

**Configuration des pools** :
- Pool TrueNAS principal : 3 disques virtuels de 100 Go en RAIDZ1 ;
- Pool TrueNAS distant : 3 disques HDD de 600 Go en RAIDZ1.

## 2. **Partage réseau via NFS :**

J’ai choisi d’utiliser le protocole NFS pour Veeam, car celui-ci possède plusieurs avantages :

- Des performances optimales pour les opérations de lecture/écriture ;
- Une gestion fine des permissions au niveau des fichiers ;
- Des compatibilités avec des fonctionnalités avancées de Veeam (ex. : synthetic full, déduplication).

Sur le serveur TrueNAS principal, le dataset de backup est exposé via un partage NFSv4.1 avec les caractéristiques suivantes :
- Serveur : 10.0.0.18
- Export NFS : /mnt/storage/backup

Sur le serveur TrueNAS distant, les caractéristiques sont les suivantes :
- Serveur : 192.168.1.250
- Export NFS : /mnt/storage/replicat_backup

L’accès à ce partage NFS est restreint par l’adresse IP. Ainsi seul le serveur Veeam (10.0.0.19) est autorisé à monter ce partage, cela limite les risques d’accès non autorisés.

Le serveur TrueNAS principal a été intégré au domaine (PROTO.LAN). Les permissions POSIX du dataset sont ainsi configurées pour autoriser le compte de service PROTO\SVC-VEEAM-BU en lecture et écriture, permettant au service Veeam d’écrire les fichiers de sauvegarde.

# III. **Planification et configuration de la tâche de sauvegarde**

## 1. **Analyse des besoins**

Même si cet exemple concerne la sauvegarde de mon contrôleur de domaine (WINSRV-DEV), celui-ci assure plusieurs fonctions critiques dans l’infrastructure. En effet il permet l’authentification centralisée avec le rôle d’Active Directory ; les résolutions DNS interne ; la gestion des stratégies de groupes ; ainsi que des comptes de services importants, qui assurent le bon fonctionnement des projets et des applications.

C’est pourquoi la défaillance de ce serveur aurait des conséquences nuisibles sur l’ensemble du domaine, telles que l’impossibilité de se connecter pour les utilisateurs ainsi que l’arrêt des services applicatifs dépendants.

Dans ce contexte, un RPO (Recovery Point Objective) de 24 heures a été choisi. En effet les modifications dans l’AD sont peu fréquentes et un RPO plus court nécessiterait des backups plus fréquents, ce qui m’impose une contrainte d’espace disque supplémentaire sans bénéfice proportionnel. Le choix a donc été fait de tolérer la perte maximale des modifications sur l’AD des dernières 24 heures.

Un RTO (Recovery Time Objective) de 4 heures définit le temps maximal acceptable pour assurer la restauration du contrôleur de domaine de manière opérationnelle. Le choix de 4 heures a été calculé en prenant en compte la taille des backup (environ 35Go) et la bande passante disponible (1 Gb/s).

**Calcul du RTO** :
- Téléchargement du backup depuis TrueNAS : environ 30 min (35Go à 1Gb/s)
- Restauration Veeam : environ 1h30
- Démarrage et validation : environ 30 min
- Test et remise en service : environ 1h
- Total estimé à 3h30, avec une fenêtre de 30 minutes pour gérer les imprévus.

## 2. **Types de sauvegardes**

Les tâches de sauvegarde (backup jobs) mises en place sont effectuées sur une période hebdomadaire. Elle débute le dimanche à 23H par une sauvegarde complète de la machine (Entire Computer), ensuite chaque jour à 23H une sauvegarde incrémentielle est effectuée.

Le dimanche suivant, une sauvegarde complète est reconstruite à partir de la dernière sauvegarde complète et de ses incréments (Synthetic full backup).

Dans un souci d’optimisation de l’espace de stockage j’ai choisi de planifier une sauvegarde complète par semaine et six sauvegardes incrémentielles, qui copient uniquement les données modifiées depuis la sauvegarde précédente.

## 3. **Politiques de rétention (GFS)**

La stratégie GFS (Grandfather-Father-Son) est une politique de rétention qui permet de conserver des points de restauration à plusieurs points dans le temps.

Son (Fils) : sauvegardes quotidiennes
Father (Père) : sauvegardes hebdomadaires
Grandfather (Grand-père) : sauvegardes mensuelles

Cette approche permet de restaurer rapidement des erreurs récentes, revenir plusieurs semaines en arrière si nécessaire et conserver un historique annuel.

Afin de respecter la règle GFS (Grand-Father, Father, Son), les tâches de sauvegardes sont conservées sur les durées suivantes :

- **Quotidienne** : 7 points de restauration
	- **Localisation** : NAS principal + NAS distant
	- **Rétention** : Conserve les 7 derniers jours
	- **Rotation** : Suppression automatique des backups supérieurs à 7 jours

- **Hebdomadaires** : 4 points de restauration
	- **Localisation** : NAS principal + NAS distant
	- **Rétention** : Conserve un backup par semaine sur une période d’un mois (4 semaines)
	- **Rotation** : Suppression automatique des backups supérieurs à 4 semaines

- **Mensuelles** : 12 points de restauration
	- **Localisation** : NAS distant
	- **Rétention** : Conserve un backup par mois sur une période d’un an (12 mois)
	- **Rotation** : Suppression automatique des backups supérieurs à 12 mois

## 4. **Application de la règle 3-2-1**

**Planification :**

La règle 3-2-1 impose trois copies des données dont deux sur des supports différents, l’un d’eux hors site. Dans cet exemple :

- 3 copies des données :
	- Une version de production
	- Deux copies de sauvegarde sur TrueNAS principal et TrueNAS distant

- 2 types de supports différents :
	- Disques virtuels SCSI (NAS principal)
	- Disques HDD physiques (NAS distant)

- 1 copie hors site :
	- Second serveur TrueNAS distant géographiquement (hors OVH)

**Implémentation :**

- **Copie 1 – Production** :
	- Localisation : Contrôleur de domaine (Proxmox OVH)
	- Adresse : 10.0.0.5
	- Support : Disques virtuels SCSI

- **Copie 2 – Backup primaire (restauration rapide)** :
	- Localisation : TrueNAS (Proxmox OVH)
	- Adresse : 10.0.0.18
	- Support : Pool RAIDZ1, Disques virtuels (3x100Go)

- **Copie 3 – Backup secondaire (Disaster Recovery)** :
	- Localisation : TrueNAS (site distant)
	- Adresse : 192.168.1.250
	- Support : Pool RAIDZ1, HDD (3x600Go)

Le schéma complet de l’infrastructure de sauvegarde ainsi que la mise ne place des tâches de sauvegarde se trouvent en **[Annexe n°12](#Annexe12)** et **[Annexe n°13](#Annexe13)**.

# IV. **Test de restauration**

Un test de restauration a été effectué via Veeam File Level Restore. Un fichier à été supprimé puis restauré avec succès, validant l’intégrité du backup de fichiers.

Ce processus a été documenté en **[Annexe n°14](#Annexe14)**.

# V. **Sécurité des backups**

- Le serveur Veeam n’est volontairement pas joint au domaine PROTO.LAN. Ceci permet de protéger les backups en cas de compromission de l’Active Directory, de garantir l’indépendance de la restauration (via une authentification locale) ainsi que d’appliquer le principe de défense en profondeur (superposition de plusieurs couches de sécurité).

- Afin de renforcer la protection contre les ransomwares, ou la suppression de données accidentelles, des snapshots ZFS quotidiens du répertoire des backup ont été mis en place sur le serveur TrueNAS principal.

	**Configuration des snapshots** :
	- Fréquence : Quotidienne à 03h00
	- Rétention : 14 jours

La mise en place des snapshots est documentée en **[Annexe n°15](#Annexe15)**.

Ces snapshots ZFS créent une copie instantanée **immuable** du dataset de backup. Ceux-ci ne peuvent pas être supprimés pendant la durée de rétention même par un compte avec des privilèges élevés (ex. administrateur root).

- Les accès sont eux aussi contrôlés. En effet, le partage NFS est uniquement accessible depuis 10.0.0.19 (serveur Veeam). L’utilisation du compte de service dédié PROTO\SVC-VEEAM-BU permet de respecter le principe de moindre privilège. De plus, la réplication vers le site distant s’effectue via un tunnel VPN sécurisé WireGuard. Enfin des règles de pare-feu granulaires ont été configurées notamment les port NFS (2049, 111) restreints au réseau local.

# VI. **Limitations et améliorations**

Durant la mise en place de cette solution de sauvegarde, j’ai constaté plusieurs axes d’amélioration ainsi que des problèmes potentiels méritant une attention particulière :

- Le serveur Veeam centralise les connexions au deux NAS, ce qui fait de lui un SPOF (point de défaillance unique). En effet en cas de panne du serveur Veeam les backups quotidiens ainsi que la réplication vers le site distant ne seront plus effectués. Pour remédier à ce problème la tâche de réplication pourrait s’effectuer avec une connexion VPN entre les deux NAS.

- Les deux NAS dépendent de la même solution : TrueNAS. La bonne pratique serait de diversifier les solutions afin d’éviter que des vulnérabilités ou défaillances critiques venant de la solution n’impacte l’intégralité des sauvegardes stockées.

- Une mise à niveau vers une version plus récente de Veeam serait à envisager. En effet les versions plus récentes prennent mieux en charge les restaurations d’objets Active Directory de Windows Server 2025. De plus elles possèdent une prise en charge native de l’hyperviseur Proxmox simplifiant la restauration de machines virtuelles.