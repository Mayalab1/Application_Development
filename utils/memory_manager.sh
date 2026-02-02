#!/bin/bash
# memory_manager.sh - Gestion de la mémoire partagée hiérarchique
#
# Usage:
#   ./memory_manager.sh search <query>
#   ./memory_manager.sh search --category <category> <query>
#   ./memory_manager.sh read <entry_id> [--summary|--headers|--full|--section <name>]
#   ./memory_manager.sh list [--category <category>]
#   ./memory_manager.sh create --category <cat> --title <title> --tags <tags> --author <author> [--task <task_id>] --content <content>
#   ./memory_manager.sh update --id <entry_id> --author <author> --reason <reason> [--include-previous] --content <content>
#   ./memory_manager.sh create-category --path <path> --description <desc> [--parent <parent>] [--related <categories>]
#   ./memory_manager.sh move --id <entry_id> --to-category <category>

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MEMORY_DIR="${SCRIPT_DIR}/memory"
INDEX_FILE="${MEMORY_DIR}/_index.json"
CONFIG_FILE="${SCRIPT_DIR}/config.json"

# Couleurs
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# Initialiser le répertoire mémoire si nécessaire
init_memory() {
    mkdir -p "${MEMORY_DIR}/_inbox"

    if [[ ! -f "$INDEX_FILE" ]]; then
        cat > "$INDEX_FILE" << 'EOF'
{
  "version": 1,
  "last_updated": null,
  "categories": [
    {
      "path": "_inbox",
      "description": "Zone de staging pour entrées à classifier",
      "entry_count": 0,
      "subcategories": []
    },
    {
      "path": "domain",
      "description": "Connaissances du domaine métier",
      "entry_count": 0,
      "subcategories": ["rules", "workflows"]
    },
    {
      "path": "architecture",
      "description": "Patterns et décisions d'architecture",
      "entry_count": 0,
      "subcategories": []
    },
    {
      "path": "ui_patterns",
      "description": "Patterns d'interface utilisateur",
      "entry_count": 0,
      "subcategories": []
    },
    {
      "path": "configuration",
      "description": "Configuration et paramétrage",
      "entry_count": 0,
      "subcategories": []
    }
  ],
  "pending_classification": 0,
  "category_suggestions": []
}
EOF
    fi

    # Créer les sous-répertoires
    for cat in domain/{rules,workflows} architecture ui_patterns configuration _inbox; do
        mkdir -p "${MEMORY_DIR}/${cat}"
    done
}

# Fonction: Générer un ID d'entrée unique
generate_entry_id() {
    local CATEGORY="$1"
    local BASE_NAME=$(echo "$CATEGORY" | tr '/' '_')
    local COUNT=$(find "${MEMORY_DIR}/${CATEGORY}" -name "*.md" 2>/dev/null | wc -l)
    printf "mem_%s_%03d" "$BASE_NAME" $((COUNT + 1))
}

