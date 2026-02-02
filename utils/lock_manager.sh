#!/bin/bash
# lock_manager.sh - Gestion des locks pour le framework multi-sessions
#
# Usage:
#   ./lock_manager.sh acquire <task_id> <feature_dir>
#   ./lock_manager.sh acquire --type <type> --target <path> --task <task_id>
#   ./lock_manager.sh release <task_id>
#   ./lock_manager.sh check <file_path>
#   ./lock_manager.sh cleanup

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LOCKS_DIR="${SCRIPT_DIR}/locks"
CONFIG_FILE="${SCRIPT_DIR}/config.json"

# Couleurs
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Charger la configuration
EXPIRATION_MINUTES=$(jq -r '.locks.expirationMinutes // 60' "$CONFIG_FILE" 2>/dev/null || echo "60")

# Créer les répertoires de locks si nécessaire
mkdir -p "${LOCKS_DIR}/files" "${LOCKS_DIR}/directories" "${LOCKS_DIR}/patterns"

# Fonction: Encoder un chemin pour le nom de fichier
encode_path() {
    echo "$1" | sed 's/\//_/g' | sed 's/\./_/g' | sed 's/\*/_star_/g'
}

# Fonction: Calculer l'expiration
get_expiration() {
    date -d "+${EXPIRATION_MINUTES} minutes" -Iseconds 2>/dev/null || \
    date -v+${EXPIRATION_MINUTES}M -Iseconds 2>/dev/null || \
    date -Iseconds
}

# Fonction: Vérifier si un lock a expiré
is_expired() {
    local LOCK_FILE="$1"

    if [[ ! -f "$LOCK_FILE" ]]; then
        return 0  # Pas de lock = considéré comme expiré
    fi

    local EXPIRES_AT=$(jq -r '.expires_at' "$LOCK_FILE" 2>/dev/null)

    if [[ -z "$EXPIRES_AT" || "$EXPIRES_AT" == "null" ]]; then
        return 0
    fi

    local EXPIRES_EPOCH=$(date -d "$EXPIRES_AT" +%s 2>/dev/null || date -jf "%Y-%m-%dT%H:%M:%S" "$EXPIRES_AT" +%s 2>/dev/null || echo "0")
    local NOW_EPOCH=$(date +%s)

    if [[ $NOW_EPOCH -gt $EXPIRES_EPOCH ]]; then
        return 0  # Expiré
    else
        return 1  # Pas expiré
    fi
}

