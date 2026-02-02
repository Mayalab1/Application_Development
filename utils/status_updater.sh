#!/bin/bash
# status_updater.sh - Mise à jour des statuts des tâches et features
#
# Usage:
#   ./status_updater.sh set_status <task_id> <status> [reason] [tasks_file]
#   ./status_updater.sh get_status <task_id> [tasks_file]
#   ./status_updater.sh update_feature <feature_id>
#   ./status_updater.sh report [features_dir]

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# Couleurs
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# Statuts valides
VALID_STATUSES=("Pending" "InProgress" "Implemented" "Reviewed" "Tested" "Interrupted" "Error" "Blocked")

# Fonction: Vérifier si un statut est valide
is_valid_status() {
    local STATUS="$1"
    for valid in "${VALID_STATUSES[@]}"; do
        if [[ "$STATUS" == "$valid" ]]; then
            return 0
        fi
    done
    return 1
}

# Fonction: Trouver le fichier tasks.json pour une tâche
find_tasks_file() {
    local TASK_ID="$1"

    # Extraire le numéro de feature (F001 → 001)
    local FEATURE_NUM=$(echo "$TASK_ID" | grep -oP 'F\K[0-9]{3}')

    # Chercher le répertoire de feature correspondant
    local FEATURE_DIR=$(find "${SCRIPT_DIR}/features" -maxdepth 1 -type d -name "feature_${FEATURE_NUM}_*" 2>/dev/null | head -1)

    if [[ -n "$FEATURE_DIR" && -f "${FEATURE_DIR}/tasks.json" ]]; then
        echo "${FEATURE_DIR}/tasks.json"
        return 0
    fi

    return 1
}

# Fonction: Mettre à jour le statut d'une tâche
set_status() {
    local TASK_ID="$1"
    local NEW_STATUS="$2"
    local REASON="${3:-}"
    local TASKS_FILE="${4:-}"

    if [[ -z "$TASK_ID" || -z "$NEW_STATUS" ]]; then
        echo -e "${RED}[ERROR]${NC} Usage: status_updater.sh set_status <task_id> <status> [reason] [tasks_file]" >&2
        return 1
    fi

    # Valider le statut
    if ! is_valid_status "$NEW_STATUS"; then
        echo -e "${RED}[ERROR]${NC} Statut invalide: $NEW_STATUS" >&2
        echo -e "${RED}[ERROR]${NC} Statuts valides: ${VALID_STATUSES[*]}" >&2
        return 1
    fi

    # Trouver le fichier tasks.json si non spécifié
    if [[ -z "$TASKS_FILE" ]]; then
        TASKS_FILE=$(find_tasks_file "$TASK_ID")
        if [[ -z "$TASKS_FILE" ]]; then
            echo -e "${RED}[ERROR]${NC} Impossible de trouver tasks.json pour $TASK_ID" >&2
            return 1
        fi
    fi

    if [[ ! -f "$TASKS_FILE" ]]; then
        echo -e "${RED}[ERROR]${NC} Fichier non trouvé: $TASKS_FILE" >&2
        return 1
    fi

    # Vérifier que la tâche existe
    local TASK_EXISTS=$(jq -r ".tasks[] | select(.id == \"$TASK_ID\") | .id" "$TASKS_FILE")
    if [[ -z "$TASK_EXISTS" ]]; then
        echo -e "${RED}[ERROR]${NC} Tâche non trouvée: $TASK_ID" >&2
        return 1
    fi

    local NOW=$(date -Iseconds)
    local OLD_STATUS=$(jq -r ".tasks[] | select(.id == \"$TASK_ID\") | .status" "$TASKS_FILE")

    # Mettre à jour le statut et l'historique
    local TEMP_FILE=$(mktemp)

    jq --arg task_id "$TASK_ID" \
       --arg new_status "$NEW_STATUS" \
       --arg reason "$REASON" \
       --arg timestamp "$NOW" \
       '
       (.tasks[] | select(.id == $task_id)) |= (
         .status = $new_status |
         .statusHistory += [{
           status: $new_status,
           timestamp: $timestamp,
           reason: $reason
         }] |
         if $new_status == "InProgress" then
           .execution.startedAt = $timestamp
         elif $new_status == "Tested" or $new_status == "Error" then
           .execution.completedAt = $timestamp
         else
           .
         end |
         if $new_status == "Error" then
           .execution.attempts = (.execution.attempts + 1)
         else
           .
         end
       )
       ' "$TASKS_FILE" > "$TEMP_FILE"

    mv "$TEMP_FILE" "$TASKS_FILE"

    echo -e "${GREEN}[OK]${NC} $TASK_ID: $OLD_STATUS → $NEW_STATUS"

    if [[ -n "$REASON" ]]; then
        echo -e "${BLUE}[INFO]${NC} Raison: $REASON"
    fi

    return 0
}

