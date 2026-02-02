#!/bin/bash
# add_mandatory_criteria.sh - Ajout automatique des acceptance criteria obligatoires
#
# Usage: ./add_mandatory_criteria.sh <tasks_file>
#
# Ajoute les critères obligatoires selon le type de chaque tâche:
# - Toutes: "✓ Typecheck passes"
# - logic/api/model: + "✓ Tests passent"
# - ui: + "✓ Vérifier visuellement dans le navigateur"

set -e

TASKS_FILE="$1"

# Couleurs
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

if [[ -z "$TASKS_FILE" || ! -f "$TASKS_FILE" ]]; then
    echo -e "${RED}[ERROR]${NC} Usage: add_mandatory_criteria.sh <tasks_file>"
    exit 1
fi

echo -e "${BLUE}═══════════════════════════════════════════════════════════════${NC}"
echo -e "${BLUE}       AJOUT DES ACCEPTANCE CRITERIA OBLIGATOIRES               ${NC}"
echo -e "${BLUE}═══════════════════════════════════════════════════════════════${NC}"
echo ""

# Critères obligatoires par type
TYPECHECK_CRITERION="✓ Typecheck passes"
TESTS_CRITERION="✓ Tests passent"
VISUAL_CRITERION="✓ Vérifier visuellement dans le navigateur"
LINT_CRITERION="✓ Lint passes"

# Compter les tâches
TOTAL_TASKS=$(jq '.tasks | length' "$TASKS_FILE")
UPDATED=0

echo -e "${BLUE}[INFO]${NC} Traitement de $TOTAL_TASKS tâche(s)..."
echo ""

# Créer un fichier temporaire pour les modifications
TEMP_FILE=$(mktemp)

# Traiter chaque tâche avec jq
jq '
  .tasks |= map(
    . as $task |
    # Critères à ajouter selon le type
    (
      # Toujours ajouter typecheck
      ["✓ Typecheck passes"] +
      # Ajouter tests pour logic, api, model
      (if .type == "logic" or .type == "api" or .type == "model" then
        ["✓ Tests passent"]
      else
        []
      end) +
      # Ajouter vérification visuelle pour ui
      (if .type == "ui" then
        ["✓ Vérifier visuellement dans le navigateur"]
      else
        []
      end)
    ) as $mandatory |
    # Filtrer les critères déjà présents
    ($mandatory | map(select(. as $c | $task.acceptanceCriteria | index($c) == null))) as $to_add |
    # Ajouter les nouveaux critères
    .acceptanceCriteria += $to_add
  )
' "$TASKS_FILE" > "$TEMP_FILE"

# Vérifier si des modifications ont été faites
if ! diff -q "$TASKS_FILE" "$TEMP_FILE" > /dev/null 2>&1; then
    mv "$TEMP_FILE" "$TASKS_FILE"

    # Compter les tâches modifiées
    echo -e "${GREEN}[OK]${NC} Critères obligatoires ajoutés"

    # Afficher un résumé par type
    echo ""
    echo "Résumé par type de tâche:"

    for TYPE in ui logic api model test config doc; do
        COUNT=$(jq "[.tasks[] | select(.type == \"$TYPE\")] | length" "$TASKS_FILE")
        if [[ $COUNT -gt 0 ]]; then
            echo -e "  ${BLUE}$TYPE${NC}: $COUNT tâche(s)"
        fi
    done
else
    rm -f "$TEMP_FILE"
    echo -e "${YELLOW}[INFO]${NC} Aucune modification nécessaire - critères déjà présents"
fi

echo ""
echo -e "${GREEN}═══════════════════════════════════════════════════════════════${NC}"
echo -e "${GREEN}                          TERMINÉ                               ${NC}"
echo -e "${GREEN}═══════════════════════════════════════════════════════════════${NC}"

exit 0
