# Documentation technique - DaaS Orchestrator

Documentation technique pour développeurs et administrateurs système.

---

## Table des matières

- [Stack technique](#stack-technique)
- [API REST](#api-rest)
- [Base de code](#base-de-code)
- [Terraform](#terraform)
- [Ansible](#ansible)
- [Sécurité](#sécurité)
- [Monitoring et logs](#monitoring-et-logs)
- [Développement](#développement)
- [Tests](#tests)
- [Contribution](#contribution)
- [Roadmap](#roadmap)

---

## Stack technique

### Backend

| Composant | Version | Rôle |
|-----------|---------|------|
| **Python** | 3.10+ | Langage principal |
| **Flask** | 3.1.2 | Framework web API REST |
| **subprocess** | stdlib | Exécution Terraform/Ansible |
| **json** | stdlib | Parsing tfstate et responses |
| **systemd** | — | Service management |

### Infrastructure as Code

| Composant | Version | Rôle |
|-----------|---------|------|
| **Terraform** | 1.0+ | Provisioning VMs Proxmox |
| **Provider Proxmox** | 3.0.2-rc04 | telmate/proxmox |
| **Provider Random** | 3.x | Génération noms VMs |

### Configuration Management

| Composant | Version | Rôle |
|-----------|---------|------|
| **Ansible** | 2.9+ | Configuration des VMs |
| **ansible-vault** | — | Chiffrement secrets |
| **YAML** | — | Format playbooks/vars |

### Virtualization

| Composant | Version | Rôle |
|-----------|---------|------|
| **Proxmox VE** | 8.x | Hyperviseur |
| **QEMU/KVM** | — | Virtualisation |
| **cloud-init** | — | Init VMs |

### OS & Desktop

| Composant | Version | Rôle |
|-----------|---------|------|
| **Ubuntu Server** | 22.04 LTS | OS des VMs |
| **XFCE4** | 4.16+ | Desktop environment |
| **XRDP** | 0.9+ | Serveur RDP |
| **xorgxrdp** | — | Backend graphique RDP |

### Active Directory Integration

| Composant | Version | Rôle |
|-----------|---------|------|
| **SSSD** | — | Auth daemon AD |
| **realmd** | — | Domain join |
| **Kerberos** | — | Auth protocol |
| **Samba client** | — | File sharing |
| **pam_mount** | — | Auto-mount shares |

---

## API REST

### Base URL
```
http://<ip_serveur>:5000
```

### Authentication

**Actuellement** : Aucune (confiance réseau interne)

**Future** : Token JWT ou API Key

---

### Endpoints

#### GET /

Page d'accueil HTML de l'API.

**Response** :
```html
<h1>Orchestrateur DaaS</h1>
...
```

---

#### GET /api/sessions

Liste toutes les sessions actives.

**Request** :
```bash
curl http://<ip_serveur>:5000/api/sessions
```

**Response 200** :
```json
{
  "desktop-abc123": {
    "session_id": "desktop-abc123",
    "vm_name": "desktop-abc123",
    "vm_ip": "<ip_vm>",
    "username": "bob",
    "created_at": "2025-11-21T10:00:00",
    "status": "active"
  }
}
```

---

#### POST /api/session/create

Crée un nouveau desktop éphémère.

**Request** :
```bash
curl -X POST http://<ip_serveur>:5000/api/session/create \
  -H "Content-Type: application/json" \
  -d '{
    "username": "bob",
    "session_user": "optional_local_user",
    "session_password": "optional_password"
  }'
```

**Body parameters** :

| Paramètre | Type | Requis | Description |
|-----------|------|--------|-------------|
| `username` | string | Oui | Username de l'utilisateur AD |
| `session_user` | string | Non | Créer un user local (optionnel) |
| `session_password` | string | Non | Password du user local |

**Response 200** (succès) :
```json
{
  "session_id": "desktop-abc123",
  "vm_name": "desktop-abc123",
  "vm_ip": "<ip_vm>",
  "rdp_port": 3389,
  "username": "bob",
  "session_user": null,
  "status": "ready",
  "message": "Desktop prêt ! Connectez-vous en RDP"
}
```

**Response 500** (erreur) :
```json
{
  "error": "Terraform failed",
  "details": "Error: connection refused..."
}
```

**Durée** : 120-180 secondes (2-3 minutes)

**Process** :
1. Terraform apply (~60s)
2. Wait cloud-init (~30s)
3. Ansible playbook (~90s)
4. Enregistrement session
5. Retour JSON

---

#### POST /api/session/destroy

Détruit un desktop éphémère.

**Request** :
```bash
curl -X POST http://<ip_serveur>:5000/api/session/destroy \
  -H "Content-Type: application/json" \
  -d '{
    "session_id": "desktop-abc123"
  }'
```

**Body parameters** :

| Paramètre | Type | Requis | Description |
|-----------|------|--------|-------------|
| `session_id` | string | Oui | ID de la session (= vm_name) |

**Response 200** (succès) :
```json
{
  "session_id": "desktop-abc123",
  "status": "destroyed"
}
```

**Response 400** (mauvaise requête) :
```json
{
  "error": "session_id required"
}
```

**Response 500** (erreur) :
```json
{
  "error": "Terraform destroy failed",
  "details": "..."
}
```

**Durée** : 20-30 secondes

---

### Codes d'erreur HTTP

| Code | Signification | Exemple |
|------|---------------|---------|
| 200 | Succès | Session créée/détruite |
| 400 | Mauvaise requête | Paramètre manquant |
| 500 | Erreur serveur | Terraform/Ansible failed |

---

## Terraform

### Configuration provider Proxmox
```hcl
provider "proxmox" {
  pm_api_url          = "https://<ip_hôte>:8006/api2/json"
  pm_api_token_id     = var.token_id
  pm_api_token_secret = var.token_secret
  pm_tls_insecure     = true
}
```

### Ressource VM
```hcl
resource "proxmox_vm_qemu" "ephemeral_desktop" {
  name        = local.vm_name
  target_node = "pve"
  clone       = "ubuntu-22.04-template"
  full_clone  = false              # Linked clone (rapide)
  
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
}
```

### State management

**Local backend** (actuel) :
```
terraform.tfstate  # Stocké localement
```

**Future - Remote backend** :
```hcl
terraform {
  backend "s3" {
    bucket = "terraform-state"
    key    = "daas/ephemeral.tfstate"
    region = "eu-west-1"
  }
}
```

### Commandes utiles
```bash
# Init
terraform init

# Format code
terraform fmt

# Valider config
terraform validate

# Voir le plan
terraform plan

# Appliquer
terraform apply -auto-approve

# Outputs
terraform output
terraform output -json

# Voir le state
terraform show

# Détruire
terraform destroy -auto-approve

# Refresh state
terraform refresh
```

---

## Ansible

### Inventaire dynamique

**Script Python** : `inventory/inventory.yaml`
```python
#!/usr/bin/env python3
import json
import sys
import os

TFSTATE_PATHS = [
    "/srv/samba/terraform/environments/production/terraform.tfstate",
    "/srv/samba/terraform/ephemeral/terraform.tfstate"
]

def generate_inventory():
    inventory = {
        "_meta": {"hostvars": {}},
        "domain_vms": {"hosts": [], "vars": {...}},
        "ephemeral_desktop": {"hosts": [], "vars": {...}}
    }
    
    for tfstate_path in TFSTATE_PATHS:
        tfstate = read_tfstate(tfstate_path)
        group = "ephemeral_desktop" if "ephemeral" in tfstate_path else "domain_vms"
        
        for resource in tfstate.get("resources", []):
            if resource.get("type") == "proxmox_vm_qemu":
                # Extraire IP et nom
                inventory[group]["hosts"].append(vm_name)
                inventory["_meta"]["hostvars"][vm_name] = {"ansible_host": vm_ip}
    
    return inventory
```

**Usage** :
```bash
# Lister l'inventaire
./inventory/inventory.yaml --list | jq .

# Avec Ansible
ansible-inventory --list
ansible ephemeral_desktop --list-hosts
```

---

### Playbook deploy-desktop.yml
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
    orchestrator_url: "http://<ip_serveur>:5000"
  
  roles:
    - ad-join
    - desktop-config
```

**Variables injectées** :
- `vm_name` : Nom de la VM (depuis inventaire)
- `orchestrator_url` : URL de l'API pour monitoring
- `ad_join_password` : Depuis vault.yml (chiffré)

---

### Rôle ad-join

**Tâches principales** :
```yaml
# roles/ad-join/tasks/main.yml

- name: Installer packages AD
  apt:
    name:
      - sssd
      - realmd
      - krb5-user
      - adcli
      - samba-common-bin
    state: present

- name: Joindre le domaine AD
  shell: |
    echo "{{ ad_join_password }}" | realm join -U Administrator proto.lan
  args:
    creates: /etc/sssd/sssd.conf

- name: Configurer SSSD
  template:
    src: sssd.conf.j2
    dest: /etc/sssd/sssd.conf
    mode: 0600

- name: Permettre users AD de se connecter
  lineinfile:
    path: /etc/pam.d/common-session
    line: "session required pam_mkhomedir.so skel=/etc/skel/ umask=0077"
```

---

### Rôle desktop-config

**Tâches principales** :
```yaml
# roles/desktop-config/tasks/main.yml

- name: Installer XFCE et XRDP
  apt:
    name:
      - xfce4
      - xfce4-goodies
      - xrdp
      - xorgxrdp
    state: present

- name: Configurer XRDP
  template:
    src: xrdp.ini.j2
    dest: /etc/xrdp/xrdp.ini

- name: Installer pam_mount
  apt:
    name: libpam-mount
    state: present

- name: Configurer pam_mount
  template:
    src: pam_mount.conf.xml.j2
    dest: /etc/security/pam_mount.conf.xml

- name: Créer script monitoring
  template:
    src: inactivity-monitor.sh.j2
    dest: /usr/local/bin/inactivity-monitor.sh
    mode: 0755

- name: Créer service systemd monitoring
  template:
    src: inactivity-monitor.service.j2
    dest: /etc/systemd/system/inactivity-monitor.service

- name: Activer et démarrer monitoring
  systemd:
    name: inactivity-monitor
    enabled: yes
    state: started
```

---

### Ansible Vault

**Chiffrer un fichier** :
```bash
ansible-vault create group_vars/all/vault.yml
ansible-vault edit group_vars/all/vault.yml
```

**Changer le password** :
```bash
ansible-vault rekey group_vars/all/vault.yml
```

**Voir le contenu** :
```bash
ansible-vault view group_vars/all/vault.yml
```

**Utiliser avec playbook** :
```bash
# Avec prompt
ansible-playbook playbooks/deploy-desktop.yml --ask-vault-pass

# Avec fichier password
ansible-playbook playbooks/deploy-desktop.yml --vault-password-file .vault_pass
```

---

### Tags Ansible (future feature)
```yaml
roles:
  - { role: ad-join, tags: ['ad'] }
  - { role: desktop-config, tags: ['desktop'] }
```
```bash
# Exécuter seulement certains tags
ansible-playbook deploy-desktop.yml --tags "desktop"

# Skip certains tags
ansible-playbook deploy-desktop.yml --skip-tags "ad"
```

---

## Sécurité

### Secrets management

| Secret | Fichier | Protection |
|--------|---------|------------|
| **Proxmox token** | `terraform.tfvars` | File perms 600, .gitignore |
| **AD password** | `ansible/vault.yml` | Ansible Vault AES256 |
| **Vault password** | `.vault_pass` | File perms 600, .gitignore |

### Network security

**Flux autorisés** :
```
Client → Orchestrateur:5000 (HTTP)
Orchestrateur → Proxmox:8006 (HTTPS)
Orchestrateur → Desktop:22 (SSH - Ansible)
Client → Desktop:3389 (RDP)
Desktop → AD:389,636,88 (LDAP, Kerberos)
Desktop → Samba:445 (SMB)
```

**Recommandations** :
- ✅ Utiliser un firewall sur l'orchestrateur (ufw)
- ✅ Restreindre l'accès API à certaines IPs
- ✅ Utiliser HTTPS pour l'API (avec certificat)
- ✅ Implémenter authentication API (JWT tokens)

---

### Authentication future

**Option 1: API Key** :
```python
@app.before_request
def check_api_key():
    api_key = request.headers.get('X-API-Key')
    if api_key != VALID_API_KEY:
        return jsonify({"error": "Unauthorized"}), 401
```

**Option 2: JWT Token** :
```python
from flask_jwt_extended import JWTManager, jwt_required

app.config['JWT_SECRET_KEY'] = 'super-secret'
jwt = JWTManager(app)

@app.route('/api/session/create', methods=['POST'])
@jwt_required()
def create_session():
    ...
```

---

## Monitoring et logs

### Logs systemd

**Voir les logs orchestrateur** :
```bash
# Logs complets
sudo journalctl -u orchestrator-daas

# Dernières 100 lignes
sudo journalctl -u orchestrator-daas -n 100

# Logs en temps réel
sudo journalctl -u orchestrator-daas -f

# Filtrer par date
sudo journalctl -u orchestrator-daas --since "2025-11-21 10:00"

# Filtrer par niveau (err, warning, info)
sudo journalctl -u orchestrator-daas -p err
```

**Logs des VMs** :
```bash
# SSH sur la VM
ssh ubuntu@<VM_IP>

# Monitoring
sudo journalctl -u inactivity-monitor -f

# XRDP
sudo journalctl -u xrdp -f

# SSSD (auth AD)
sudo journalctl -u sssd -f

# Tous les logs système
sudo journalctl -f
```

---

### Métriques

**Actuellement** : Logs textuels uniquement

**Future - Prometheus metrics** :
```python
from prometheus_flask_exporter import PrometheusMetrics

metrics = PrometheusMetrics(app)

# Métriques automatiques
metrics.info('app_info', 'Application info', version='1.0.0')

# Métriques custom
session_counter = Counter('daas_sessions_total', 'Total sessions créées')
session_duration = Histogram('daas_session_duration_seconds', 'Durée des sessions')

@app.route('/api/session/create', methods=['POST'])
def create_session():
    session_counter.inc()
    start = time.time()
    # ... création session
    session_duration.observe(time.time() - start)
```

**Endpoint metrics** :
```
GET /metrics
```

---

### Grafana dashboard

**Future** : Dashboard Grafana avec :
- Nombre de sessions actives
- Taux de création/destruction
- Durée moyenne des sessions
- Erreurs Terraform/Ansible
- Utilisation CPU/RAM Proxmox

---

## Développement

### Setup environnement dev
```bash
# Cloner le repo
git clone https://github.com/TomGn1/daas-project.git
cd daas-project

# Créer venv Python
cd orchestrator
python3 -m venv venv
source venv/bin/activate
pip install flask

# Installer pre-commit hooks (optionnel)
pip install pre-commit
pre-commit install
```

---

### Lancer en mode dev
```bash
# Mode debug Flask (auto-reload)
cd /srv/samba/orchestrator
source venv/bin/activate

# Avec debug activé
export FLASK_ENV=development
python app.py

# OU
flask run --debug
```


---

### Variables d'environnement

**Futures variables** :
```bash
# .env file
FLASK_ENV=development
ORCHESTRATOR_PORT=5000
TERRAFORM_DIR=/srv/samba/terraform/ephemeral
ANSIBLE_DIR=/srv/samba/ansible
PROXMOX_URL=https://<ip_hôte>:8006
MAX_CONCURRENT_SESSIONS=10
SESSION_TIMEOUT=1800  # 30 minutes
```

**Usage** :
```python
from dotenv import load_dotenv
import os

load_dotenv()

TERRAFORM_DIR = os.getenv('TERRAFORM_DIR', '/srv/samba/terraform/ephemeral')
```

---

## Tests

### Tests manuels actuels
```bash
# Test création session
curl -X POST http://<ip_serveur>:5000/api/session/create \
  -H "Content-Type: application/json" \
  -d '{"username": "testuser"}'

# Test liste sessions
curl http://<ip_serveur>:5000/api/sessions

# Test destruction
curl -X POST http://<ip_serveur>:5000/api/session/destroy \
  -H "Content-Type: application/json" \
  -d '{"session_id": "desktop-abc123"}'
```

---

### Tests unitaires (à implémenter)

**pytest** :
```python
# tests/test_api.py
import pytest
from app import app

@pytest.fixture
def client():
    app.config['TESTING'] = True
    with app.test_client() as client:
        yield client

def test_home(client):
    rv = client.get('/')
    assert rv.status_code == 200
    assert b'Orchestrateur DaaS' in rv.data

def test_list_sessions(client):
    rv = client.get('/api/sessions')
    assert rv.status_code == 200
    data = rv.get_json()
    assert isinstance(data, dict)

def test_create_session_missing_username(client):
    rv = client.post('/api/session/create',
                     json={})
    assert rv.status_code == 400
```

**Lancer les tests** :
```bash
pip install pytest
pytest tests/
```

---

### Tests d'intégration (à implémenter)
```bash
# Tester le workflow complet
# 1. Créer une session
# 2. Vérifier que la VM existe sur Proxmox
# 3. Vérifier que la VM est accessible en SSH
# 4. Détruire la session
# 5. Vérifier que la VM est supprimée
```

---

## Contribution

### Workflow Git
```bash
# Créer une branche feature
git checkout -b feature/ma-fonctionnalite

# Faire des commits
git add .
git commit -m "feat: ajout fonctionnalité X"

# Push et créer PR
git push origin feature/ma-fonctionnalite
```

### Commit message convention
```
feat: Nouvelle fonctionnalité
fix: Correction de bug
docs: Documentation
refactor: Refactoring code
test: Ajout de tests
chore: Tâches diverses (deps, config)
```

**Exemples** :
```
feat: ajout endpoint /api/sessions/:id
fix: correction timeout Terraform
docs: mise à jour README
refactor: extraction service Terraform
```

---

### Code style

**Python (PEP 8)** :
```bash
# Installer black (formatter)
pip install black

# Formatter le code
black app.py

# Vérifier avec flake8
pip install flake8
flake8 app.py
```

**Ansible (YAML lint)** :
```bash
# Installer ansible-lint
pip install ansible-lint

# Vérifier les playbooks
ansible-lint playbooks/deploy-desktop.yml
```

---

## Roadmap

### Version 1.0 (Actuel) ✅

- [x] Création automatique de desktops
- [x] Destruction automatique
- [x] Intégration AD
- [x] Montage Samba automatique
- [x] Scripts clients (Windows, Linux)
- [x] Service systemd orchestrateur

---

### Version 1.1 (Court terme)

- [ ] **Authentication API** (JWT tokens)
- [ ] **HTTPS pour l'API** (certificat Let's Encrypt)
- [ ] **Base de données** (SQLite) pour persistence
- [ ] **Logs structurés** (JSON format)
- [ ] **Health check endpoint** (`/health`)

---

### Version 1.2 (Moyen terme)

- [ ] **Queue système** (Redis) pour multi-threading
- [ ] **Rate limiting** (limite de requêtes par IP)
- [ ] **Webhooks** (notifications Slack/Discord)
- [ ] **Métriques Prometheus**
- [ ] **Dashboard Grafana**
- [ ] **Tests automatisés** (CI/CD)

---

### Version 2.0 (Long terme)

- [ ] **Interface web** (React frontend)
- [ ] **Multi-tenancy** (organisations/projets)
- [ ] **Templates customisables** (différents OS/configs)
- [ ] **Snapshot/restore** de sessions
- [ ] **Scheduling** (créer desktop à heure fixe)
- [ ] **Quotas** (limite par user/org)
- [ ] **Audit logs** complets
- [ ] **Cluster Proxmox** (HA, load balancing)

---

## Performance

### Optimisations actuelles

| Optimisation | Impact |
|--------------|--------|
| **Linked clones** | Création VM en 30s au lieu de 5 min |
| **cloud-init** | Init VM en 30s au lieu de 2 min |
| **Thin provisioning** | Économie de stockage (~80%) |
| **DHCP** | Pas de gestion IP statique |

---

### Bottlenecks identifiés

1. **Séquentiel** : Une seule demande traitée à la fois
   - Solution : Thread pool ou queue Redis
   
2. **In-memory sessions** : Perte d'état au restart
   - Solution : Base de données

3. **Pas de cache** : Chaque demande relit tfstate
   - Solution : Cache Redis

4. **Single node Proxmox** : Limite de capacité
   - Solution : Cluster Proxmox

---

### Benchmarks

**Création de session** :

| Étape | Temps | % Total |
|-------|-------|---------|
| Terraform apply | 60s | 40% |
| Wait cloud-init | 30s | 20% |
| Ansible config | 60s | 40% |
| **Total** | **150s** | **100%** |

**Destruction de session** :

| Étape | Temps |
|-------|-------|
| Terraform destroy | 25s |
| **Total** | **25s** |

---

## Troubleshooting

### Erreurs courantes

#### `FileNotFoundError: 'terraform'`

**Cause** : PATH incorrect dans service systemd

**Solution** :
```bash
sudo nano /etc/systemd/system/orchestrator-daas.service
# Ajouter /usr/bin dans Environment="PATH=..."
sudo systemctl daemon-reload
sudo systemctl restart orchestrator-daas
```

---

#### `ansible_host not defined`

**Cause** : VM pas encore dans inventaire dynamique

**Solution** : Attendre 30s que cloud-init termine et que l'IP soit assignée

---

#### `realm join failed`

**Cause** : DNS ne résout pas proto.lan

**Solution** :
```bash
# Sur la VM
sudo nano /etc/systemd/resolved.conf
# DNS=<ip_dns>
sudo systemctl restart systemd-resolved
```

---

#### `pam_mount: mount failed`

**Cause** : Credentials AD incorrects ou partage inaccessible

**Solution** :
```bash
# Test manuel
sudo mount -t cifs //<ip_samba>/Partage /mnt/test \
  -o username=testuser,domain=PROTO
```

---

## Références

### Documentation officielle

- **Flask** : https://flask.palletsprojects.com/
- **Terraform** : https://www.terraform.io/docs
- **Proxmox Provider** : https://registry.terraform.io/providers/Telmate/proxmox
- **Ansible** : https://docs.ansible.com/
- **Proxmox VE** : https://pve.proxmox.com/wiki/

### Ressources utiles

- **XRDP** : https://github.com/neutrinolabs/xrdp
- **SSSD** : https://sssd.io/
- **pam_mount** : https://pam-mount.sourceforge.net/

---

## Changelog technique

### 2025-11-21 - v1.0.0

**Added** :
- Orchestrateur Flask avec API REST
- Terraform automation (Proxmox)
- Ansible automation (configuration VMs)
- Inventaire dynamique multi-tfstate
- Service systemd orchestrator
- Scripts clients Windows/Linux
- Monitoring d'inactivité dans VMs
- Documentation complète

**Technical details** :
- Python 3.10, Flask 3.1.2
- Terraform 1.x, provider Proxmox 3.0.2-rc04
- Ansible 2.9+
- Ubuntu 22.04 LTS, XFCE 4.16, XRDP 0.9

---