# Fonction: Obtenir le statut d'une tâche
get_status() {
    local TASK_ID="$1"
    local TASKS_FILE="${2:-}"

    if [[ -z "$TASK_ID" ]]; then
        echo -e "${RED}[ERROR]${NC} Usage: status_updater.sh get_status <task_id> [tasks_file]" >&2
        return 1
    fi

    # Trouver le fichier tasks.json si non spécifié
    if [[ -z "$TASKS_FILE" ]]; then
        TASKS_FILE=$(find_tasks_file "$TASK_ID")
        if [[ -z "$TASKS_FILE" ]]; then
            echo -e "${RED}[ERROR]${NC} Impossible de trouver tasks.json pour $TASK_ID" >&2
            return 1
        fi
    fi

    if [[ ! -f "$TASKS_FILE" ]]; then
        echo -e "${RED}[ERROR]${NC} Fichier non trouvé: $TASKS_FILE" >&2
        return 1
    fi

    local STATUS=$(jq -r ".tasks[] | select(.id == \"$TASK_ID\") | .status" "$TASKS_FILE")

    if [[ -z "$STATUS" || "$STATUS" == "null" ]]; then
        echo -e "${RED}[ERROR]${NC} Tâche non trouvée: $TASK_ID" >&2
        return 1
    fi

    echo "$STATUS"
    return 0
}

# Fonction: Mettre à jour le statut d'une feature basé sur ses tâches
update_feature() {
    local FEATURE_ID="$1"

    if [[ -z "$FEATURE_ID" ]]; then
        echo -e "${RED}[ERROR]${NC} Usage: status_updater.sh update_feature <feature_id>" >&2
        return 1
    fi

    local FEATURE_DIR="${SCRIPT_DIR}/features/${FEATURE_ID}"
    local FEATURE_FILE="${FEATURE_DIR}/feature.json"
    local TASKS_FILE="${FEATURE_DIR}/tasks.json"

    if [[ ! -f "$FEATURE_FILE" ]]; then
        echo -e "${RED}[ERROR]${NC} Feature non trouvée: $FEATURE_ID" >&2
        return 1
    fi

    if [[ ! -f "$TASKS_FILE" ]]; then
        echo -e "${YELLOW}[WARNING]${NC} Pas de tasks.json pour $FEATURE_ID" >&2
        return 0
    fi

    # Compter les tâches par statut
    local TOTAL=$(jq '.tasks | length' "$TASKS_FILE")
    local PENDING=$(jq '[.tasks[] | select(.status == "Pending")] | length' "$TASKS_FILE")
    local IN_PROGRESS=$(jq '[.tasks[] | select(.status == "InProgress")] | length' "$TASKS_FILE")
    local TESTED=$(jq '[.tasks[] | select(.status == "Tested")] | length' "$TASKS_FILE")
    local ERROR=$(jq '[.tasks[] | select(.status == "Error")] | length' "$TASKS_FILE")

    # Déterminer le statut de la feature
    local NEW_STATUS="Ready"

    if [[ $TESTED -eq $TOTAL ]]; then
        NEW_STATUS="Completed"
    elif [[ $IN_PROGRESS -gt 0 ]]; then
        NEW_STATUS="InProgress"
    elif [[ $PENDING -lt $TOTAL && $PENDING -gt 0 ]]; then
        NEW_STATUS="InProgress"
    fi

    # Mettre à jour la feature
    local NOW=$(date -Iseconds)
    local TEMP_FILE=$(mktemp)

    jq --arg status "$NEW_STATUS" --arg updated "$NOW" \
       '.status = $status | .updatedAt = $updated' \
       "$FEATURE_FILE" > "$TEMP_FILE"

    mv "$TEMP_FILE" "$FEATURE_FILE"

    echo -e "${GREEN}[OK]${NC} Feature $FEATURE_ID: $NEW_STATUS"
    echo -e "${BLUE}[INFO]${NC} Tâches: $TESTED/$TOTAL complétées, $IN_PROGRESS en cours, $ERROR en erreur"

    return 0
}

