#!/usr/bin/env bash
# ═════════════════════════════════════════════════════════════════════════════
# TuringOne Community — Installation en un clic (Linux / macOS / Git Bash)
#
#   ./install.sh            installation complète (génère .env + démarre la stack)
#   ./install.sh --env-only génère uniquement le .env (pour inspection avant démarrage)
#
# Moteurs supportés : Docker (recommandé) ou Podman (voir notes dans README.md).
# Sous Windows, préférez PowerShell :  .\install.ps1
#
# Idempotent : un .env existant n'est JAMAIS écrasé (les secrets générés — dont
# la master key de chiffrement — doivent survivre aux réinstallations).
# ═════════════════════════════════════════════════════════════════════════════
set -euo pipefail

cd "$(dirname "$0")"

BLUE='\033[0;34m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; NC='\033[0m'
info()  { echo -e "${BLUE}ℹ️  $*${NC}"; }
ok()    { echo -e "${GREEN}✅ $*${NC}"; }
warn()  { echo -e "${YELLOW}⚠️  $*${NC}"; }
fail()  { echo -e "${RED}❌ $*${NC}"; exit 1; }

# ── Plateforme ───────────────────────────────────────────────────────────────
if [[ -n "${SUDO_USER:-}" ]]; then
    warn "Lancé via sudo : ce n'est normalement PAS nécessaire (Docker Desktop, ou"
    warn "utilisateur membre du groupe 'docker'). Les fichiers générés sont rendus à"
    warn "${SUDO_USER}, mais lancez plutôt ./install.sh sans sudo."
fi

case "$(uname -s)" in
    MINGW*|MSYS*|CYGWIN*)
        warn "Windows détecté (Git Bash). Ce script peut fonctionner, mais la sortie"
        warn "de Docker s'affiche mal dans certains terminaux (MinTTY)."
        warn "👉 Recommandé sous Windows :  PowerShell →  .\\install.ps1"
        ;;
esac

# ── Moteur de conteneurs : Docker ou Podman ──────────────────────────────────
# ENGINE  : binaire pour inspect/info (docker | podman)
# COMPOSE : commande compose ("docker compose" | "podman compose")
ENGINE=""; COMPOSE=""
if command -v docker >/dev/null 2>&1 && docker compose version >/dev/null 2>&1; then
    ENGINE="docker"; COMPOSE="docker compose"
    docker info >/dev/null 2>&1 || fail "Le démon Docker ne répond pas — démarrez Docker (Desktop)"
elif command -v podman >/dev/null 2>&1; then
    podman info >/dev/null 2>&1 || fail "Podman ne répond pas (machine podman démarrée ?)"
    if podman compose version >/dev/null 2>&1; then
        ENGINE="podman"; COMPOSE="podman compose"
        warn "Podman détecté. Fonctionne avec le provider 'docker-compose' (recommandé)."
        warn "Le provider python 'podman-compose' gère mal 'depends_on: service_completed_successfully' :"
        warn "si le backend démarre avant la fin du bootstrap, relancez :  podman compose up -d"
    else
        fail "Podman trouvé mais 'podman compose' indisponible — installez docker-compose ou podman-compose"
    fi
else
    fail "Ni Docker ni Podman trouvés : https://docs.docker.com/get-docker/"
fi
info "Moteur : ${ENGINE} (${COMPOSE})"

