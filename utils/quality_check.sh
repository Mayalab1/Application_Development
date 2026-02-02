#!/bin/bash
# quality_check.sh - Vérification de qualité avant commit (inspiré de Ralph)
#
# Usage: ./quality_check.sh <task_id> [config_file]
#
# Exécute les checks de qualité configurés et bloque le commit si échec.

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TASK_ID="$1"
CONFIG_FILE="${2:-${SCRIPT_DIR}/config.json}"

# Couleurs
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

if [[ -z "$TASK_ID" ]]; then
    echo -e "${RED}[ERROR]${NC} Usage: quality_check.sh <task_id> [config_file]"
    exit 1
fi

echo -e "${BLUE}═══════════════════════════════════════════════════════════════${NC}"
echo -e "${BLUE}           QUALITY CHECKS - $TASK_ID                            ${NC}"
echo -e "${BLUE}═══════════════════════════════════════════════════════════════${NC}"
echo ""

# Charger la configuration
QUALITY_ENABLED=$(jq -r '.qualityChecks.enabled // true' "$CONFIG_FILE")
TYPECHECK=$(jq -r '.qualityChecks.typecheck // true' "$CONFIG_FILE")
LINT=$(jq -r '.qualityChecks.lint // true' "$CONFIG_FILE")
FORMAT=$(jq -r '.qualityChecks.format // true' "$CONFIG_FILE")
UNIT_TESTS=$(jq -r '.qualityChecks.unitTests // true' "$CONFIG_FILE")
INTEGRATION_TESTS=$(jq -r '.qualityChecks.integrationTests // false' "$CONFIG_FILE")
FAIL_ON_WARNINGS=$(jq -r '.qualityChecks.failOnWarnings // true' "$CONFIG_FILE")

if [[ "$QUALITY_ENABLED" != "true" ]]; then
    echo -e "${YELLOW}[WARNING]${NC} Quality checks désactivés dans la configuration"
    exit 0
fi

ERRORS=()
WARNINGS=()

# Fonction: Exécuter un check
run_check() {
    local NAME="$1"
    local CMD="$2"
    local REQUIRED="${3:-true}"

    echo -e "${BLUE}→${NC} $NAME..."

    local OUTPUT
    local EXIT_CODE

    OUTPUT=$(eval "$CMD" 2>&1) || EXIT_CODE=$?
    EXIT_CODE=${EXIT_CODE:-0}

    if [[ $EXIT_CODE -eq 0 ]]; then
        echo -e "  ${GREEN}✓${NC} $NAME passed"
        return 0
    else
        if [[ "$REQUIRED" == "true" ]]; then
            echo -e "  ${RED}✗${NC} $NAME failed"
            ERRORS+=("$NAME")

            # Afficher un extrait de l'erreur
            if [[ -n "$OUTPUT" ]]; then
                echo "$OUTPUT" | head -10 | sed 's/^/    /'
            fi
        else
            echo -e "  ${YELLOW}⚠${NC} $NAME warning"
            WARNINGS+=("$NAME")
        fi
        return 1
    fi
}

# Détecter le type de projet
detect_project_type() {
    if [[ -f "package.json" ]]; then
        echo "node"
    elif [[ -f "pom.xml" ]]; then
        echo "maven"
    elif [[ -f "build.gradle" || -f "build.gradle.kts" ]]; then
        echo "gradle"
    elif [[ -f "Cargo.toml" ]]; then
        echo "rust"
    elif [[ -f "go.mod" ]]; then
        echo "go"
    elif [[ -f "requirements.txt" || -f "pyproject.toml" ]]; then
        echo "python"
    else
        echo "unknown"
    fi
}

PROJECT_TYPE=$(detect_project_type)
echo -e "${BLUE}[INFO]${NC} Type de projet détecté: $PROJECT_TYPE"
echo ""

# ═══════════════════════════════════════════════════════════════════
# 1. TYPECHECK
# ═══════════════════════════════════════════════════════════════════
if [[ "$TYPECHECK" == "true" ]]; then
    case $PROJECT_TYPE in
        node)
            if [[ -f "tsconfig.json" ]]; then
                run_check "TypeScript typecheck" "npx tsc --noEmit" || true
            else
                echo -e "${YELLOW}[SKIP]${NC} Pas de tsconfig.json trouvé"
            fi
            ;;
        maven)
            run_check "Maven compile" "mvn compile -q" || true
            ;;
        gradle)
            run_check "Gradle compile" "./gradlew compileJava -q" || true
            ;;
        rust)
            run_check "Rust check" "cargo check" || true
            ;;
        go)
            run_check "Go vet" "go vet ./..." || true
            ;;
        python)
            if command -v mypy &>/dev/null; then
                run_check "Python mypy" "mypy ." || true
            fi
            ;;
        *)
            echo -e "${YELLOW}[SKIP]${NC} Typecheck non supporté pour ce type de projet"
            ;;
    esac
fi

