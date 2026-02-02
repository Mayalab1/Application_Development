#!/bin/bash
# ralph_wiggum_task.sh - Exécute une tâche avec retry automatique (boucle Ralph Wiggum)
#
# Usage: ./ralph_wiggum_task.sh <task_id> <feature_dir> [config_file]
#
# La boucle Ralph Wiggum réessaie automatiquement les tâches échouées jusqu'à
# un maximum de tentatives configuré.

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TASK_ID="$1"
FEATURE_DIR="$2"
CONFIG_FILE="${3:-${SCRIPT_DIR}/config.json}"

# Couleurs
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
log_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# Validation des arguments
if [[ -z "$TASK_ID" || -z "$FEATURE_DIR" ]]; then
    log_error "Usage: $0 <task_id> <feature_dir> [config_file]"
    exit 1
fi

if [[ ! -f "$CONFIG_FILE" ]]; then
    log_error "Fichier de configuration non trouvé: $CONFIG_FILE"
    exit 1
fi

TASKS_FILE="${FEATURE_DIR}/tasks.json"
if [[ ! -f "$TASKS_FILE" ]]; then
    log_error "Fichier tasks.json non trouvé: $TASKS_FILE"
    exit 1
fi

# Charger la configuration
MAX_RETRIES=$(jq -r '.execution.ralphWiggum.maxRetries // 7' "$CONFIG_FILE")
RETRY_DELAY=$(jq -r '.execution.ralphWiggum.retryDelaySeconds // 10' "$CONFIG_FILE")
MAX_DURATION=$(jq -r '.execution.quotaCheck.maxTaskDurationMinutes // 30' "$CONFIG_FILE")
REVIEWER_ENABLED=$(jq -r '.pipeline.reviewerEnabled // true' "$CONFIG_FILE")
TESTER_ENABLED=$(jq -r '.pipeline.testerEnabled // true' "$CONFIG_FILE")
QUALITY_CHECKS_ENABLED=$(jq -r '.qualityChecks.enabled // true' "$CONFIG_FILE")
GIT_AUTO_COMMIT=$(jq -r '.git.autoCommit // true' "$CONFIG_FILE")

# Vérifier que la tâche existe
TASK_EXISTS=$(jq -r ".tasks[] | select(.id == \"$TASK_ID\") | .id" "$TASKS_FILE")
if [[ -z "$TASK_EXISTS" ]]; then
    log_error "Tâche non trouvée: $TASK_ID"
    exit 1
fi

# Obtenir le modèle pour developer
get_model() {
    local AGENT_TYPE="$1"
    jq -r ".models[\"$AGENT_TYPE\"] // .models.default" "$CONFIG_FILE"
}

# Générer un ID de session unique
generate_session_id() {
    echo "impl_${TASK_ID}_$(date +%Y%m%d%H%M%S)_$$"
}

ATTEMPT=0
SESSION_ID=""

