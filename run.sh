#!/bin/bash
# run.sh - Script principal d'orchestration du framework multi-sessions Claude CLI
#
# Usage:
#   ./run.sh --full                           # Pipeline complet
#   ./run.sh --agent <agent-name> [options]   # Agent individuel
#
# Agents disponibles:
#   business-analyst, architect, developer, reviewer, tester
#
# Options:
#   --feature <feature_id>    Cible une feature spécifique
#   --task <task_id>          Cible une tâche spécifique
#   --update <YYMMDD:HHMM>    Traite un fichier update
#   --config <file>           Fichier de configuration
#   --model <model>           Override du modèle LLM
#   --ignore-quota            Ignorer les vérifications de quota
#   --resume-interrupted      Reprendre les tâches interrompues

set -e

# Configuration par défaut
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="${SCRIPT_DIR}/config.json"
AGENT=""
FEATURE=""
TASK=""
UPDATE=""
MODEL_OVERRIDE=""
FULL_PIPELINE=false
IGNORE_QUOTA=false
RESUME_INTERRUPTED=false

# Couleurs pour l'affichage
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Fonctions utilitaires
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Parsing des arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --full)
            FULL_PIPELINE=true
            shift
            ;;
        --agent)
            AGENT="$2"
            shift 2
            ;;
        --feature)
            FEATURE="$2"
            shift 2
            ;;
        --task)
            TASK="$2"
            shift 2
            ;;
        --update)
            UPDATE="$2"
            shift 2
            ;;
        --config)
            CONFIG_FILE="$2"
            shift 2
            ;;
        --model)
            MODEL_OVERRIDE="$2"
            shift 2
            ;;
        --ignore-quota)
            IGNORE_QUOTA=true
            shift
            ;;
        --resume-interrupted)
            RESUME_INTERRUPTED=true
            shift
            ;;
        --help|-h)
            echo "Usage: ./run.sh [--full | --agent <agent-name>] [options]"
            echo ""
            echo "Modes:"
            echo "  --full                      Exécute le pipeline complet"
            echo "  --agent business-analyst    Décompose application en features"
            echo "  --agent architect           Décompose features en tâches"
            echo "  --agent developer           Implémente les tâches"
            echo "  --agent reviewer            Review le code"
            echo "  --agent tester              Teste les critères d'acceptation"
            echo ""
            echo "Options:"
            echo "  --feature <feature_id>      Cible une feature spécifique"
            echo "  --task <task_id>            Cible une tâche spécifique"
            echo "  --update <YYMMDD:HHMM>      Traite un fichier update"
            echo "  --config <file>             Fichier de configuration"
            echo "  --model <model>             Override du modèle LLM"
            echo "  --ignore-quota              Ignorer les vérifications de quota"
            echo "  --resume-interrupted        Reprendre les tâches interrompues"
            echo "  --help                      Affiche cette aide"
            exit 0
            ;;
        *)
            log_error "Option inconnue: $1"
            echo "Utilisez --help pour voir les options disponibles."
            exit 1
            ;;
    esac
done

# Vérifier que le fichier de configuration existe
if [[ ! -f "$CONFIG_FILE" ]]; then
    log_error "Fichier de configuration non trouvé: $CONFIG_FILE"
    exit 1
fi

# Charger la configuration
load_config() {
    local key="$1"
    jq -r "$key" "$CONFIG_FILE" 2>/dev/null || echo ""
}

# Vérification des dépendances externes
check_dependencies() {
    local DEPS_FILE="${SCRIPT_DIR}/dependencies.json"

    if [[ -f "$DEPS_FILE" ]]; then
        log_info "Vérification des dépendances..."
        "${SCRIPT_DIR}/utils/check_dependencies.sh" "$DEPS_FILE" || {
            log_error "Installation des dépendances requise. Arrêt."
            exit 1
        }
    fi
}

