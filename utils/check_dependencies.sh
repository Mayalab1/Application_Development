#!/bin/bash
# check_dependencies.sh - Vérification des dépendances externes avant exécution
#
# Usage: ./check_dependencies.sh [dependencies.json]
#
# Vérifie que tous les composants requis (runtime, tools, servers, databases)
# sont installés et disponibles avant de lancer le pipeline.

set -e

DEPS_FILE="${1:-dependencies.json}"

# Couleurs
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

if [[ ! -f "$DEPS_FILE" ]]; then
    echo -e "${YELLOW}[WARNING]${NC} Fichier de dépendances non trouvé: $DEPS_FILE"
    echo -e "${BLUE}[INFO]${NC} Aucune vérification de dépendances effectuée."
    exit 0
fi

echo -e "${BLUE}═══════════════════════════════════════════════════════════════${NC}"
echo -e "${BLUE}              VÉRIFICATION DES DÉPENDANCES                      ${NC}"
echo -e "${BLUE}═══════════════════════════════════════════════════════════════${NC}"
echo ""

MISSING=()
OPTIONAL_MISSING=()

# Fonction: Vérifier une dépendance
check_dependency() {
    local NAME="$1"
    local CMD="$2"
    local REQUIRED="$3"
    local MIN_VERSION="$4"

    # Exécuter la commande de vérification
    if eval "$CMD" &>/dev/null; then
        # Récupérer la version si possible
        local VERSION=$(eval "$CMD" 2>&1 | grep -oE '[0-9]+\.[0-9]+(\.[0-9]+)?' | head -1 || echo "")

        if [[ -n "$VERSION" ]]; then
            echo -e "${GREEN}✓${NC} $NAME : installé (v$VERSION)"
        else
            echo -e "${GREEN}✓${NC} $NAME : installé"
        fi

        # TODO: Comparer les versions si MIN_VERSION est spécifié
        return 0
    else
        if [[ "$REQUIRED" == "true" ]]; then
            echo -e "${RED}✗${NC} $NAME : NON INSTALLÉ (requis)"
            MISSING+=("$NAME")
        else
            echo -e "${YELLOW}⚠${NC} $NAME : non installé (optionnel)"
            OPTIONAL_MISSING+=("$NAME")
        fi
        return 1
    fi
}

# Vérifier chaque catégorie
for CATEGORY in runtime tools servers databases; do
    # Vérifier si la catégorie existe et n'est pas vide
    DEPS=$(jq -r ".$CATEGORY[]? | @base64" "$DEPS_FILE" 2>/dev/null)

    if [[ -n "$DEPS" ]]; then
        echo -e "${BLUE}[$CATEGORY]${NC}"

        for DEP in $DEPS; do
            # Décoder le JSON en base64
            _jq() {
                echo "$DEP" | base64 --decode | jq -r "$1" 2>/dev/null || echo ""
            }

            NAME=$(_jq '.name')
            CMD=$(_jq '.checkCommand')
            MIN_VERSION=$(_jq '.minVersion // ""')

            # Déterminer si requis
            REQUIRED=$(_jq '.required // "true"')
            OPTIONAL=$(_jq '.optional // "false"')

            if [[ "$OPTIONAL" == "true" ]]; then
                REQUIRED="false"
            fi

            if [[ -n "$NAME" && -n "$CMD" ]]; then
                check_dependency "$NAME" "$CMD" "$REQUIRED" "$MIN_VERSION"
            fi
        done

        echo ""
    fi
done

# Résumé
echo -e "${BLUE}═══════════════════════════════════════════════════════════════${NC}"

if [[ ${#MISSING[@]} -gt 0 ]]; then
    echo ""
    echo -e "${RED}══════════════════════════════════════════════════════════════${NC}"
    echo -e "${RED}⛔ DÉPENDANCES MANQUANTES - Installation requise              ${NC}"
    echo -e "${RED}══════════════════════════════════════════════════════════════${NC}"
    echo ""

    for DEP in "${MISSING[@]}"; do
        echo -e "  ${RED}•${NC} $DEP"

        # Chercher les instructions d'installation si disponibles
        INSTALL_INSTRUCTIONS=$(jq -r ".. | objects | select(.name == \"$DEP\") | .installInstructions // empty" "$DEPS_FILE" 2>/dev/null)

        if [[ -n "$INSTALL_INSTRUCTIONS" ]]; then
            echo -e "    ${BLUE}Installation:${NC} $INSTALL_INSTRUCTIONS"
        fi
    done

    echo ""
    echo -e "Veuillez installer ces composants avant de continuer."
    echo ""

    exit 1
fi

if [[ ${#OPTIONAL_MISSING[@]} -gt 0 ]]; then
    echo ""
    echo -e "${YELLOW}[WARNING]${NC} Dépendances optionnelles manquantes:"

    for DEP in "${OPTIONAL_MISSING[@]}"; do
        echo -e "  ${YELLOW}•${NC} $DEP"
    done

    echo ""
    echo -e "Ces composants sont optionnels mais certaines fonctionnalités"
    echo -e "pourraient ne pas être disponibles."
    echo ""
fi

echo ""
echo -e "${GREEN}✓ Toutes les dépendances requises sont installées${NC}"
echo ""

exit 0