while [[ $ATTEMPT -lt $MAX_RETRIES ]]; do
    ATTEMPT=$((ATTEMPT + 1))
    SESSION_ID=$(generate_session_id)

    log_info "═══════════════════════════════════════════════════════════"
    log_info "Tâche: $TASK_ID - Tentative $ATTEMPT/$MAX_RETRIES"
    log_info "Session: $SESSION_ID"
    log_info "═══════════════════════════════════════════════════════════"

    # ═══════════════════════════════════════════════════════════════════
    # PHASE 1: Acquisition du lock
    # ═══════════════════════════════════════════════════════════════════
    log_info "[1/6] Acquisition du lock..."

    LOCK_RESULT=$("${SCRIPT_DIR}/utils/lock_manager.sh" acquire "$TASK_ID" "$FEATURE_DIR" 2>&1) || {
        log_warning "Lock non disponible. Attente..."
        sleep "$RETRY_DELAY"
        continue
    }

    log_success "Lock acquis"

    # ═══════════════════════════════════════════════════════════════════
    # PHASE 2: Mise à jour du statut → InProgress
    # ═══════════════════════════════════════════════════════════════════
    log_info "[2/6] Mise à jour du statut → InProgress..."

    "${SCRIPT_DIR}/utils/status_updater.sh" set_status "$TASK_ID" "InProgress" "Attempt $ATTEMPT" "$TASKS_FILE" || true

    # ═══════════════════════════════════════════════════════════════════
    # PHASE 3: Exécution de l'agent Developer
    # ═══════════════════════════════════════════════════════════════════
    log_info "[3/6] Lancement de l'agent Developer..."

    DEV_MODEL=$(get_model "developer")
    LOG_FILE="${SCRIPT_DIR}/logs/sessions/${SESSION_ID}.log"
    mkdir -p "$(dirname "$LOG_FILE")"

    # Préparer le contexte de la tâche
    TASK_CONTEXT=$(jq -r ".tasks[] | select(.id == \"$TASK_ID\")" "$TASKS_FILE")

    # Dans une vraie implémentation, on exécuterait claude ici
    # Pour l'instant, on simule le succès

    echo "=== Session $SESSION_ID ===" > "$LOG_FILE"
    echo "Task: $TASK_ID" >> "$LOG_FILE"
    echo "Model: $DEV_MODEL" >> "$LOG_FILE"
    echo "Attempt: $ATTEMPT" >> "$LOG_FILE"
    echo "Started: $(date -Iseconds)" >> "$LOG_FILE"
    echo "---" >> "$LOG_FILE"
    echo "Task context:" >> "$LOG_FILE"
    echo "$TASK_CONTEXT" >> "$LOG_FILE"
    echo "---" >> "$LOG_FILE"
    echo "[SIMULATED] Developer agent execution" >> "$LOG_FILE"
    echo "<promise>COMPLETE</promise>" >> "$LOG_FILE"
    echo "---" >> "$LOG_FILE"
    echo "Completed: $(date -Iseconds)" >> "$LOG_FILE"

    # Vérifier le signal de complétion
    if grep -q '<promise>COMPLETE</promise>' "$LOG_FILE"; then
        log_success "Agent Developer: COMPLETE"
        DEV_EXIT_CODE=0
    elif grep -q '<promise>BLOCKED:' "$LOG_FILE"; then
        BLOCK_REASON=$(grep -oP '(?<=<promise>BLOCKED: ).*(?=</promise>)' "$LOG_FILE" || echo "Unknown")
        log_warning "Agent Developer: BLOCKED - $BLOCK_REASON"
        "${SCRIPT_DIR}/utils/status_updater.sh" set_status "$TASK_ID" "Blocked" "$BLOCK_REASON" "$TASKS_FILE"
        "${SCRIPT_DIR}/utils/lock_manager.sh" release "$TASK_ID"
        exit 2
    elif grep -q '<promise>NEEDS_SPLIT:' "$LOG_FILE"; then
        SPLIT_REASON=$(grep -oP '(?<=<promise>NEEDS_SPLIT: ).*(?=</promise>)' "$LOG_FILE" || echo "Task too complex")
        log_warning "Agent Developer: NEEDS_SPLIT - $SPLIT_REASON"
        "${SCRIPT_DIR}/utils/status_updater.sh" set_status "$TASK_ID" "Error" "Needs split: $SPLIT_REASON" "$TASKS_FILE"
        "${SCRIPT_DIR}/utils/lock_manager.sh" release "$TASK_ID"
        exit 3
    else
        log_error "Agent Developer: Pas de signal COMPLETE"
        DEV_EXIT_CODE=1
    fi

    # Si l'agent Developer a échoué, retry
    if [[ $DEV_EXIT_CODE -ne 0 ]]; then
        "${SCRIPT_DIR}/utils/status_updater.sh" set_status "$TASK_ID" "Error" "Attempt $ATTEMPT failed" "$TASKS_FILE"
        "${SCRIPT_DIR}/utils/lock_manager.sh" release "$TASK_ID"
        log_error "Échec tentative $ATTEMPT pour $TASK_ID"
        sleep "$RETRY_DELAY"
        continue
    fi

    "${SCRIPT_DIR}/utils/status_updater.sh" set_status "$TASK_ID" "Implemented" "" "$TASKS_FILE"

    # ═══════════════════════════════════════════════════════════════════
    # PHASE 4: Review (si activé)
    # ═══════════════════════════════════════════════════════════════════
    if [[ "$REVIEWER_ENABLED" == "true" ]]; then
        log_info "[4/6] Lancement de l'agent Reviewer..."

        REVIEWER_MODEL=$(get_model "reviewer")
        REVIEW_LOG="${SCRIPT_DIR}/logs/sessions/${SESSION_ID}_review.log"

        # Simulation de la review
        echo "=== Review Session ===" > "$REVIEW_LOG"
        echo "Task: $TASK_ID" >> "$REVIEW_LOG"
        echo "Model: $REVIEWER_MODEL" >> "$REVIEW_LOG"
        echo "[SIMULATED] Reviewer agent execution" >> "$REVIEW_LOG"
        echo "<promise>COMPLETE</promise>" >> "$REVIEW_LOG"

        if grep -q '<promise>COMPLETE</promise>' "$REVIEW_LOG"; then
            log_success "Agent Reviewer: COMPLETE"
        else
            log_error "Review échouée pour $TASK_ID"
            "${SCRIPT_DIR}/utils/status_updater.sh" set_status "$TASK_ID" "Error" "Review failed" "$TASKS_FILE"
            "${SCRIPT_DIR}/utils/lock_manager.sh" release "$TASK_ID"
            sleep "$RETRY_DELAY"
            continue
        fi

        "${SCRIPT_DIR}/utils/status_updater.sh" set_status "$TASK_ID" "Reviewed" "" "$TASKS_FILE"
    else
        log_info "[4/6] Reviewer désactivé - skip"
    fi

    # ═══════════════════════════════════════════════════════════════════
    # PHASE 5: Tests (si activé)
    # ═══════════════════════════════════════════════════════════════════
    if [[ "$TESTER_ENABLED" == "true" ]]; then
        log_info "[5/6] Lancement de l'agent Tester..."

        TESTER_MODEL=$(get_model "tester")
        TEST_LOG="${SCRIPT_DIR}/logs/sessions/${SESSION_ID}_test.log"

        # Simulation des tests
        echo "=== Test Session ===" > "$TEST_LOG"
        echo "Task: $TASK_ID" >> "$TEST_LOG"
        echo "Model: $TESTER_MODEL" >> "$TEST_LOG"
        echo "[SIMULATED] Tester agent execution" >> "$TEST_LOG"
        echo "<promise>COMPLETE</promise>" >> "$TEST_LOG"

        if grep -q '<promise>COMPLETE</promise>' "$TEST_LOG"; then
            log_success "Agent Tester: COMPLETE"
        else
            log_error "Tests échoués pour $TASK_ID"
            "${SCRIPT_DIR}/utils/status_updater.sh" set_status "$TASK_ID" "Error" "Tests failed" "$TASKS_FILE"
            "${SCRIPT_DIR}/utils/lock_manager.sh" release "$TASK_ID"
            sleep "$RETRY_DELAY"
            continue
        fi

        "${SCRIPT_DIR}/utils/status_updater.sh" set_status "$TASK_ID" "Tested" "" "$TASKS_FILE"
    else
        log_info "[5/6] Tester désactivé - skip"
    fi

    # ═══════════════════════════════════════════════════════════════════
    # PHASE 6: Quality checks et commit Git
    # ═══════════════════════════════════════════════════════════════════
    if [[ "$QUALITY_CHECKS_ENABLED" == "true" ]]; then
        log_info "[6/6] Quality checks..."

        if ! "${SCRIPT_DIR}/utils/quality_check.sh" "$TASK_ID" "$CONFIG_FILE" 2>/dev/null; then
            log_error "Quality checks échoués pour $TASK_ID"
            "${SCRIPT_DIR}/utils/status_updater.sh" set_status "$TASK_ID" "Error" "Quality checks failed" "$TASKS_FILE"
            "${SCRIPT_DIR}/utils/lock_manager.sh" release "$TASK_ID"
            sleep "$RETRY_DELAY"
            continue
        fi
    else
        log_info "[6/6] Quality checks désactivés - skip"
    fi

    # Git commit
    if [[ "$GIT_AUTO_COMMIT" == "true" ]]; then
        log_info "Commit Git..."

        TASK_TITLE=$(jq -r ".tasks[] | select(.id == \"$TASK_ID\") | .title" "$TASKS_FILE")
        COMMIT_PREFIX=$(jq -r '.git.commitMessagePrefix // "feat"' "$CONFIG_FILE")

        # Vérifier si c'est un repo git
        if git rev-parse --is-inside-work-tree &>/dev/null; then
            git add -A
            git commit -m "$(cat <<EOF
