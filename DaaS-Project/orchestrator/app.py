#!/usr/bin/env python3
"""
Orchestrateur DaaS - Desktop as a Service
Gère la création et destruction de desktops éphémères
"""
from flask import Flask, request, jsonify
import subprocess
import json
import os
import time
from datetime import datetime

app = Flask(__name__)

# ========================================
# CONFIGURATION
# ========================================

TERRAFORM_DIR = "/srv/samba/terraform/ephemeral"
ANSIBLE_DIR = "/srv/samba/ansible"
SESSIONS = {}  # Dict pour tracker les sessions actives

# ========================================
# FONCTIONS UTILITAIRES
# ========================================


def run_command(cmd, cwd=None, timeout=300):
    """
    Exécute une commande shell avec logs en TEMPS RÉEL
    """
    try:
        print(f"Commande: {' '.join(cmd)}")
        print(f"Dossier: {cwd}")
        print("Exécution en cours...\n")

        # Créer le process
        process = subprocess.Popen(
            cmd,
            cwd=cwd,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,  # Combiner stdout et stderr
            text=True,
            bufsize=1,  # Line buffered
            universal_newlines=True
        )

        stdout_lines = []

        # Lire ligne par ligne en temps réel
        for line in process.stdout:
            print(line.rstrip())  # Afficher immédiatement
            stdout_lines.append(line)

        # Attendre la fin
        process.wait(timeout=timeout)

        stdout = ''.join(stdout_lines)
        success = process.returncode == 0

        print(f"\n{'✅' if success else '❌'} Returncode: {process.returncode}\n")

        return success, stdout, ""

    except subprocess.TimeoutExpired:
        process.kill()
        return False, "", f"Command timed out after {timeout}s"
    except Exception as e:
        print(f"Exception: {e}")
        import traceback
        traceback.print_exc()
        return False, "", str(e)


def get_vm_info_from_tfstate():
    """
    Lit le tfstate Terraform et extrait l'IP et le nom de la VM

    Returns:
        dict: {"vm_name": "desktop-XXX", "vm_ip": "10.0.0.X"}
    """
    tfstate_path = os.path.join(TERRAFORM_DIR, "terraform.tfstate")

    try:
        with open(tfstate_path, 'r') as f:
            tfstate = json.load(f)

        # Parcourir les ressources Terraform
        for resource in tfstate.get("resources", []):
            if resource.get("type") == "proxmox_vm_qemu":
                for instance in resource.get("instances", []):
                    attrs = instance.get("attributes", {})

                    vm_name = attrs.get("name")
                    vm_ip = attrs.get("default_ipv4_address")

                    if vm_name and vm_ip:
                        return {"vm_name": vm_name, "vm_ip": vm_ip}

        return None

    except Exception as e:
        print(f"Erreur lecture tfstate: {e}")
        return None

# ========================================
# ROUTES API
# ========================================


@app.route('/')
def home():
    """Page d'accueil"""
    return """
    <h1>Orchestrateur DaaS</h1>
    <p>API REST pour gérer des desktops éphémères</p>
    <ul>
        <li>POST /api/session/create - Créer un desktop</li>
        <li>POST /api/session/destroy - Détruire un desktop</li>
        <li>GET /api/sessions - Lister les sessions actives</li>
    </ul>
    """


@app.route('/api/sessions', methods=['GET'])
def list_sessions():
    """Liste toutes les sessions actives"""
    return jsonify(SESSIONS)