# ── Bits d'exécution des scripts montés ──────────────────────────────────────
# postgres/init/*.sh est monté dans /docker-entrypoint-initdb.d : l'image
# officielle PostgreSQL EXÉCUTE ces fichiers (elle ne les "source" pas toujours).
# Sans bit +x → exec échoue (code 126), l'init est abandonnée, le cluster reste
# vide et Keycloak boucle sur « role "keycloak" does not exist ».
# Les archives ZIP/tar perdent les permissions : on les rétablit à chaque run.
chmod +x postgres/init/*.sh 2>/dev/null || true

# ── Génération de secrets ────────────────────────────────────────────────────
gen_secret()   { openssl rand -hex 24; }                                    # 48 hex chars
gen_keyid()    { echo "turingone$(openssl rand -hex 8)"; }                  # access key id
gen_masterkey(){ openssl rand -base64 32 | tr '+/' '-_' | tr -d '\n'; }     # b64 url-safe 32o

set_var() {  # set_var NOM VALEUR — remplace la ligne NOM=... dans .env
    local name="$1" value="$2"
    # sed -i portable macOS/Linux
    sed -i.bak "s|^${name}=.*|${name}=${value}|" .env && rm -f .env.bak
}

if [[ -f .env ]]; then
    warn ".env existant conservé (secrets préservés). Supprimez-le pour repartir de zéro."
else
    info "Génération du fichier .env avec des secrets aléatoires…"
    cp .env.example .env

    DB_PASSWORD="$(gen_secret)"
    set_var POSTGRES_SUPERUSER_PASSWORD  "$(gen_secret)"
    set_var DATABASE_PASSWORD            "$DB_PASSWORD"
    set_var BILLING_DATABASE_PASSWORD    "$DB_PASSWORD"
    set_var KC_DB_PASSWORD               "$(gen_secret)"
    set_var KEYCLOAK_PASSWORD_ADMIN      "$(gen_secret)"
    set_var TURINGONE_ADMIN_PASSWORD     "$(gen_secret)"
    set_var RABBITMQ_PASSWORD            "$(gen_secret)"
    set_var S3_ACCESS_KEY                "$(gen_keyid)"
    set_var S3_SECRET_KEY                "$(gen_secret)"
    set_var TURINGONE_MASTER_KEY         "$(gen_masterkey)"

    chmod 600 .env
    # Sous sudo, .env appartiendrait à root en 600 → illisible pour l'utilisateur,
    # et tout 'docker compose' ultérieur échouerait sur « permission denied ».
    if [[ -n "${SUDO_USER:-}" ]]; then
        chown "$SUDO_USER" .env 2>/dev/null || true
    fi
    ok ".env généré (permissions 600)"
    warn "SAUVEGARDEZ ce fichier : TURINGONE_MASTER_KEY est indispensable pour déchiffrer vos données."
fi

if grep -q "CHANGE-ME" .env; then
    warn "Pensez à renseigner VLLM_API_KEY dans .env (clé OpenAI ou serveur LLM local) —"
    warn "sans elle, les fonctionnalités IA ne répondront pas."
fi

[[ "${1:-}" == "--env-only" ]] && { ok "Fichier .env prêt. Lancez : ${COMPOSE} up -d"; exit 0; }

# ── Étape 1/3 : telechargement des images (la partie LONGUE) ─────────────────────────
info "Étape 1/3 — Téléchargement des images…"
info "  ⏳ Le PREMIER téléchargement représente environ 2 Go :"
info "     comptez 5 à 15 min selon la connexion. La progression s'affiche ci-dessous."
$COMPOSE pull || fail "Le téléchargement des images a échoué (voir la sortie ci-dessus)"
ok "Images téléchargées"

# ── Étape 2/3 : démarrage de la stack ────────────────────────────────────────
info "Étape 2/3 — Démarrage des services…"
# Ne pas mourir ici (set -e) : backend dépend du bootstrap, donc un échec de
# provisioning fait échouer 'up' — on veut alors afficher les logs bootstrap.
COMPOSE_RC=0
$COMPOSE up -d || COMPOSE_RC=$?

# ── Diagnostic : cluster PostgreSQL présent mais non initialisé ──────────────
# L'image PostgreSQL ne rejoue JAMAIS /docker-entrypoint-initdb.d sur un volume
# non vide. Si une installation précédente a échoué pendant l'init (script non
# exécutable, mot de passe manquant…), le volume pgdata existe sans les rôles ni
# les bases : Keycloak boucle indéfiniment et relancer install.sh n'y change rien.
if [[ "$COMPOSE_RC" != "0" ]]; then
    PG_CID="$($COMPOSE ps -q postgres 2>/dev/null || true)"
    if [[ -n "$PG_CID" ]] && ! $ENGINE exec "$PG_CID" \
            psql -U postgres -tAc "SELECT 1 FROM pg_roles WHERE rolname = 'keycloak'" \
            2>/dev/null | grep -q '^1$'; then
        echo
        warn "Le cluster PostgreSQL existe mais le rôle 'keycloak' est absent :"
        warn "l'initialisation (postgres/init/01-init-databases.sh) n'a pas abouti."
        warn "L'init n'est jouée qu'une fois, sur un volume VIDE — il faut le recréer."
        warn "Les commandes ci-dessous SUPPRIMENT les données PostgreSQL existantes"
        warn "(le .env et sa master key, eux, sont conservés) :"
        echo "    ${COMPOSE} down"
        echo "    ${ENGINE} volume rm turingone-community_pgdata"
        echo "    ./install.sh"
        fail "Initialisation PostgreSQL incomplète — voir ci-dessus."
    fi
fi

# ── Étape 3/3 : provisioning automatique (bootstrap) ─────────────────────────
info "Étape 3/3 — Provisioning automatique (bases, Keycloak, buckets)…"
BOOT_CID="$($COMPOSE ps -aq bootstrap 2>/dev/null || true)"
if [[ -z "$BOOT_CID" ]]; then
    fail "Conteneur bootstrap introuvable — le démarrage a échoué (code $COMPOSE_RC). Logs : ${COMPOSE} logs"
fi

# Logs du bootstrap en DIRECT pendant l'attente (arrière-plan, coupé à la fin)
$COMPOSE logs -f bootstrap 2>/dev/null &
LOGS_PID=$!

ELAPSED=0
while [[ "$($ENGINE inspect -f '{{.State.Running}}' "$BOOT_CID" 2>/dev/null)" == "true" ]]; do
    sleep 5
    ELAPSED=$((ELAPSED + 5))
    # Battement de cœur discret toutes les 30 s si les logs sont silencieux
    if (( ELAPSED % 30 == 0 )); then
        info "…provisioning en cours (${ELAPSED}s) — services : $($COMPOSE ps --format '{{.Service}}={{.State}}' 2>/dev/null | tr '\n' ' ')"
    fi
done
kill "$LOGS_PID" >/dev/null 2>&1 || true
BOOT_EXIT="$($ENGINE inspect -f '{{.State.ExitCode}}' "$BOOT_CID" 2>/dev/null || echo 1)"

if [[ "$BOOT_EXIT" != "0" || "$COMPOSE_RC" != "0" ]]; then
    echo
    $COMPOSE logs bootstrap 2>/dev/null | tail -40
    fail "Le bootstrap a échoué (voir logs ci-dessus) : ${COMPOSE} logs bootstrap"
fi

# ── Résumé ───────────────────────────────────────────────────────────────────
source <(grep -E '^(FRONTEND_URL|TURINGONE_ADMIN_USERNAME|TURINGONE_ADMIN_PASSWORD|KEYCLOAK_PUBLIC_URL|KEYCLOAK_USERNAME_ADMIN|KEYCLOAK_PASSWORD_ADMIN)=' .env | sed 's/^/export /')
echo
ok "TuringOne Community est installé ! 🎉"
echo
echo    "   🌐 Application  : ${FRONTEND_URL}"
echo    "   👤 Utilisateur  : ${TURINGONE_ADMIN_USERNAME}"
echo    "   🔑 Mot de passe : ${TURINGONE_ADMIN_PASSWORD}"
echo
echo    "   🔐 Console Keycloak (admin technique) : ${KEYCLOAK_PUBLIC_URL}"
echo    "      ${KEYCLOAK_USERNAME_ADMIN} / ${KEYCLOAK_PASSWORD_ADMIN}"
echo
echo    "   Ces identifiants sont aussi dans le fichier .env (permissions 600)."
echo
echo    "   Premier démarrage du backend : téléchargement des modèles d'embeddings"
echo    "   (quelques minutes). Suivre :  ${COMPOSE} logs -f backend"
echo
warn    "Sauvegardez le fichier .env (master key de chiffrement) avec vos backups !"