# Fonction: Rechercher dans la mémoire
search_memory() {
    local QUERY=""
    local CATEGORY=""
    local MAX_RESULTS=5

    while [[ $# -gt 0 ]]; do
        case $1 in
            --category)
                CATEGORY="$2"
                shift 2
                ;;
            --max)
                MAX_RESULTS="$2"
                shift 2
                ;;
            *)
                QUERY="$1"
                shift
                ;;
        esac
    done

    if [[ -z "$QUERY" ]]; then
        echo -e "${RED}[ERROR]${NC} Usage: memory_manager.sh search <query>" >&2
        return 1
    fi

    echo -e "${CYAN}═══════════════════════════════════════════════════════════════${NC}"
    echo -e "${CYAN}            RECHERCHE MÉMOIRE: \"$QUERY\"                        ${NC}"
    echo -e "${CYAN}═══════════════════════════════════════════════════════════════${NC}"
    echo ""

    local SEARCH_PATH="$MEMORY_DIR"
    if [[ -n "$CATEGORY" ]]; then
        SEARCH_PATH="${MEMORY_DIR}/${CATEGORY}"
    fi

    local RESULTS=0

    # Rechercher dans les fichiers .md
    while IFS= read -r file; do
        if [[ -f "$file" && $RESULTS -lt $MAX_RESULTS ]]; then
            # Extraire les métadonnées
            local ID=$(grep -m1 '^id:' "$file" 2>/dev/null | sed 's/id: *"\(.*\)"/\1/' || echo "")
            local TITLE=$(grep -m1 '^# ' "$file" 2>/dev/null | sed 's/^# //' || basename "$file" .md)
            local CATEGORY_PATH=$(dirname "$file" | sed "s|${MEMORY_DIR}/||")
            local TAGS=$(grep -m1 '^tags:' "$file" 2>/dev/null | sed 's/tags: *\[\(.*\)\]/\1/' || echo "")

            echo -e "${GREEN}📄 $TITLE${NC}"
            echo "   ID: $ID"
            echo "   Category: $CATEGORY_PATH"
            echo "   Tags: $TAGS"

            # Afficher un extrait du contenu correspondant
            local CONTEXT=$(grep -i -m1 -C1 "$QUERY" "$file" 2>/dev/null | head -3 || echo "")
            if [[ -n "$CONTEXT" ]]; then
                echo "   Preview: $(echo "$CONTEXT" | head -1 | cut -c1-60)..."
            fi
            echo ""

            RESULTS=$((RESULTS + 1))
        fi
    done < <(grep -l -r -i "$QUERY" "$SEARCH_PATH" --include="*.md" 2>/dev/null || true)

    if [[ $RESULTS -eq 0 ]]; then
        echo "Aucun résultat trouvé pour \"$QUERY\"."
    else
        echo -e "${BLUE}[INFO]${NC} $RESULTS résultat(s) trouvé(s)"
    fi

    return 0
}

# Fonction: Lire une entrée mémoire
read_entry() {
    local ENTRY_ID=""
    local MODE="full"
    local SECTION=""

    while [[ $# -gt 0 ]]; do
        case $1 in
            --summary)
                MODE="summary"
                shift
                ;;
            --headers)
                MODE="headers"
                shift
                ;;
            --full)
                MODE="full"
                shift
                ;;
            --section)
                MODE="section"
                SECTION="$2"
                shift 2
                ;;
            --version)
                VERSION="$2"
                shift 2
                ;;
            *)
                ENTRY_ID="$1"
                shift
                ;;
        esac
    done

    if [[ -z "$ENTRY_ID" ]]; then
        echo -e "${RED}[ERROR]${NC} Usage: memory_manager.sh read <entry_id> [--summary|--headers|--full|--section <name>]" >&2
        return 1
    fi

    # Trouver le fichier
    local FILE=$(find "$MEMORY_DIR" -name "*.md" -exec grep -l "^id: *\"$ENTRY_ID\"" {} \; 2>/dev/null | head -1)

    if [[ -z "$FILE" ]]; then
        # Essayer de chercher par nom de fichier
        FILE=$(find "$MEMORY_DIR" -name "${ENTRY_ID}.md" 2>/dev/null | head -1)
    fi

    if [[ -z "$FILE" || ! -f "$FILE" ]]; then
        echo -e "${RED}[ERROR]${NC} Entrée non trouvée: $ENTRY_ID" >&2
        return 1
    fi

    case $MODE in
        summary)
            # Afficher les métadonnées et le premier paragraphe
            echo -e "${CYAN}═══ SUMMARY: $ENTRY_ID ═══${NC}"
            head -20 "$FILE" | grep -E '^(id:|version:|updated:|author:|category:|tags:|#)' || true
            echo ""
            # Premier paragraphe après les métadonnées
            sed -n '/^---$/,/^---$/!p' "$FILE" | grep -v '^$' | head -5
            ;;
        headers)
            # Afficher uniquement les titres
            echo -e "${CYAN}═══ HEADERS: $ENTRY_ID ═══${NC}"
            grep -E '^#{1,3} ' "$FILE" || echo "Pas de sections trouvées"
            ;;
        section)
            # Afficher une section spécifique
            echo -e "${CYAN}═══ SECTION: $SECTION ═══${NC}"
            awk "/^## $SECTION/,/^## [^$SECTION]/" "$FILE" | head -50
            ;;
        full|*)
            # Afficher tout le contenu
            cat "$FILE"
            ;;
    esac

    return 0
}

