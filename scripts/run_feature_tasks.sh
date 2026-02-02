#!/bin/bash
# run_feature_tasks.sh - Lance toutes les tâches d'une ou plusieurs features en parallèle
#
# Usage: ./run_feature_tasks.sh <feature_dir_or_features_root> [config_file]
#
# Si le chemin est un répertoire de feature (contient tasks.json), traite cette feature.
# Si le chemin est le répertoire features/, traite toutes les features.

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TARGET_DIR="$1"
CONFIG_FILE="${2:-${SCRIPT_DIR}/config.json}"

# Couleurs
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
log_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }
log_header() { echo -e "${CYAN}$1${NC}"; }

# Validation
if [[ -z "$TARGET_DIR" ]]; then
    log_error "Usage: $0 <feature_dir_or_features_root> [config_file]"
    exit 1
fi

if [[ ! -f "$CONFIG_FILE" ]]; then
    log_error "Fichier de configuration non trouvé: $CONFIG_FILE"
    exit 1
fi

# Charger la configuration
MAX_PARALLEL=$(jq -r '.execution.maxParallelSessions // 3' "$CONFIG_FILE")
LOW_QUOTA_THRESHOLD=$(jq -r '.execution.quotaCheck.lowQuotaThresholdPercent // 30' "$CONFIG_FILE")
LOW_QUOTA_STRATEGY=$(jq -r '.execution.quotaCheck.lowQuotaStrategy // "prioritize-critical"' "$CONFIG_FILE")

log_header "╔═══════════════════════════════════════════════════════════════╗"
log_header "║       ORCHESTRATION DES TÂCHES - FRAMEWORK MULTI-SESSIONS     ║"
log_header "╚═══════════════════════════════════════════════════════════════╝"

log_info "Configuration:"
log_info "  - Sessions parallèles max: $MAX_PARALLEL"
log_info "  - Config: $CONFIG_FILE"