@app.route('/api/session/create', methods=['POST'])
def create_session():
    """
    Crée un nouveau desktop éphémère

    Body JSON attendu:
    {
        "username": "bob",
        "session_user": "optionnel",  // Pour créer un user local
        "session_password": "optionnel"
    }
    """
    data = request.json
    username = data.get('username', 'anonymous')
    session_user = data.get('session_user')
    session_password = data.get('session_password')

    print(f"\nCréation de session pour {username}")
    print(f"Heure: {datetime.now()}")

    # ========================================
    # ÉTAPE 1 : Terraform Apply
    # ========================================

    print("Étape 1/3 : Terraform apply...")

    success, stdout, stderr = run_command(
        ['terraform', 'apply', '-auto-approve'],
        cwd=TERRAFORM_DIR,
        timeout=300  # 5 minutes max
    )

    if not success:
        print(f"Terraform failed: {stderr}")
        return jsonify({
            "error": "Terraform failed",
            "details": stderr
        }), 500

    print("Terraform completed")

    # ========================================
    # ÉTAPE 2 : Récupérer infos VM
    # ========================================

    print("Étape 2/3 : Récupération des infos VM...")

    # Attendre un peu que cloud-init finisse
    time.sleep(30)

    vm_info = get_vm_info_from_tfstate()

    if not vm_info:
        return jsonify({
            "error": "Could not get VM info from tfstate"
        }), 500

    vm_name = vm_info['vm_name']
    vm_ip = vm_info['vm_ip']

    print(f"VM créée: {vm_name} @ {vm_ip}")

    # ========================================
    # ÉTAPE 3 : Ansible Configuration
    # ========================================

    print("Étape 3/3 : Configuration Ansible...")

    # Construire la commande Ansible
    ansible_cmd = [
        'ansible-playbook',
        'playbooks/deploy-desktop.yml'
    ]

    # Ajouter les extra-vars si un user local est demandé
    if session_user and session_password:
        ansible_cmd.extend([
            '-e', f'session_user={session_user}',
            '-e', f'session_password={session_password}'
        ])

    success, stdout, stderr = run_command(
        ansible_cmd,
        cwd=ANSIBLE_DIR,
        timeout=600  # 10 minutes max
    )

    if not success:
        print(f"Ansible failed (VM created but not configured): {stderr}")
        # VM existe quand même, on retourne les infos
    else:
        print("Ansible completed")

    # ========================================
    # ENREGISTRER LA SESSION
    # ========================================

    session_id = vm_name  # Utiliser le nom de VM comme session_id

    SESSIONS[session_id] = {
        "session_id": session_id,
        "vm_name": vm_name,
        "vm_ip": vm_ip,
        "username": username,
        "session_user": session_user,
        "created_at": datetime.now().isoformat(),
        "status": "active"
    }

    # ========================================
    # RÉPONSE AU CLIENT
    # ========================================

    print(f"Session {session_id} prête !\n")

    return jsonify({
        "session_id": session_id,
        "vm_name": vm_name,
        "vm_ip": vm_ip,
        "rdp_port": 3389,
        "username": username,
        "session_user": session_user,
        "status": "ready",
        "message": "Desktop prêt ! Connectez-vous en RDP"
    })


@app.route('/api/session/destroy', methods=['POST'])
def destroy_session():
    """
    Détruit un desktop éphémère

    Body JSON:
    {
        "session_id": "desktop-XXX"
    }
    """
    data = request.json
    session_id = data.get('session_id')

    if not session_id:
        return jsonify({"error": "session_id required"}), 400

    print(f"\nDestruction de session: {session_id}")

    # ========================================
    # Terraform Destroy
    # ========================================

    success, stdout, stderr = run_command(
        ['terraform', 'destroy', '-auto-approve'],
        cwd=TERRAFORM_DIR,
        timeout=300
    )

    if not success:
        print(f"Terraform destroy failed: {stderr}")
        return jsonify({
            "error": "Terraform destroy failed",
            "details": stderr
        }), 500

    # Marquer la session comme détruite
    if session_id in SESSIONS:
        SESSIONS[session_id]['status'] = 'destroyed'
        SESSIONS[session_id]['destroyed_at'] = datetime.now().isoformat()

    print(f"Session {session_id} détruite\n")

    return jsonify({
        "session_id": session_id,
        "status": "destroyed"
    })

# ========================================
# LANCEMENT DU SERVEUR
# ========================================


if __name__ == '__main__':
    print("=" * 50)
    print("Démarrage Orchestrateur DaaS")
    print("=" * 50)
    print(f"Terraform dir: {TERRAFORM_DIR}")
    print(f"Ansible dir: {ANSIBLE_DIR}")
    print(f"API: http://0.0.0.0:5000")
    print("=" * 50)

    app.run(host='0.0.0.0', port=5000, debug=True)