# Fonction: Lister les entrées
list_entries() {
    local CATEGORY=""

    while [[ $# -gt 0 ]]; do
        case $1 in
            --category)
                CATEGORY="$2"
                shift 2
                ;;
            *)
                shift
                ;;
        esac
    done

    echo -e "${CYAN}═══════════════════════════════════════════════════════════════${NC}"
    echo -e "${CYAN}                    ENTRÉES MÉMOIRE                             ${NC}"
    echo -e "${CYAN}═══════════════════════════════════════════════════════════════${NC}"
    echo ""

    local SEARCH_PATH="$MEMORY_DIR"
    if [[ -n "$CATEGORY" ]]; then
        SEARCH_PATH="${MEMORY_DIR}/${CATEGORY}"
        echo -e "${BLUE}[INFO]${NC} Catégorie: $CATEGORY"
        echo ""
    fi

    local COUNT=0

    for file in $(find "$SEARCH_PATH" -name "*.md" -type f 2>/dev/null | sort); do
        if [[ -f "$file" ]]; then
            local ID=$(grep -m1 '^id:' "$file" 2>/dev/null | sed 's/id: *"\(.*\)"/\1/' || basename "$file" .md)
            local TITLE=$(grep -m1 '^# ' "$file" 2>/dev/null | sed 's/^# //' || basename "$file" .md)
            local VERSION=$(grep -m1 '^version:' "$file" 2>/dev/null | sed 's/version: *//' || echo "1")
            local CAT=$(dirname "$file" | sed "s|${MEMORY_DIR}/||")

            echo "📄 $ID (v$VERSION)"
            echo "   Title: $TITLE"
            echo "   Category: $CAT"
            echo ""

            COUNT=$((COUNT + 1))
        fi
    done

    if [[ $COUNT -eq 0 ]]; then
        echo "Aucune entrée trouvée."
    else
        echo -e "${BLUE}[INFO]${NC} Total: $COUNT entrée(s)"
    fi

    return 0
}

# Fonction: Créer une nouvelle entrée
create_entry() {
    local CATEGORY=""
    local TITLE=""
    local TAGS=""
    local AUTHOR=""
    local TASK_ID=""
    local CONTENT=""
    local CONTENT_FILE=""
    local NEEDS_CLASSIFICATION=false

    while [[ $# -gt 0 ]]; do
        case $1 in
            --category)
                CATEGORY="$2"
                shift 2
                ;;
            --title)
                TITLE="$2"
                shift 2
                ;;
            --tags)
                TAGS="$2"
                shift 2
                ;;
            --author)
                AUTHOR="$2"
                shift 2
                ;;
            --task)
                TASK_ID="$2"
                shift 2
                ;;
            --content)
                CONTENT="$2"
                shift 2
                ;;
            --file)
                CONTENT_FILE="$2"
                shift 2
                ;;
            --needs-classification)
                NEEDS_CLASSIFICATION=true
                shift
                ;;
            *)
                shift
                ;;
        esac
    done

    # Validation
    if [[ -z "$CATEGORY" || -z "$TITLE" || -z "$AUTHOR" ]]; then
        echo -e "${RED}[ERROR]${NC} Usage: memory_manager.sh create --category <cat> --title <title> --author <author> [--tags <tags>] [--task <task_id>] --content <content>" >&2
        return 1
    fi

    # Créer le répertoire de catégorie si nécessaire
    mkdir -p "${MEMORY_DIR}/${CATEGORY}"

    # Générer l'ID
    local ENTRY_ID=$(generate_entry_id "$CATEGORY")

    # Préparer le contenu
    if [[ -n "$CONTENT_FILE" && -f "$CONTENT_FILE" ]]; then
        CONTENT=$(cat "$CONTENT_FILE")
    fi

    local NOW=$(date -Iseconds)
    local FILENAME="${MEMORY_DIR}/${CATEGORY}/$(echo "$TITLE" | tr ' ' '_' | tr '[:upper:]' '[:lower:]').md"

    # Créer le fichier
    cat > "$FILENAME" << EOF