# Fonction: Acquérir un lock
acquire_lock() {
    local TASK_ID=""
    local LOCK_TYPE="file"
    local TARGET=""
    local FEATURE_DIR=""

    # Parser les arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            --type)
                LOCK_TYPE="$2"
                shift 2
                ;;
            --target)
                TARGET="$2"
                shift 2
                ;;
            --task)
                TASK_ID="$2"
                shift 2
                ;;
            *)
                if [[ -z "$TASK_ID" ]]; then
                    TASK_ID="$1"
                elif [[ -z "$FEATURE_DIR" ]]; then
                    FEATURE_DIR="$1"
                fi
                shift
                ;;
        esac
    done

    # Si pas de target spécifié, utiliser la tâche pour déterminer
    if [[ -z "$TARGET" && -n "$FEATURE_DIR" ]]; then
        local TASKS_FILE="${FEATURE_DIR}/tasks.json"
        if [[ -f "$TASKS_FILE" ]]; then
            TARGET=$(jq -r ".tasks[] | select(.id == \"$TASK_ID\") | .outputs.lockTarget // .outputs.files[0]" "$TASKS_FILE" 2>/dev/null)
            LOCK_TYPE=$(jq -r ".tasks[] | select(.id == \"$TASK_ID\") | .outputs.lockType // \"file\"" "$TASKS_FILE" 2>/dev/null)
        fi
    fi

    if [[ -z "$TASK_ID" || -z "$TARGET" ]]; then
        echo -e "${RED}[ERROR]${NC} Usage: lock_manager.sh acquire <task_id> <feature_dir>" >&2
        echo -e "${RED}[ERROR]${NC}    ou: lock_manager.sh acquire --type <type> --target <path> --task <task_id>" >&2
        return 1
    fi

    # Déterminer le chemin du fichier lock
    local ENCODED_TARGET=$(encode_path "$TARGET")
    local LOCK_FILE=""

    case $LOCK_TYPE in
        file)
            LOCK_FILE="${LOCKS_DIR}/files/${ENCODED_TARGET}.lock"
            ;;
        directory)
            LOCK_FILE="${LOCKS_DIR}/directories/${ENCODED_TARGET}.lock"
            ;;
        pattern)
            LOCK_FILE="${LOCKS_DIR}/patterns/${ENCODED_TARGET}.lock"
            ;;
        *)
            echo -e "${RED}[ERROR]${NC} Type de lock invalide: $LOCK_TYPE" >&2
            return 1
            ;;
    esac

    # Vérifier s'il existe un lock non expiré
    if [[ -f "$LOCK_FILE" ]]; then
        if is_expired "$LOCK_FILE"; then
            echo -e "${YELLOW}[WARNING]${NC} Lock expiré trouvé, nettoyage..."
            rm -f "$LOCK_FILE"
        else
            local EXISTING_TASK=$(jq -r '.task_id' "$LOCK_FILE")
            local EXISTING_SESSION=$(jq -r '.session_id' "$LOCK_FILE")
            echo -e "${RED}[ERROR]${NC} Lock déjà détenu par $EXISTING_TASK (session: $EXISTING_SESSION)" >&2
            return 1
        fi
    fi

    # Vérifier les conflits avec les locks de type directory
    if [[ "$LOCK_TYPE" == "file" ]]; then
        local PARENT_DIR=$(dirname "$TARGET")
        local ENCODED_PARENT=$(encode_path "$PARENT_DIR")
        local PARENT_LOCK="${LOCKS_DIR}/directories/${ENCODED_PARENT}.lock"

        if [[ -f "$PARENT_LOCK" ]] && ! is_expired "$PARENT_LOCK"; then
            local EXISTING_TASK=$(jq -r '.task_id' "$PARENT_LOCK")
            echo -e "${RED}[ERROR]${NC} Répertoire parent locké par $EXISTING_TASK" >&2
            return 1
        fi
    fi

    # Créer le lock
    local SESSION_ID="session_${TASK_ID}_$(date +%Y%m%d%H%M%S)_$$"
    local NOW=$(date -Iseconds)
    local EXPIRES=$(get_expiration)

    cat > "$LOCK_FILE" << EOF
{
  "session_id": "$SESSION_ID",
  "locked_at": "$NOW",
  "expires_at": "$EXPIRES",
  "task_id": "$TASK_ID",
  "lock_type": "$LOCK_TYPE",
  "target": "$TARGET",
  "scope": ["$TARGET"]
}
EOF

    echo -e "${GREEN}[OK]${NC} Lock acquis: $LOCK_TYPE sur $TARGET (expire: $EXPIRES)"
    return 0
}