# Fonction: Générer un rapport de progression
generate_report() {
    local FEATURES_DIR="${1:-${SCRIPT_DIR}/features}"

    echo -e "${CYAN}═══════════════════════════════════════════════════════════════${NC}"
    echo -e "${CYAN}                    RAPPORT DE PROGRESSION                      ${NC}"
    echo -e "${CYAN}═══════════════════════════════════════════════════════════════${NC}"
    echo ""

    local TOTAL_TASKS=0
    local TOTAL_PENDING=0
    local TOTAL_IN_PROGRESS=0
    local TOTAL_IMPLEMENTED=0
    local TOTAL_REVIEWED=0
    local TOTAL_TESTED=0
    local TOTAL_ERROR=0
    local TOTAL_BLOCKED=0

    for feature_dir in "${FEATURES_DIR}"/*/; do
        if [[ -d "$feature_dir" ]]; then
            local FEATURE_FILE="${feature_dir}feature.json"
            local TASKS_FILE="${feature_dir}tasks.json"

            if [[ -f "$FEATURE_FILE" ]]; then
                local FEATURE_ID=$(jq -r '.id' "$FEATURE_FILE")
                local FEATURE_TITLE=$(jq -r '.title' "$FEATURE_FILE")
                local FEATURE_STATUS=$(jq -r '.status' "$FEATURE_FILE")

                echo -e "${BLUE}📦 $FEATURE_ID${NC}: $FEATURE_TITLE"
                echo -e "   Status: $FEATURE_STATUS"

                if [[ -f "$TASKS_FILE" ]]; then
                    local TASKS=$(jq '.tasks | length' "$TASKS_FILE")
                    local PENDING=$(jq '[.tasks[] | select(.status == "Pending")] | length' "$TASKS_FILE")
                    local IN_PROGRESS=$(jq '[.tasks[] | select(.status == "InProgress")] | length' "$TASKS_FILE")
                    local IMPLEMENTED=$(jq '[.tasks[] | select(.status == "Implemented")] | length' "$TASKS_FILE")
                    local REVIEWED=$(jq '[.tasks[] | select(.status == "Reviewed")] | length' "$TASKS_FILE")
                    local TESTED=$(jq '[.tasks[] | select(.status == "Tested")] | length' "$TASKS_FILE")
                    local ERROR=$(jq '[.tasks[] | select(.status == "Error")] | length' "$TASKS_FILE")
                    local BLOCKED=$(jq '[.tasks[] | select(.status == "Blocked")] | length' "$TASKS_FILE")

                    echo -e "   Tâches: $TASKS total"

                    local BAR_WIDTH=30
                    local COMPLETED=$((TESTED + REVIEWED + IMPLEMENTED))
                    local PROGRESS=$((COMPLETED * BAR_WIDTH / TASKS))

                    printf "   Progress: ["
                    printf "%${PROGRESS}s" | tr ' ' '█'
                    printf "%$((BAR_WIDTH - PROGRESS))s" | tr ' ' '░'
                    printf "] %d%%\n" $((COMPLETED * 100 / TASKS))

                    echo "   ├─ Pending: $PENDING"
                    echo "   ├─ In Progress: $IN_PROGRESS"
                    echo "   ├─ Implemented: $IMPLEMENTED"
                    echo "   ├─ Reviewed: $REVIEWED"
                    echo "   ├─ Tested: $TESTED"

                    if [[ $ERROR -gt 0 ]]; then
                        echo -e "   ├─ ${RED}Error: $ERROR${NC}"
                    fi

                    if [[ $BLOCKED -gt 0 ]]; then
                        echo -e "   └─ ${YELLOW}Blocked: $BLOCKED${NC}"
                    fi

                    # Accumuler les totaux
                    TOTAL_TASKS=$((TOTAL_TASKS + TASKS))
                    TOTAL_PENDING=$((TOTAL_PENDING + PENDING))
                    TOTAL_IN_PROGRESS=$((TOTAL_IN_PROGRESS + IN_PROGRESS))
                    TOTAL_IMPLEMENTED=$((TOTAL_IMPLEMENTED + IMPLEMENTED))
                    TOTAL_REVIEWED=$((TOTAL_REVIEWED + REVIEWED))
                    TOTAL_TESTED=$((TOTAL_TESTED + TESTED))
                    TOTAL_ERROR=$((TOTAL_ERROR + ERROR))
                    TOTAL_BLOCKED=$((TOTAL_BLOCKED + BLOCKED))
                fi
                echo ""
            fi
        fi
    done

    echo -e "${CYAN}───────────────────────────────────────────────────────────────${NC}"
    echo -e "${CYAN}                         TOTAUX                                ${NC}"
    echo -e "${CYAN}───────────────────────────────────────────────────────────────${NC}"

    if [[ $TOTAL_TASKS -gt 0 ]]; then
        local TOTAL_COMPLETED=$((TOTAL_TESTED + TOTAL_REVIEWED + TOTAL_IMPLEMENTED))
        local OVERALL_PROGRESS=$((TOTAL_COMPLETED * 100 / TOTAL_TASKS))

        echo "Total tâches: $TOTAL_TASKS"
        echo "Progression globale: $OVERALL_PROGRESS%"
        echo ""
        echo "Par statut:"
        echo "  ⏳ Pending:      $TOTAL_PENDING"
        echo "  🔄 In Progress:  $TOTAL_IN_PROGRESS"
        echo "  📝 Implemented:  $TOTAL_IMPLEMENTED"
        echo "  👁  Reviewed:     $TOTAL_REVIEWED"
        echo "  ✅ Tested:       $TOTAL_TESTED"

        if [[ $TOTAL_ERROR -gt 0 ]]; then
            echo -e "  ${RED}❌ Error:        $TOTAL_ERROR${NC}"
        fi

        if [[ $TOTAL_BLOCKED -gt 0 ]]; then
            echo -e "  ${YELLOW}🚫 Blocked:      $TOTAL_BLOCKED${NC}"
        fi
    else
        echo "Aucune tâche trouvée."
    fi

    echo ""
    echo -e "${CYAN}═══════════════════════════════════════════════════════════════${NC}"

    return 0
}

# Point d'entrée principal
case "${1:-}" in
    set_status)
        shift
        set_status "$@"
        ;;
    get_status)
        shift
        get_status "$@"
        ;;
    update_feature)
        shift
        update_feature "$@"
        ;;
    report)
        shift
        generate_report "$@"
        ;;
    *)
        echo "Usage: $0 <command> [arguments]"
        echo ""
        echo "Commands:"
        echo "  set_status <task_id> <status> [reason] [tasks_file]"
        echo "  get_status <task_id> [tasks_file]"
        echo "  update_feature <feature_id>"
        echo "  report [features_dir]"
        echo ""
        echo "Valid statuses: ${VALID_STATUSES[*]}"
        exit 1
        ;;
esac