---
id: "$ENTRY_ID"
version: 1
created: "$NOW"
updated: "$NOW"
author: "$AUTHOR"
task_origin: "$TASK_ID"
category: "$CATEGORY"
tags: [$TAGS]
audit_trail:
  - version: 1
    date: "$NOW"
    author: "$AUTHOR"
    reason: "Initial creation"
---

# $TITLE

$CONTENT
EOF

    # Mettre à jour l'index
    local TEMP_FILE=$(mktemp)
    jq --arg cat "$CATEGORY" \
       --arg now "$NOW" \
       '
       .last_updated = $now |
       (.categories[] | select(.path == $cat) | .entry_count) += 1
       ' "$INDEX_FILE" > "$TEMP_FILE" 2>/dev/null || cp "$INDEX_FILE" "$TEMP_FILE"
    mv "$TEMP_FILE" "$INDEX_FILE"

    echo -e "${GREEN}[OK]${NC} Entrée créée: $ENTRY_ID"
    echo -e "${BLUE}[INFO]${NC} Fichier: $FILENAME"

    return 0
}

# Fonction: Mettre à jour une entrée
update_entry() {
    local ENTRY_ID=""
    local AUTHOR=""
    local REASON=""
    local INCLUDE_PREVIOUS=false
    local CONTENT=""
    local CONTENT_FILE=""

    while [[ $# -gt 0 ]]; do
        case $1 in
            --id)
                ENTRY_ID="$2"
                shift 2
                ;;
            --author)
                AUTHOR="$2"
                shift 2
                ;;
            --reason)
                REASON="$2"
                shift 2
                ;;
            --include-previous)
                INCLUDE_PREVIOUS=true
                shift
                ;;
            --content)
                CONTENT="$2"
                shift 2
                ;;
            --file)
                CONTENT_FILE="$2"
                shift 2
                ;;
            *)
                shift
                ;;
        esac
    done

    # Validation
    if [[ -z "$ENTRY_ID" || -z "$AUTHOR" || -z "$REASON" ]]; then
        echo -e "${RED}[ERROR]${NC} Usage: memory_manager.sh update --id <entry_id> --author <author> --reason <reason> [--include-previous] --content <content>" >&2
        return 1
    fi

    # Trouver le fichier
    local FILE=$(find "$MEMORY_DIR" -name "*.md" -exec grep -l "^id: *\"$ENTRY_ID\"" {} \; 2>/dev/null | head -1)

    if [[ -z "$FILE" || ! -f "$FILE" ]]; then
        echo -e "${RED}[ERROR]${NC} Entrée non trouvée: $ENTRY_ID" >&2
        return 1
    fi

    # Lire le contenu si depuis un fichier
    if [[ -n "$CONTENT_FILE" && -f "$CONTENT_FILE" ]]; then
        CONTENT=$(cat "$CONTENT_FILE")
    fi

    # Extraire la version actuelle
    local CURRENT_VERSION=$(grep -m1 '^version:' "$FILE" | sed 's/version: *//')
    local NEW_VERSION=$((CURRENT_VERSION + 1))

    # Archiver la version précédente
    local ARCHIVE_FILE="${FILE%.md}.v${CURRENT_VERSION}.md"
    cp "$FILE" "$ARCHIVE_FILE"

    local NOW=$(date -Iseconds)
    local TITLE=$(grep -m1 '^# ' "$FILE" | sed 's/^# //')
    local OLD_CONTENT=""

    if [[ "$INCLUDE_PREVIOUS" == "true" ]]; then
        # Extraire le contenu précédent (après le front matter)
        OLD_CONTENT=$(sed -n '/^---$/,/^---$/!p' "$FILE" | tail -n +2)
    fi

    # Mettre à jour le fichier
    local TEMP_FILE=$(mktemp)

    # Reconstruire avec le nouveau contenu
    sed -n '1,/^---$/p' "$FILE" | head -n -1 > "$TEMP_FILE"

    cat >> "$TEMP_FILE" << EOF