# Vérification du quota
check_quota() {
    if [[ "$IGNORE_QUOTA" == "true" ]]; then
        log_warning "Vérification de quota ignorée (--ignore-quota)"
        return 0
    fi

    local QUOTA_ENABLED=$(load_config '.execution.quotaCheck.enabled')
    if [[ "$QUOTA_ENABLED" != "true" ]]; then
        return 0
    fi

    local MIN_PERCENT=$(load_config '.execution.quotaCheck.minRemainingPercent')
    local LOW_THRESHOLD=$(load_config '.execution.quotaCheck.lowQuotaThresholdPercent')

    # Note: Dans une vraie implémentation, on utiliserait claude --usage
    # Pour l'instant, on simule avec 100%
    local REMAINING=100

    if (( REMAINING < MIN_PERCENT )); then
        log_error "Quota critique: ${REMAINING}% restant (seuil: ${MIN_PERCENT}%)"

        local PAUSE_ON_LOW=$(load_config '.execution.quotaCheck.pauseOnLowQuota')
        if [[ "$PAUSE_ON_LOW" == "true" ]]; then
            log_warning "Pause automatique. Reprise possible après reset du quota."
            log_info "Pour forcer: ./run.sh --ignore-quota ..."
            exit 2
        fi
    elif (( REMAINING < LOW_THRESHOLD )); then
        log_warning "Quota faible: ${REMAINING}% restant. Mode économique activé."
        log_info "Seules les tâches prioritaires (critical, high) seront exécutées."
    else
        log_success "Quota OK: ${REMAINING}% restant"
    fi

    return 0
}

# Obtenir le modèle pour un agent
get_model_for_agent() {
    local AGENT_TYPE="$1"

    if [[ -n "$MODEL_OVERRIDE" ]]; then
        echo "$MODEL_OVERRIDE"
        return
    fi

    local MODEL=$(jq -r ".models[\"$AGENT_TYPE\"] // .models.default" "$CONFIG_FILE")
    echo "$MODEL"
}

# Générer un ID de session unique
generate_session_id() {
    local AGENT_TYPE="$1"
    echo "${AGENT_TYPE}_$(date +%Y%m%d_%H%M%S)_$$"
}

# Nouvelle session Claude CLI (isolée)
invoke_agent() {
    local AGENT_TYPE="$1"
    local AGENT_PROMPT_FILE="$2"
    shift 2
    local CONTEXT_ARGS="$@"

    local SESSION_ID=$(generate_session_id "$AGENT_TYPE")
    local LOG_FILE="${SCRIPT_DIR}/logs/sessions/${SESSION_ID}.log"

    log_info "=== Nouvelle session: $AGENT_TYPE ==="
    log_info "Session ID: $SESSION_ID"

    # Vérifier le quota avant invocation
    check_quota

    # Obtenir le modèle configuré pour cet agent
    local MODEL=$(get_model_for_agent "$AGENT_TYPE")
    log_info "Modèle: $MODEL"

    # Lire le prompt de l'agent
    if [[ ! -f "$AGENT_PROMPT_FILE" ]]; then
        log_error "Fichier prompt non trouvé: $AGENT_PROMPT_FILE"
        return 1
    fi

    local AGENT_PROMPT=$(cat "$AGENT_PROMPT_FILE")

    # Créer le répertoire de logs si nécessaire
    mkdir -p "$(dirname "$LOG_FILE")"

    # Construire la commande claude
    local CLAUDE_CMD="claude"
    CLAUDE_CMD+=" --print"
    CLAUDE_CMD+=" --model $MODEL"
    CLAUDE_CMD+=" --dangerously-skip-permissions"

    # Ajouter les fichiers de contexte
    for ctx in $CONTEXT_ARGS; do
        if [[ -f "$ctx" ]]; then
            CLAUDE_CMD+=" --context $ctx"
        elif [[ -d "$ctx" ]]; then
            CLAUDE_CMD+=" --context $ctx"
        fi
    done

    # Exécuter et logger
    log_info "Exécution de la session..."
    echo "=== Session $SESSION_ID ===" > "$LOG_FILE"
    echo "Agent: $AGENT_TYPE" >> "$LOG_FILE"
    echo "Model: $MODEL" >> "$LOG_FILE"
    echo "Started: $(date -Iseconds)" >> "$LOG_FILE"
    echo "---" >> "$LOG_FILE"

    # Note: Dans une vraie implémentation, on exécuterait:
    # echo "$AGENT_PROMPT" | $CLAUDE_CMD 2>&1 | tee -a "$LOG_FILE"

    # Pour l'instant, on simule
    echo "[SIMULATED] Would execute: $CLAUDE_CMD" >> "$LOG_FILE"
    echo "[SIMULATED] With prompt from: $AGENT_PROMPT_FILE" >> "$LOG_FILE"

    echo "---" >> "$LOG_FILE"
    echo "Completed: $(date -Iseconds)" >> "$LOG_FILE"

    log_success "Session terminée. Log: $LOG_FILE"

    return 0
}

