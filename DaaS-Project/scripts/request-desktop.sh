#!/bin/bash
# ========================================
# request-desktop.sh
# Script client pour demander un desktop éphémère via l'orchestrateur DaaS
# ========================================

set -euo pipefail  # Arrêter si une commande échoue

# ========================================
# Configuration
# ========================================

ORCHESTRATOR_URL="${ORCHESTRATOR_URL:-http://<ip_serveur>:5000}"
USERNAME="${USER}"
DOMAIN="PROTO"

# Couleurs pour les messages
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Fonctions d'affichage
log_success() { echo -e "${GREEN}✅ $1${NC}"; }
log_info() { echo -e "${CYAN}ℹ️  $1${NC}"; }
log_warning() { echo -e "${YELLOW}⚠️  $1${NC}"; }
log_error() { echo -e "${RED}❌ $1${NC}"; }

# ========================================
# Vérifications préalables
# ========================================

# Vérifier que curl est installé
if ! command -v curl &> /dev/null; then
    log_error "curl n'est pas installé. Installez-le avec: sudo apt install curl"
    exit 1
fi

# Vérifier que xfreerdp est installé
if ! command -v xfreerdp &> /dev/null; then
    log_error "xfreerdp n'est pas installé. Installez-le avec: sudo apt install freerdp2-x11"
    exit 1
fi

# Vérifier que jq est installé (pour parser JSON)
if ! command -v jq &> /dev/null; then
    log_warning "jq n'est pas installé. Installation recommandée: sudo apt install jq"
    USE_JQ=false
else
    USE_JQ=true
fi

# ========================================
# Bannière
# ========================================

clear
echo -e "${CYAN}"
cat << "EOF"
╔══════════════════════════════════════════╗
║     Desktop as a Service (DaaS)          ║
║     Orchestrateur Desktop Éphémère       ║
╚══════════════════════════════════════════╝
EOF
echo -e "${NC}"

log_info "Demande de desktop en cours pour: $USERNAME"
log_info "Orchestrateur: $ORCHESTRATOR_URL"
echo ""

# ========================================
# Étape 1 : Créer la session
# ========================================

log_info "Étape 1/3 : Création du desktop..."
echo ""

# Créer le body JSON
JSON_BODY=$(cat <<EOF
{
    "username": "$USERNAME"
}
EOF
)

# Appeler l'API
RESPONSE=$(curl -s -X POST \
    -H "Content-Type: application/json" \
    -d "$JSON_BODY" \
    "$ORCHESTRATOR_URL/api/session/create" \
    --max-time 600 \
    -w "\nHTTP_CODE:%{http_code}")

# Extraire le code HTTP
HTTP_CODE=$(echo "$RESPONSE" | grep "HTTP_CODE:" | cut -d: -f2)
RESPONSE_BODY=$(echo "$RESPONSE" | sed '/HTTP_CODE:/d')

# Vérifier le succès
if [ "$HTTP_CODE" != "200" ]; then
    log_error "Échec de la création du desktop"
    log_error "Code HTTP: $HTTP_CODE"
    echo "$RESPONSE_BODY"
    exit 1
fi

log_success "Desktop créé avec succès"
echo ""

# ========================================
# Étape 2 : Extraire les informations
# ========================================

log_info "Extraction des informations..."

if [ "$USE_JQ" = true ]; then
    # Parser avec jq
    SESSION_ID=$(echo "$RESPONSE_BODY" | jq -r '.session_id')
    VM_IP=$(echo "$RESPONSE_BODY" | jq -r '.vm_ip')
    RDP_PORT=$(echo "$RESPONSE_BODY" | jq -r '.rdp_port // 3389')
else
    # Parser manuellement (fallback)
    SESSION_ID=$(echo "$RESPONSE_BODY" | grep -o '"session_id":"[^"]*"' | cut -d'"' -f4)
    VM_IP=$(echo "$RESPONSE_BODY" | grep -o '"vm_ip":"[^"]*"' | cut -d'"' -f4)
    RDP_PORT=3389
fi

# Vérifier que les infos sont bien récupérées
if [ -z "$SESSION_ID" ] || [ -z "$VM_IP" ]; then
    log_error "Impossible d'extraire les informations de la réponse"
    echo "$RESPONSE_BODY"
    exit 1
fi

echo ""
log_info "Informations de connexion:"
echo "   Session ID  : $SESSION_ID"
echo "   Adresse IP  : $VM_IP"
echo "   Port RDP    : $RDP_PORT"
echo "   Utilisateur : $USERNAME@$DOMAIN"
echo ""

# ========================================
# Étape 3 : Connexion RDP
# ========================================

log_info "Étape 2/3 : Lancement de la connexion RDP..."
log_warning "Patientez pendant le chargement du bureau distant..."
echo ""

sleep 2

# Options xfreerdp
# /v: = adresse
# /u: = username
# /d: = domain
# /cert:ignore = ignorer les certificats
# /f = fullscreen
# +clipboard = activer le presse-papier
# /dynamic-resolution = résolution dynamique
# /sound:sys:pulse = son via PulseAudio

log_info "Utilisez ces credentials pour vous connecter :"
echo -e "   ${YELLOW}Domaine     : $DOMAIN${NC}"
echo -e "   ${YELLOW}Utilisateur : $USERNAME${NC}"
echo -e "   ${YELLOW}Mot de passe: [Votre mot de passe AD]${NC}"
echo ""

# Lancer xfreerdp en arrière-plan et capturer son PID
xfreerdp /v:$VM_IP:$RDP_PORT \
    /u:$USERNAME \
    /d:$DOMAIN \
    /cert:ignore \
    /dynamic-resolution \
    +clipboard \
    /sound:sys:pulse \
    /f \
    > /dev/null 2>&1 &

XFREERDP_PID=$!

log_success "Connexion RDP lancée (PID: $XFREERDP_PID)"
echo ""

# ========================================
# Étape 4 : Surveiller la session
# ========================================

log_info "   Surveillance de la session en cours..."
log_info "   (Le script attendra la fin de votre session)"
echo ""

# Attendre que xfreerdp se termine
wait $XFREERDP_PID

log_success "Session RDP terminée !"
echo ""

# ========================================
# Étape 5 : Destruction automatique
# ========================================

log_info "Destruction automatique du desktop..."
log_warning "La VM sera détruite dans 10 secondes (Ctrl+C pour annuler)"
echo ""

# Countdown
for i in {10..1}; do
    echo -ne "      $i secondes...\r"
    sleep 1
done
echo ""

# Appeler l'API de destruction
DESTROY_JSON=$(cat <<EOF
{
    "session_id": "$SESSION_ID"
}
EOF
)

DESTROY_RESPONSE=$(curl -s -X POST \
    -H "Content-Type: application/json" \
    -d "$DESTROY_JSON" \
    "$ORCHESTRATOR_URL/api/session/destroy" \
    --max-time 300 \
    -w "\nHTTP_CODE:%{http_code}")

DESTROY_HTTP_CODE=$(echo "$DESTROY_RESPONSE" | grep "HTTP_CODE:" | cut -d: -f2)

if [ "$DESTROY_HTTP_CODE" = "200" ]; then
    log_success "Desktop détruit avec succès"
else
    log_error "Erreur lors de la destruction (Code: $DESTROY_HTTP_CODE)"
    echo "$DESTROY_RESPONSE"
fi

echo ""
log_success "Terminé"
echo ""