version: $NEW_VERSION
updated: "$NOW"
supersedes: "${ENTRY_ID}.v${CURRENT_VERSION}"
includes_previous: $INCLUDE_PREVIOUS
EOF

    # Ajouter au trail
    echo "audit_trail:" >> "$TEMP_FILE"
    grep -A100 '^audit_trail:' "$FILE" | tail -n +2 | grep -E '^\s+-' >> "$TEMP_FILE" || true
    cat >> "$TEMP_FILE" << EOF
  - version: $NEW_VERSION
    date: "$NOW"
    author: "$AUTHOR"
    reason: "$REASON"
---

# $TITLE

## Contenu actuel (v$NEW_VERSION)
$CONTENT

EOF

    if [[ "$INCLUDE_PREVIOUS" == "true" && -n "$OLD_CONTENT" ]]; then
        cat >> "$TEMP_FILE" << EOF
## Contenu précédent toujours valide (v$CURRENT_VERSION)
$OLD_CONTENT
EOF
    fi

    mv "$TEMP_FILE" "$FILE"

    echo -e "${GREEN}[OK]${NC} Entrée mise à jour: $ENTRY_ID (v$CURRENT_VERSION → v$NEW_VERSION)"
    echo -e "${BLUE}[INFO]${NC} Archive: $ARCHIVE_FILE"

    return 0
}

# Fonction: Créer une nouvelle catégorie
create_category() {
    local PATH_NAME=""
    local DESCRIPTION=""
    local PARENT=""
    local RELATED=""

    while [[ $# -gt 0 ]]; do
        case $1 in
            --path)
                PATH_NAME="$2"
                shift 2
                ;;
            --description)
                DESCRIPTION="$2"
                shift 2
                ;;
            --parent)
                PARENT="$2"
                shift 2
                ;;
            --related)
                RELATED="$2"
                shift 2
                ;;
            *)
                shift
                ;;
        esac
    done

    if [[ -z "$PATH_NAME" || -z "$DESCRIPTION" ]]; then
        echo -e "${RED}[ERROR]${NC} Usage: memory_manager.sh create-category --path <path> --description <desc>" >&2
        return 1
    fi

    # Créer le répertoire
    mkdir -p "${MEMORY_DIR}/${PATH_NAME}"

    # Créer l'index local
    cat > "${MEMORY_DIR}/${PATH_NAME}/_index.json" << EOF
{
  "category": "$PATH_NAME",
  "description": "$DESCRIPTION",
  "entries": [],
  "subcategories": [],
  "related_categories": [$(echo "$RELATED" | sed 's/,/","/g' | sed 's/^/"/' | sed 's/$/"/' || echo "")]
}
EOF

    # Mettre à jour l'index global
    local NOW=$(date -Iseconds)
    local TEMP_FILE=$(mktemp)

    jq --arg path "$PATH_NAME" \
       --arg desc "$DESCRIPTION" \
       --arg now "$NOW" \
       --arg parent "$PARENT" \
       '
       .last_updated = $now |
       .version += 1 |
       .categories += [{
         path: $path,
         description: $desc,
         entry_count: 0,
         subcategories: [],
         created: $now,
         created_by: "system"
       }]
       ' "$INDEX_FILE" > "$TEMP_FILE"

    mv "$TEMP_FILE" "$INDEX_FILE"

    echo -e "${GREEN}[OK]${NC} Catégorie créée: $PATH_NAME"

    return 0
}