# Archiver le run précédent si nécessaire
archive_previous_run() {
    local NEW_FEATURE="$1"
    local CURRENT_FEATURE_FILE="${SCRIPT_DIR}/.current_feature"

    if [[ -f "$CURRENT_FEATURE_FILE" ]]; then
        local CURRENT_FEATURE=$(cat "$CURRENT_FEATURE_FILE")

        if [[ -n "$CURRENT_FEATURE" && "$CURRENT_FEATURE" != "$NEW_FEATURE" ]]; then
            local ARCHIVE_ENABLED=$(load_config '.archiving.enabled')
            local ARCHIVE_ON_CHANGE=$(load_config '.archiving.archiveOnFeatureChange')

            if [[ "$ARCHIVE_ENABLED" == "true" && "$ARCHIVE_ON_CHANGE" == "true" ]]; then
                log_info "Archivage de $CURRENT_FEATURE..."
                "${SCRIPT_DIR}/utils/archive_run.sh" "$CURRENT_FEATURE" 2>/dev/null || true
            fi
        fi
    fi

    echo "$NEW_FEATURE" > "$CURRENT_FEATURE_FILE"
}

# Reprendre les tâches interrompues
resume_interrupted_tasks() {
    log_info "Recherche des tâches interrompues..."

    local INTERRUPTED_COUNT=0

    for tasks_file in "${SCRIPT_DIR}"/features/*/tasks.json; do
        if [[ -f "$tasks_file" ]]; then
            local INTERRUPTED=$(jq -r '.tasks[] | select(.status == "Interrupted") | .id' "$tasks_file" 2>/dev/null)

            for task_id in $INTERRUPTED; do
                log_info "Reprise de la tâche: $task_id"
                INTERRUPTED_COUNT=$((INTERRUPTED_COUNT + 1))

                # Mettre à jour le statut → Pending pour re-traitement
                "${SCRIPT_DIR}/utils/status_updater.sh" set_status "$task_id" "Pending" "Auto-resumed"
            done
        fi
    done

    if [[ $INTERRUPTED_COUNT -eq 0 ]]; then
        log_info "Aucune tâche interrompue trouvée."
    else
        log_success "$INTERRUPTED_COUNT tâche(s) remise(s) en attente."
        log_info "Exécutez './run.sh --agent developer' pour les traiter."
    fi
}

# Mode: Reprendre les tâches interrompues
if [[ "$RESUME_INTERRUPTED" == "true" ]]; then
    resume_interrupted_tasks
    exit 0
fi

# Vérifier les dépendances au démarrage
check_dependencies

# Mode: Pipeline complet
if [[ "$FULL_PIPELINE" == true ]]; then
    log_info "=== Exécution pipeline complet ==="

    # Phase 1: Business Analyst
    log_info "Phase 1: Business Analyst"
    invoke_agent "business-analyst" \
        "${SCRIPT_DIR}/agents/business-analyst.md" \
        "${SCRIPT_DIR}/application.md" \
        "${SCRIPT_DIR}/context/glossary.md"

    # Phase 2: Architect (toutes les features)
    log_info "Phase 2: Architect"
    for feature_dir in "${SCRIPT_DIR}"/features/*/; do
        if [[ -d "$feature_dir" ]]; then
            local feature_file="${feature_dir}feature.json"
            if [[ -f "$feature_file" ]]; then
                invoke_agent "architect" \
                    "${SCRIPT_DIR}/agents/architect-task-decompose.md" \
                    "$feature_file"
            fi
        fi
    done

    # Phase 3: Developer (toutes les tâches)
    log_info "Phase 3: Developer"
    "${SCRIPT_DIR}/scripts/run_feature_tasks.sh" "${SCRIPT_DIR}/features/" "$CONFIG_FILE"

    log_success "Pipeline complet terminé."
    exit 0
fi

# Mode: Agent individuel
case $AGENT in
    business-analyst)
        if [[ -n "$UPDATE" ]]; then
            INPUT_FILE="${SCRIPT_DIR}/application_update_${UPDATE}.md"
            if [[ ! -f "$INPUT_FILE" ]]; then
                log_error "Fichier update non trouvé: $INPUT_FILE"
                exit 1
            fi
        else
            INPUT_FILE="${SCRIPT_DIR}/application.md"
            if [[ ! -f "$INPUT_FILE" ]]; then
                log_error "Fichier application.md non trouvé"
                exit 1
            fi
        fi

        invoke_agent "business-analyst" \
            "${SCRIPT_DIR}/agents/business-analyst.md" \
            "$INPUT_FILE" \
            "${SCRIPT_DIR}/context/glossary.md"
        ;;

    architect)
        if [[ -n "$FEATURE" ]]; then
            FEATURE_DIR="${SCRIPT_DIR}/features/${FEATURE}"
            if [[ ! -d "$FEATURE_DIR" ]]; then
                log_error "Feature non trouvée: $FEATURE"
                exit 1
            fi

            archive_previous_run "$FEATURE"

            invoke_agent "architect" \
                "${SCRIPT_DIR}/agents/architect-task-decompose.md" \
                "${FEATURE_DIR}/feature.json"
        else
            for feature_dir in "${SCRIPT_DIR}"/features/*/; do
                if [[ -d "$feature_dir" ]]; then
                    local feature_file="${feature_dir}feature.json"
                    if [[ -f "$feature_file" ]]; then
                        local feature_id=$(basename "$feature_dir")
                        archive_previous_run "$feature_id"

                        invoke_agent "architect" \
                            "${SCRIPT_DIR}/agents/architect-task-decompose.md" \
                            "$feature_file"
                    fi
                fi
            done
        fi
        ;;

    developer)
        if [[ -n "$TASK" ]]; then
            # Extraire feature_id du task_id (F001_T003 → feature_001)
            FEATURE_NUM=$(echo "$TASK" | grep -oP 'F\K[0-9]{3}')
            FEATURE_DIR=$(find "${SCRIPT_DIR}/features" -maxdepth 1 -type d -name "feature_${FEATURE_NUM}_*" | head -1)

            if [[ -z "$FEATURE_DIR" ]]; then
                log_error "Feature non trouvée pour la tâche: $TASK"
                exit 1
            fi

            archive_previous_run "$(basename "$FEATURE_DIR")"

            "${SCRIPT_DIR}/scripts/ralph_wiggum_task.sh" "$TASK" "$FEATURE_DIR" "$CONFIG_FILE"

        elif [[ -n "$FEATURE" ]]; then
            FEATURE_DIR="${SCRIPT_DIR}/features/${FEATURE}"
            if [[ ! -d "$FEATURE_DIR" ]]; then
                log_error "Feature non trouvée: $FEATURE"
                exit 1
            fi

            archive_previous_run "$FEATURE"

            "${SCRIPT_DIR}/scripts/run_feature_tasks.sh" "$FEATURE_DIR" "$CONFIG_FILE"
        else
            "${SCRIPT_DIR}/scripts/run_feature_tasks.sh" "${SCRIPT_DIR}/features/" "$CONFIG_FILE"
        fi
        ;;

    reviewer)
        if [[ -z "$TASK" ]]; then
            log_error "--task requis pour reviewer"
            echo "Usage: ./run.sh --agent reviewer --task F001_T003"
            exit 1
        fi

        FEATURE_NUM=$(echo "$TASK" | grep -oP 'F\K[0-9]{3}')
        FEATURE_DIR=$(find "${SCRIPT_DIR}/features" -maxdepth 1 -type d -name "feature_${FEATURE_NUM}_*" | head -1)

        if [[ -z "$FEATURE_DIR" ]]; then
            log_error "Feature non trouvée pour la tâche: $TASK"
            exit 1
        fi

        invoke_agent "reviewer" \
            "${SCRIPT_DIR}/agents/reviewer-prompt.md" \
            "${FEATURE_DIR}/tasks.json" \
            "${SCRIPT_DIR}/context/conventions.md"
        ;;

    tester)
        if [[ -z "$TASK" ]]; then
            log_error "--task requis pour tester"
            echo "Usage: ./run.sh --agent tester --task F001_T003"
            exit 1
        fi

        FEATURE_NUM=$(echo "$TASK" | grep -oP 'F\K[0-9]{3}')
        FEATURE_DIR=$(find "${SCRIPT_DIR}/features" -maxdepth 1 -type d -name "feature_${FEATURE_NUM}_*" | head -1)

        if [[ -z "$FEATURE_DIR" ]]; then
            log_error "Feature non trouvée pour la tâche: $TASK"
            exit 1
        fi

        invoke_agent "tester" \
            "${SCRIPT_DIR}/agents/tester-prompt.md" \
            "${FEATURE_DIR}/tasks.json"
        ;;

    "")
        log_error "Aucun mode spécifié. Utilisez --full ou --agent <agent-name>"
        echo "Utilisez --help pour voir les options disponibles."
        exit 1
        ;;

    *)
        log_error "Agent inconnu: $AGENT"
        echo "Agents disponibles: business-analyst, architect, developer, reviewer, tester"
        exit 1
        ;;
esac