# Fonction: Libérer un lock
release_lock() {
    local TASK_ID="$1"

    if [[ -z "$TASK_ID" ]]; then
        echo -e "${RED}[ERROR]${NC} Usage: lock_manager.sh release <task_id>" >&2
        return 1
    fi

    local RELEASED=0

    # Chercher et supprimer tous les locks de cette tâche
    for lock_dir in files directories patterns; do
        for lock_file in "${LOCKS_DIR}/${lock_dir}"/*.lock; do
            if [[ -f "$lock_file" ]]; then
                local FILE_TASK_ID=$(jq -r '.task_id' "$lock_file" 2>/dev/null)

                if [[ "$FILE_TASK_ID" == "$TASK_ID" ]]; then
                    rm -f "$lock_file"
                    RELEASED=$((RELEASED + 1))
                    echo -e "${GREEN}[OK]${NC} Lock libéré: $(basename "$lock_file")"
                fi
            fi
        done
    done

    if [[ $RELEASED -eq 0 ]]; then
        echo -e "${YELLOW}[WARNING]${NC} Aucun lock trouvé pour $TASK_ID"
    else
        echo -e "${GREEN}[OK]${NC} $RELEASED lock(s) libéré(s) pour $TASK_ID"
    fi

    return 0
}

# Fonction: Vérifier un lock
check_lock() {
    local FILE_PATH="$1"

    if [[ -z "$FILE_PATH" ]]; then
        echo -e "${RED}[ERROR]${NC} Usage: lock_manager.sh check <file_path>" >&2
        return 1
    fi

    local ENCODED_PATH=$(encode_path "$FILE_PATH")

    # Vérifier lock fichier
    local FILE_LOCK="${LOCKS_DIR}/files/${ENCODED_PATH}.lock"
    if [[ -f "$FILE_LOCK" ]] && ! is_expired "$FILE_LOCK"; then
        local TASK_ID=$(jq -r '.task_id' "$FILE_LOCK")
        local SESSION=$(jq -r '.session_id' "$FILE_LOCK")
        local EXPIRES=$(jq -r '.expires_at' "$FILE_LOCK")
        echo "LOCKED by $TASK_ID (session: $SESSION, expires: $EXPIRES)"
        return 1
    fi

    # Vérifier lock répertoire parent
    local PARENT_DIR=$(dirname "$FILE_PATH")
    local ENCODED_PARENT=$(encode_path "$PARENT_DIR")
    local DIR_LOCK="${LOCKS_DIR}/directories/${ENCODED_PARENT}.lock"
    if [[ -f "$DIR_LOCK" ]] && ! is_expired "$DIR_LOCK"; then
        local TASK_ID=$(jq -r '.task_id' "$DIR_LOCK")
        echo "LOCKED (directory) by $TASK_ID"
        return 1
    fi

    echo "AVAILABLE"
    return 0
}

# Fonction: Nettoyer les locks expirés
cleanup_locks() {
    local CLEANED=0

    for lock_dir in files directories patterns; do
        for lock_file in "${LOCKS_DIR}/${lock_dir}"/*.lock; do
            if [[ -f "$lock_file" ]]; then
                if is_expired "$lock_file"; then
                    rm -f "$lock_file"
                    CLEANED=$((CLEANED + 1))
                    echo -e "${GREEN}[OK]${NC} Nettoyé: $(basename "$lock_file")"
                fi
            fi
        done
    done

    echo -e "${GREEN}[OK]${NC} $CLEANED lock(s) expiré(s) nettoyé(s)"
    return 0
}

# Fonction: Lister tous les locks actifs
list_locks() {
    echo "═══════════════════════════════════════════════════════════"
    echo "                      LOCKS ACTIFS"
    echo "═══════════════════════════════════════════════════════════"

    local COUNT=0

    for lock_dir in files directories patterns; do
        for lock_file in "${LOCKS_DIR}/${lock_dir}"/*.lock; do
            if [[ -f "$lock_file" ]]; then
                if ! is_expired "$lock_file"; then
                    COUNT=$((COUNT + 1))
                    local TASK_ID=$(jq -r '.task_id' "$lock_file")
                    local TARGET=$(jq -r '.target' "$lock_file")
                    local TYPE=$(jq -r '.lock_type' "$lock_file")
                    local EXPIRES=$(jq -r '.expires_at' "$lock_file")

                    echo "[$TYPE] $TARGET"
                    echo "  Task: $TASK_ID"
                    echo "  Expires: $EXPIRES"
                    echo ""
                fi
            fi
        done
    done

    if [[ $COUNT -eq 0 ]]; then
        echo "Aucun lock actif."
    else
        echo "───────────────────────────────────────────────────────────"
        echo "Total: $COUNT lock(s) actif(s)"
    fi
}

# Point d'entrée principal
case "${1:-}" in
    acquire)
        shift
        acquire_lock "$@"
        ;;
    release)
        shift
        release_lock "$@"
        ;;
    check)
        shift
        check_lock "$@"
        ;;
    cleanup)
        cleanup_locks
        ;;
    list)
        list_locks
        ;;
    *)
        echo "Usage: $0 <command> [arguments]"
        echo ""
        echo "Commands:"
        echo "  acquire <task_id> <feature_dir>    Acquérir un lock pour une tâche"
        echo "  acquire --type <type> --target <path> --task <id>"
        echo "  release <task_id>                   Libérer tous les locks d'une tâche"
        echo "  check <file_path>                   Vérifier si un fichier est locké"
        echo "  cleanup                             Nettoyer les locks expirés"
        echo "  list                                Lister tous les locks actifs"
        echo ""
        echo "Lock types: file, directory, pattern"
        exit 1
        ;;
esac
