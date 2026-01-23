#!/usr/bin/env python3
"""
Test Flask ultra-simple pour comprendre
"""
from flask import Flask, jsonify, request

# Créer l'application Flask
# __name__ = nom du module Python actuel
app = Flask(__name__)

# ========================================
# ROUTES (les "URLs" de ton API)
# ========================================

# Route 1 : Page d'accueil
@app.route('/')
def home():
    """
    Quand quelqu'un va sur http://10.0.0.7:5000/
    Cette fonction s'exécute
    """
    return "Orchestrateur DaaS - API en ligne !"

# Route 2 : Info sur l'API (GET)
@app.route('/api/info')
def info():
    """
    GET http://10.0.0.7:5000/api/info
    Retourne du JSON
    """
    data = {
        "nom": "Orchestrateur Desktop Ephemeral",
        "version": "1.0",
        "status": "running"
    }
    # jsonify() convertit un dict Python en JSON
    return jsonify(data)

# Route 3 : Créer une session (POST)
@app.route('/api/session/create', methods=['POST'])
def create_session():
    """
    POST http://10.0.0.7:5000/api/session/create
    
    Le client envoie du JSON, on le récupère avec request.json
    """
    # Récupérer les données envoyées par le client
    data = request.json  # ← Dict Python depuis le JSON reçu
    
    username = data.get('username', 'anonymous')
    
    # Pour l'instant, juste un mock (simulation)
    response = {
        "session_id": "test-123",
        "vm_name": "desktop-mock",
        "ip": "10.0.0.999",
        "username": username,
        "status": "created (MOCK)"
    }
    
    return jsonify(response)

# ========================================
# LANCEMENT DU SERVEUR
# ========================================

if __name__ == '__main__':
    # Lancer le serveur Flask
    # host='0.0.0.0' = écoute sur toutes les interfaces réseau
    # port=5000 = port d'écoute
    # debug=True = mode debug avec auto-reload
    app.run(host='0.0.0.0', port=5000, debug=True)