# Collecter toutes les tâches à exécuter
collect_tasks() {
    local DIR="$1"
    local TASKS=()

    # Si c'est un répertoire de feature unique
    if [[ -f "${DIR}/tasks.json" ]]; then
        local FEATURE_ID=$(jq -r '.featureId' "${DIR}/tasks.json")
        log_info "Feature: $FEATURE_ID"

        # Récupérer les tâches Pending triées par priorité
        while IFS= read -r task_id; do
            if [[ -n "$task_id" ]]; then
                TASKS+=("$task_id:$DIR")
            fi
        done < <(jq -r '
            .tasks[]
            | select(.status == "Pending")
            | select(.priority != null)
            | {id, priority}
            | .priority_order = (
                if .priority == "critical" then 1
                elif .priority == "high" then 2
                elif .priority == "medium" then 3
                else 4
                end
            )
            | .id
        ' "${DIR}/tasks.json" | head -100)

    # Si c'est le répertoire racine des features
    elif [[ -d "$DIR" ]]; then
        for feature_dir in "${DIR}"/*/; do
            if [[ -f "${feature_dir}tasks.json" ]]; then
                local FEATURE_ID=$(jq -r '.featureId' "${feature_dir}tasks.json")
                log_info "Feature trouvée: $FEATURE_ID"

                while IFS= read -r task_id; do
                    if [[ -n "$task_id" ]]; then
                        TASKS+=("$task_id:${feature_dir}")
                    fi
                done < <(jq -r '
                    .tasks[]
                    | select(.status == "Pending")
                    | .id
                ' "${feature_dir}tasks.json" | head -100)
            fi
        done
    fi

    printf '%s\n' "${TASKS[@]}"
}

# Exécuter une tâche
run_task() {
    local TASK_INFO="$1"
    local TASK_ID="${TASK_INFO%%:*}"
    local FEATURE_DIR="${TASK_INFO#*:}"

    log_info "→ Démarrage: $TASK_ID"

    "${SCRIPT_DIR}/scripts/ralph_wiggum_task.sh" "$TASK_ID" "$FEATURE_DIR" "$CONFIG_FILE"

    local EXIT_CODE=$?

    if [[ $EXIT_CODE -eq 0 ]]; then
        log_success "← Terminé: $TASK_ID"
    elif [[ $EXIT_CODE -eq 2 ]]; then
        log_warning "← Bloqué: $TASK_ID"
    else
        log_error "← Échec: $TASK_ID (code: $EXIT_CODE)"
    fi

    return $EXIT_CODE
}

# Mode économique (quota faible) - filtrer par priorité
filter_by_priority() {
    local TASKS=("$@")
    local FILTERED=()

    for task_info in "${TASKS[@]}"; do
        local TASK_ID="${task_info%%:*}"
        local FEATURE_DIR="${task_info#*:}"
        local TASKS_FILE="${FEATURE_DIR}/tasks.json"

        if [[ -f "$TASKS_FILE" ]]; then
            local PRIORITY=$(jq -r ".tasks[] | select(.id == \"$TASK_ID\") | .priority" "$TASKS_FILE")

            if [[ "$PRIORITY" == "critical" || "$PRIORITY" == "high" ]]; then
                FILTERED+=("$task_info")
            fi
        fi
    done

    printf '%s\n' "${FILTERED[@]}"
}

# Collecter les tâches
log_info "Collecte des tâches..."
mapfile -t ALL_TASKS < <(collect_tasks "$TARGET_DIR")

if [[ ${#ALL_TASKS[@]} -eq 0 ]]; then
    log_warning "Aucune tâche Pending trouvée."
    exit 0
fi

log_info "Tâches trouvées: ${#ALL_TASKS[@]}"

# Vérifier le mode quota (simulation)
QUOTA_MODE="normal"
# Dans une vraie implémentation, on vérifierait le quota ici
# Si quota < LOW_QUOTA_THRESHOLD, QUOTA_MODE="low"

if [[ "$QUOTA_MODE" == "low" && "$LOW_QUOTA_STRATEGY" == "prioritize-critical" ]]; then
    log_warning "Mode économique: seules les tâches critical/high seront exécutées"
    mapfile -t FILTERED_TASKS < <(filter_by_priority "${ALL_TASKS[@]}")
    ALL_TASKS=("${FILTERED_TASKS[@]}")
    log_info "Tâches filtrées: ${#ALL_TASKS[@]}"
fi

# Exécuter les tâches en parallèle avec limite
log_header ""
log_header "═══════════════════════════════════════════════════════════════"
log_header "                   EXÉCUTION DES TÂCHES"
log_header "═══════════════════════════════════════════════════════════════"

TOTAL=${#ALL_TASKS[@]}
COMPLETED=0
FAILED=0
BLOCKED=0
RUNNING=0

# Fonction pour suivre les jobs en parallèle
declare -A RUNNING_JOBS

process_tasks() {
    local TASK_INDEX=0

    while [[ $TASK_INDEX -lt $TOTAL || $RUNNING -gt 0 ]]; do
        # Lancer de nouveaux jobs si possible
        while [[ $RUNNING -lt $MAX_PARALLEL && $TASK_INDEX -lt $TOTAL ]]; do
            local TASK_INFO="${ALL_TASKS[$TASK_INDEX]}"
            local TASK_ID="${TASK_INFO%%:*}"

            log_info "Lancement [$((TASK_INDEX + 1))/$TOTAL]: $TASK_ID"

            run_task "$TASK_INFO" &
            RUNNING_JOBS[$!]="$TASK_INFO"
            RUNNING=$((RUNNING + 1))
            TASK_INDEX=$((TASK_INDEX + 1))
        done

        # Attendre qu'un job se termine
        if [[ $RUNNING -gt 0 ]]; then
            wait -n 2>/dev/null || true

            # Vérifier quels jobs sont terminés
            for pid in "${!RUNNING_JOBS[@]}"; do
                if ! kill -0 "$pid" 2>/dev/null; then
                    wait "$pid" 2>/dev/null
                    local EXIT_CODE=$?
                    local TASK_INFO="${RUNNING_JOBS[$pid]}"
                    local TASK_ID="${TASK_INFO%%:*}"

                    if [[ $EXIT_CODE -eq 0 ]]; then
                        COMPLETED=$((COMPLETED + 1))
                    elif [[ $EXIT_CODE -eq 2 ]]; then
                        BLOCKED=$((BLOCKED + 1))
                    else
                        FAILED=$((FAILED + 1))
                    fi

                    unset "RUNNING_JOBS[$pid]"
                    RUNNING=$((RUNNING - 1))
                fi
            done
        fi
    done
}

# Exécuter avec gestion parallèle
process_tasks

# Résumé
log_header ""
log_header "═══════════════════════════════════════════════════════════════"
log_header "                         RÉSUMÉ"
log_header "═══════════════════════════════════════════════════════════════"

echo ""
log_info "Total des tâches:    $TOTAL"
log_success "Complétées:          $COMPLETED"

if [[ $BLOCKED -gt 0 ]]; then
    log_warning "Bloquées:            $BLOCKED"
fi

if [[ $FAILED -gt 0 ]]; then
    log_error "Échouées:            $FAILED"
fi

echo ""

# Code de sortie
if [[ $FAILED -gt 0 ]]; then
    log_error "Certaines tâches ont échoué."
    exit 1
elif [[ $BLOCKED -gt 0 ]]; then
    log_warning "Certaines tâches sont bloquées."
    exit 2
else
    log_success "Toutes les tâches ont été complétées avec succès!"
    exit 0
fi