# Fonction: Déplacer une entrée vers une autre catégorie
move_entry() {
    local ENTRY_ID=""
    local TO_CATEGORY=""
    local CREATE_IF_MISSING=false

    while [[ $# -gt 0 ]]; do
        case $1 in
            --id)
                ENTRY_ID="$2"
                shift 2
                ;;
            --to-category)
                TO_CATEGORY="$2"
                shift 2
                ;;
            --create-category-if-missing)
                CREATE_IF_MISSING=true
                shift
                ;;
            *)
                shift
                ;;
        esac
    done

    if [[ -z "$ENTRY_ID" || -z "$TO_CATEGORY" ]]; then
        echo -e "${RED}[ERROR]${NC} Usage: memory_manager.sh move --id <entry_id> --to-category <category>" >&2
        return 1
    fi

    # Trouver le fichier source
    local FILE=$(find "$MEMORY_DIR" -name "*.md" -exec grep -l "^id: *\"$ENTRY_ID\"" {} \; 2>/dev/null | head -1)

    if [[ -z "$FILE" || ! -f "$FILE" ]]; then
        echo -e "${RED}[ERROR]${NC} Entrée non trouvée: $ENTRY_ID" >&2
        return 1
    fi

    # Vérifier/créer la catégorie cible
    if [[ ! -d "${MEMORY_DIR}/${TO_CATEGORY}" ]]; then
        if [[ "$CREATE_IF_MISSING" == "true" ]]; then
            mkdir -p "${MEMORY_DIR}/${TO_CATEGORY}"
        else
            echo -e "${RED}[ERROR]${NC} Catégorie cible non trouvée: $TO_CATEGORY" >&2
            return 1
        fi
    fi

    # Déplacer le fichier
    local FILENAME=$(basename "$FILE")
    local NEW_FILE="${MEMORY_DIR}/${TO_CATEGORY}/${FILENAME}"

    mv "$FILE" "$NEW_FILE"

    # Mettre à jour la catégorie dans le fichier
    sed -i "s|^category: .*|category: \"$TO_CATEGORY\"|" "$NEW_FILE"

    echo -e "${GREEN}[OK]${NC} Entrée déplacée: $ENTRY_ID → $TO_CATEGORY"

    return 0
}

# Initialisation
init_memory

# Point d'entrée principal
case "${1:-}" in
    search)
        shift
        search_memory "$@"
        ;;
    read)
        shift
        read_entry "$@"
        ;;
    list)
        shift
        list_entries "$@"
        ;;
    create)
        shift
        create_entry "$@"
        ;;
    update)
        shift
        update_entry "$@"
        ;;
    create-category)
        shift
        create_category "$@"
        ;;
    move)
        shift
        move_entry "$@"
        ;;
    *)
        echo "Usage: $0 <command> [arguments]"
        echo ""
        echo "Commands:"
        echo "  search <query>                           Rechercher dans la mémoire"
        echo "  search --category <cat> <query>          Rechercher dans une catégorie"
        echo "  read <entry_id>                          Lire une entrée (--summary|--headers|--full)"
        echo "  list [--category <cat>]                  Lister les entrées"
        echo "  create --category <cat> --title <t> ...  Créer une nouvelle entrée"
        echo "  update --id <id> --author <a> ...        Mettre à jour une entrée"
        echo "  create-category --path <p> --desc <d>    Créer une nouvelle catégorie"
        echo "  move --id <id> --to-category <cat>       Déplacer une entrée"
        exit 1
        ;;
esac