# ═══════════════════════════════════════════════════════════════════
# 2. LINT
# ═══════════════════════════════════════════════════════════════════
if [[ "$LINT" == "true" ]]; then
    case $PROJECT_TYPE in
        node)
            if [[ -f ".eslintrc.js" || -f ".eslintrc.json" || -f ".eslintrc.yml" || -f "eslint.config.js" ]]; then
                local ESLINT_FLAGS=""
                if [[ "$FAIL_ON_WARNINGS" == "true" ]]; then
                    ESLINT_FLAGS="--max-warnings 0"
                fi
                run_check "ESLint" "npx eslint . $ESLINT_FLAGS" || true
            else
                echo -e "${YELLOW}[SKIP]${NC} Pas de configuration ESLint trouvée"
            fi
            ;;
        maven)
            if grep -q "checkstyle" pom.xml 2>/dev/null; then
                run_check "Checkstyle" "mvn checkstyle:check -q" || true
            fi
            ;;
        rust)
            run_check "Clippy" "cargo clippy -- -D warnings" || true
            ;;
        go)
            if command -v golangci-lint &>/dev/null; then
                run_check "golangci-lint" "golangci-lint run" || true
            fi
            ;;
        python)
            if command -v ruff &>/dev/null; then
                run_check "Ruff" "ruff check ." || true
            elif command -v flake8 &>/dev/null; then
                run_check "Flake8" "flake8 ." || true
            fi
            ;;
        *)
            echo -e "${YELLOW}[SKIP]${NC} Lint non supporté pour ce type de projet"
            ;;
    esac
fi

# ═══════════════════════════════════════════════════════════════════
# 3. FORMAT CHECK
# ═══════════════════════════════════════════════════════════════════
if [[ "$FORMAT" == "true" ]]; then
    case $PROJECT_TYPE in
        node)
            if [[ -f ".prettierrc" || -f ".prettierrc.json" || -f "prettier.config.js" ]]; then
                run_check "Prettier" "npx prettier --check ." || true
            fi
            ;;
        rust)
            run_check "Rustfmt" "cargo fmt -- --check" || true
            ;;
        go)
            run_check "Gofmt" "test -z \"\$(gofmt -l .)\"" || true
            ;;
        python)
            if command -v black &>/dev/null; then
                run_check "Black" "black --check ." || true
            fi
            ;;
        *)
            echo -e "${YELLOW}[SKIP]${NC} Format check non supporté pour ce type de projet"
            ;;
    esac
fi

# ═══════════════════════════════════════════════════════════════════
# 4. UNIT TESTS
# ═══════════════════════════════════════════════════════════════════
if [[ "$UNIT_TESTS" == "true" ]]; then
    case $PROJECT_TYPE in
        node)
            if [[ -f "package.json" ]]; then
                if grep -q '"test"' package.json 2>/dev/null; then
                    run_check "Unit tests" "npm test -- --passWithNoTests" || true
                else
                    echo -e "${YELLOW}[SKIP]${NC} Pas de script 'test' dans package.json"
                fi
            fi
            ;;
        maven)
            run_check "Maven tests" "mvn test -q" || true
            ;;
        gradle)
            run_check "Gradle tests" "./gradlew test -q" || true
            ;;
        rust)
            run_check "Cargo tests" "cargo test" || true
            ;;
        go)
            run_check "Go tests" "go test ./..." || true
            ;;
        python)
            if command -v pytest &>/dev/null; then
                run_check "Pytest" "pytest" || true
            elif command -v python &>/dev/null; then
                run_check "Python unittest" "python -m unittest discover" || true
            fi
            ;;
        *)
            echo -e "${YELLOW}[SKIP]${NC} Tests non supportés pour ce type de projet"
            ;;
    esac
fi

# ═══════════════════════════════════════════════════════════════════
# 5. INTEGRATION TESTS
# ═══════════════════════════════════════════════════════════════════
if [[ "$INTEGRATION_TESTS" == "true" ]]; then
    case $PROJECT_TYPE in
        node)
            if [[ -f "package.json" ]] && grep -q '"test:integration"' package.json 2>/dev/null; then
                run_check "Integration tests" "npm run test:integration" || true
            fi
            ;;
        maven)
            run_check "Maven integration tests" "mvn verify -q" || true
            ;;
        *)
            echo -e "${YELLOW}[SKIP]${NC} Integration tests non configurés"
            ;;
    esac
fi

# ═══════════════════════════════════════════════════════════════════
# RÉSUMÉ
# ═══════════════════════════════════════════════════════════════════
echo ""
echo -e "${BLUE}═══════════════════════════════════════════════════════════════${NC}"
echo -e "${BLUE}                         RÉSUMÉ                                 ${NC}"
echo -e "${BLUE}═══════════════════════════════════════════════════════════════${NC}"

if [[ ${#ERRORS[@]} -gt 0 ]]; then
    echo ""
    echo -e "${RED}══════════════════════════════════════════════════════════════${NC}"
    echo -e "${RED}⛔ QUALITY CHECKS FAILED - Commit bloqué                       ${NC}"
    echo -e "${RED}══════════════════════════════════════════════════════════════${NC}"

    for ERR in "${ERRORS[@]}"; do
        echo -e "  ${RED}✗${NC} $ERR"
    done

    echo ""
    echo "Corrigez ces erreurs avant de pouvoir committer."
    exit 1
fi

if [[ ${#WARNINGS[@]} -gt 0 ]]; then
    echo ""
    echo -e "${YELLOW}[WARNING]${NC} Avertissements détectés:"

    for WARN in "${WARNINGS[@]}"; do
        echo -e "  ${YELLOW}⚠${NC} $WARN"
    done

    if [[ "$FAIL_ON_WARNINGS" == "true" ]]; then
        echo ""
        echo "failOnWarnings=true - Commit bloqué."
        exit 1
    fi
fi

echo ""
echo -e "${GREEN}✓ Tous les quality checks passent${NC}"
echo ""

exit 0
