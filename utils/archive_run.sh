#!/bin/bash
# archive_run.sh - Archivage automatique des runs (inspiré de Ralph)
#
# Usage: ./archive_run.sh <feature_id>
#
# Archive les logs et l'état d'une feature lors du passage à une autre feature.

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FEATURE_ID="$1"

# Couleurs
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

if [[ -z "$FEATURE_ID" ]]; then
    echo -e "${RED}[ERROR]${NC} Usage: archive_run.sh <feature_id>"
    exit 1
fi

FEATURE_DIR="${SCRIPT_DIR}/features/${FEATURE_ID}"

if [[ ! -d "$FEATURE_DIR" ]]; then
    echo -e "${YELLOW}[WARNING]${NC} Feature non trouvée: $FEATURE_ID"
    exit 0
fi

# Créer le répertoire d'archive
DATE_SUFFIX=$(date +%Y%m%d)
ARCHIVE_DIR="${SCRIPT_DIR}/logs/archives/${FEATURE_ID}_${DATE_SUFFIX}"

if [[ -d "$ARCHIVE_DIR" ]]; then
    # Ajouter un timestamp si l'archive existe déjà
    ARCHIVE_DIR="${ARCHIVE_DIR}_$(date +%H%M%S)"
fi

mkdir -p "${ARCHIVE_DIR}/sessions"

echo -e "${BLUE}═══════════════════════════════════════════════════════════════${NC}"
echo -e "${BLUE}                 ARCHIVAGE: $FEATURE_ID                         ${NC}"
echo -e "${BLUE}═══════════════════════════════════════════════════════════════${NC}"
echo ""

# ═══════════════════════════════════════════════════════════════════
# 1. Copier les logs de session concernant cette feature
# ═══════════════════════════════════════════════════════════════════
echo -e "${BLUE}[1/4]${NC} Archivage des logs de session..."

SESSION_COUNT=0

# Extraire le numéro de feature pour le pattern
FEATURE_NUM=$(echo "$FEATURE_ID" | grep -oP 'feature_\K[0-9]{3}' || echo "")

if [[ -d "${SCRIPT_DIR}/logs/sessions" ]]; then
    for logfile in "${SCRIPT_DIR}/logs/sessions"/*.log; do
        if [[ -f "$logfile" ]]; then
            # Vérifier si le log concerne cette feature
            if grep -q "$FEATURE_ID" "$logfile" 2>/dev/null || \
               grep -q "F${FEATURE_NUM}_" "$logfile" 2>/dev/null; then
                cp "$logfile" "${ARCHIVE_DIR}/sessions/"
                SESSION_COUNT=$((SESSION_COUNT + 1))
            fi
        fi
    done
fi

echo -e "  ${GREEN}✓${NC} $SESSION_COUNT log(s) archivé(s)"

# ═══════════════════════════════════════════════════════════════════
# 2. Snapshot du status de la feature
# ═══════════════════════════════════════════════════════════════════
echo -e "${BLUE}[2/4]${NC} Snapshot du status..."

if [[ -f "${FEATURE_DIR}/feature.json" ]]; then
    cp "${FEATURE_DIR}/feature.json" "${ARCHIVE_DIR}/feature_snapshot.json"
fi

if [[ -f "${FEATURE_DIR}/tasks.json" ]]; then
    cp "${FEATURE_DIR}/tasks.json" "${ARCHIVE_DIR}/tasks_snapshot.json"
fi

echo -e "  ${GREEN}✓${NC} Snapshot créé"

# ═══════════════════════════════════════════════════════════════════
# 3. Générer un résumé
# ═══════════════════════════════════════════════════════════════════
echo -e "${BLUE}[3/4]${NC} Génération du résumé..."

TASKS_FILE="${FEATURE_DIR}/tasks.json"

if [[ -f "$TASKS_FILE" ]]; then
    TOTAL_TASKS=$(jq '.tasks | length' "$TASKS_FILE")
    TESTED=$(jq '[.tasks[] | select(.status == "Tested")] | length' "$TASKS_FILE")
    ERROR=$(jq '[.tasks[] | select(.status == "Error")] | length' "$TASKS_FILE")
    PENDING=$(jq '[.tasks[] | select(.status == "Pending")] | length' "$TASKS_FILE")
    IN_PROGRESS=$(jq '[.tasks[] | select(.status == "InProgress")] | length' "$TASKS_FILE")
else
    TOTAL_TASKS=0
    TESTED=0
    ERROR=0
    PENDING=0
    IN_PROGRESS=0
fi

cat > "${ARCHIVE_DIR}/summary.md" << EOF
# Archive: $FEATURE_ID

## Métadonnées
- **Date d'archivage**: $(date -Iseconds)
- **Feature ID**: $FEATURE_ID
- **Archive Path**: $ARCHIVE_DIR

## Résumé de progression

| Métrique | Valeur |
|----------|--------|
| Total tâches | $TOTAL_TASKS |
| Complétées (Tested) | $TESTED |
| En erreur | $ERROR |
| En attente | $PENDING |
| En cours | $IN_PROGRESS |
| Progression | $(( TOTAL_TASKS > 0 ? TESTED * 100 / TOTAL_TASKS : 0 ))% |

## Sessions archivées
- Nombre de logs: $SESSION_COUNT

## Fichiers inclus
- \`feature_snapshot.json\` - État de la feature au moment de l'archivage
- \`tasks_snapshot.json\` - État des tâches au moment de l'archivage
- \`sessions/\` - Logs des sessions Claude CLI
EOF

echo -e "  ${GREEN}✓${NC} Résumé généré"

# ═══════════════════════════════════════════════════════════════════
# 4. Créer un manifest
# ═══════════════════════════════════════════════════════════════════
echo -e "${BLUE}[4/4]${NC} Création du manifest..."

cat > "${ARCHIVE_DIR}/manifest.json" << EOF
{
  "feature_id": "$FEATURE_ID",
  "archived_at": "$(date -Iseconds)",
  "archive_path": "$ARCHIVE_DIR",
  "stats": {
    "total_tasks": $TOTAL_TASKS,
    "completed": $TESTED,
    "errors": $ERROR,
    "pending": $PENDING,
    "in_progress": $IN_PROGRESS,
    "completion_rate": $(( TOTAL_TASKS > 0 ? TESTED * 100 / TOTAL_TASKS : 0 ))
  },
  "files": {
    "session_logs": $SESSION_COUNT,
    "feature_snapshot": $([ -f "${ARCHIVE_DIR}/feature_snapshot.json" ] && echo "true" || echo "false"),
    "tasks_snapshot": $([ -f "${ARCHIVE_DIR}/tasks_snapshot.json" ] && echo "true" || echo "false")
  }
}
EOF

echo -e "  ${GREEN}✓${NC} Manifest créé"

# ═══════════════════════════════════════════════════════════════════
# RÉSUMÉ
# ═══════════════════════════════════════════════════════════════════
echo ""
echo -e "${GREEN}═══════════════════════════════════════════════════════════════${NC}"
echo -e "${GREEN}                 ARCHIVAGE TERMINÉ                              ${NC}"
echo -e "${GREEN}═══════════════════════════════════════════════════════════════${NC}"
echo ""
echo -e "Feature: ${BLUE}$FEATURE_ID${NC}"
echo -e "Archive: ${BLUE}$ARCHIVE_DIR${NC}"
echo ""
echo "Contenu:"
echo "  - $SESSION_COUNT log(s) de session"
echo "  - Snapshot feature.json et tasks.json"
echo "  - summary.md et manifest.json"
echo ""

exit 0