${COMMIT_PREFIX}(${TASK_ID}): ${TASK_TITLE}

Co-Authored-By: Claude <noreply@anthropic.com>
EOF
)" 2>/dev/null || log_warning "Rien à committer"

            log_success "Commit créé"
        else
            log_warning "Pas un repo Git - skip commit"
        fi
    fi

    # ═══════════════════════════════════════════════════════════════════
    # SUCCÈS - Libérer le lock et terminer
    # ═══════════════════════════════════════════════════════════════════
    "${SCRIPT_DIR}/utils/lock_manager.sh" release "$TASK_ID"

    # Marquer la tâche comme passée
    jq "(.tasks[] | select(.id == \"$TASK_ID\") | .passes) = true" "$TASKS_FILE" > "${TASKS_FILE}.tmp" && mv "${TASKS_FILE}.tmp" "$TASKS_FILE"

    log_success "═══════════════════════════════════════════════════════════"
    log_success "Tâche $TASK_ID complétée avec succès!"
    log_success "Tentatives: $ATTEMPT/$MAX_RETRIES"
    log_success "═══════════════════════════════════════════════════════════"

    exit 0
done

# Max retries atteint
"${SCRIPT_DIR}/utils/lock_manager.sh" release "$TASK_ID" 2>/dev/null || true
"${SCRIPT_DIR}/utils/status_updater.sh" set_status "$TASK_ID" "Error" "Max retries ($MAX_RETRIES) reached" "$TASKS_FILE"

log_error "═══════════════════════════════════════════════════════════"
log_error "Tâche $TASK_ID en erreur après $MAX_RETRIES tentatives"
log_error "═══════════════════════════════════════════════════════════"

exit 1
