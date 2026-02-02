# Plan : Framework d'Orchestration Multi-Sessions Claude CLI

## Objectif
Créer un framework permettant de décomposer une application (décrite dans `application.md`) en features, puis en tâches atomiques, implémentées par des sessions Claude CLI indépendantes avec gestion des locks.

---

## Architecture du Framework

```
project_root/
├── run.sh                              # Script principal d'orchestration
├── config.json                         # Configuration du framework
├── application.md                      # Description initiale
├── application_update_YYMMDD:HHMM.md   # Mises à jour ultérieures
├── context/
│   ├── architecture.md                 # Architecture technique (généré)
│   ├── conventions.md                  # Conventions de code
│   └── glossary.md                     # Glossaire métier (généré par BA)
├── memory/                             # Mémoire partagée hiérarchique (évolutive)
│   ├── _index.json                     # Index global
│   ├── _inbox/                         # Zone de staging (à classifier)
│   │   └── _index.json
│   ├── domain/
│   │   ├── _index.json
│   │   ├── rules/
│   │   └── workflows/
│   ├── architecture/
│   │   └── _index.json
│   ├── ui_patterns/
│   ├── configuration/
│   └── [nouvelles catégories créées dynamiquement...]
├── features/
│   ├── feature_001_xxx.json
│   │   └── tasks.json
│   ├── feature_002_yyy.json
│   │   └── tasks.json
│   └── ...
├── locks/
│   ├── features/                       # Locks sur features
│   └── files/                          # Locks sur fichiers source
├── logs/
│   └── sessions/                       # Logs par session
├── status.json                         # État global du projet
└── src/                                # Code source généré
```

---

## Principes fondamentaux

### Sessions LLM isolées
- **Chaque invocation d'agent = nouvelle session Claude CLI**
- Pas de contexte partagé entre sessions
- Le contexte est reconstruit à partir des fichiers du projet (features/*.json, tasks.json, etc.)
- Permet la reprise après interruption et le parallélisme

### Modes d'exécution

Le framework supporte deux modes :

**1. Pipeline complet**
```bash
./run.sh --full                    # Exécute tout le pipeline
```

**2. Agent individuel**
```bash
# Business Analyst
./run.sh --agent business-analyst                     # Décompose application.md en features
./run.sh --agent business-analyst --update 260202:1430  # Traite un fichier update

# Architect
./run.sh --agent architect                            # Décompose TOUTES les features en tâches
./run.sh --agent architect --feature feature_001      # Décompose UNE feature spécifique

# Developer
./run.sh --agent developer                            # Implémente TOUTES les tâches Pending
./run.sh --agent developer --task F001_T003           # Implémente UNE tâche spécifique
./run.sh --agent developer --feature feature_001      # Implémente les tâches d'UNE feature

# Reviewer (optionnel, peut être appelé après developer)
./run.sh --agent reviewer --task F001_T003            # Review une tâche implémentée

# Tester (optionnel, peut être appelé après reviewer)
./run.sh --agent tester --task F001_T003              # Teste une tâche reviewée
```

---

## Configuration du Framework

**`config.json`** - Paramètres configurables :

```json
{
  "execution": {
    "maxParallelSessions": 3,
    "ralphWiggum": {
      "maxRetries": 7,
      "retryDelaySeconds": 10
    },
    "quotaCheck": {
      "enabled": true,
      "minRemainingPercent": 10,
      "pauseOnLowQuota": true
    }
  },
  "models": {
    "business-analyst": "claude-opus-4-5-20251101",
    "architect": "claude-opus-4-5-20251101",
    "developer": "claude-sonnet-4-5-20251101",
    "reviewer": "claude-sonnet-4-5-20251101",
    "tester": "claude-sonnet-4-5-20251101",
    "default": "claude-sonnet-4-5-20251101"
  },
  "locks": {
    "expirationMinutes": 60,
    "checkIntervalSeconds": 5
  },
  "memory": {
    "maxEntriesPerQuery": 5,
    "maxTotalEntriesPerTask": 10,
    "relevanceThreshold": 0.7,
    "defaultReadMode": "full",
    "summaryMaxTokens": 100
  },
  "git": {
    "autoCommit": true,
    "commitPerTask": true,
    "commitMessagePrefix": "feat"
  },
  "logging": {
    "level": "info",
    "saveSessionLogs": true
  }
}
```

| Paramètre | Description | Défaut |
|-----------|-------------|--------|
| `maxParallelSessions` | Nombre max de sessions d'implémentation simultanées | 3 |
| `ralphWiggum.maxRetries` | Nombre max de tentatives par tâche | 7 |
| `ralphWiggum.retryDelaySeconds` | Délai entre deux tentatives | 10 |
| `quotaCheck.enabled` | Vérifier quota avant chaque invocation | true |
| `quotaCheck.minRemainingPercent` | Seuil minimum avant pause | 10 |
| `models.business-analyst` | Modèle LLM pour Business Analyst | claude-opus-4-5 |
| `models.architect` | Modèle LLM pour Architect | claude-opus-4-5 |
| `models.developer` | Modèle LLM pour Developer | claude-sonnet-4-5 |
| `models.reviewer` | Modèle LLM pour Reviewer | claude-sonnet-4-5 |
| `models.tester` | Modèle LLM pour Tester | claude-sonnet-4-5 |
| `locks.expirationMinutes` | Durée avant expiration d'un lock | 60 |
| `memory.maxEntriesPerQuery` | Limite résultats par recherche mémoire | 5 |
| `memory.maxTotalEntriesPerTask` | Max entrées mémoire chargées par tâche | 10 |
| `memory.relevanceThreshold` | Seuil de pertinence (0-1) | 0.7 |
| `git.autoCommit` | Commit automatique après chaque tâche | true |

---

## Fichiers à créer

### 1. Schémas JSON

**`schemas/feature.schema.json`**
- id, title, description, status, priority
- dependencies (autres features)
- acceptanceCriteria
- estimatedTasks
- createdAt, updatedAt

**`schemas/task.schema.json`** (voir section "Formalisation des Tâches" ci-dessous)

**`schemas/lock.schema.json`**
- lockedBy (session_id)
- lockedAt, expiresAt
- files[], taskId

### 2. Scripts d'orchestration

**`scripts/master_decompose.md`** (prompt pour session master)
- Instructions pour lire application.md
- Règles de décomposition en features
- Format de sortie attendu

**`scripts/feature_decompose.md`** (prompt pour sessions feature)
- Instructions pour décomposer une feature en tâches atomiques
- Critères de granularité
- Gestion des dépendances intra-feature

**`scripts/task_implement.md`** (prompt pour sessions implémentation)
- Instructions pour implémenter une tâche
- Protocole de lock/unlock
- Gestion des erreurs

### 3. Utilitaires

**`utils/lock_manager.sh`**
- acquire_lock(session_id, task_id, files[])
- release_lock(session_id, task_id)
- check_lock(file)
- cleanup_expired_locks()

**`utils/status_updater.sh`**
- update_task_status(task_id, status)
- update_feature_status(feature_id)
- generate_progress_report()

---

## Configuration des Modèles LLM

### Modèles par défaut par agent

| Agent | Modèle par défaut | Justification |
|-------|-------------------|---------------|
| **Business Analyst** | Claude Opus 4.5 | Analyse complexe, compréhension métier |
| **Architect** | Claude Opus 4.5 | Décisions d'architecture critiques |
| **Developer** | Claude Sonnet 4.5 | Bon équilibre performance/coût pour code |
| **Reviewer** | Claude Sonnet 4.5 | Revue de code efficace |
| **Tester** | Claude Sonnet 4.5 | Génération de tests |

### Personnalisation

```json
{
  "models": {
    "business-analyst": "claude-opus-4-5-20251101",
    "architect": "claude-opus-4-5-20251101",
    "developer": "claude-sonnet-4-5-20251101",
    "reviewer": "claude-sonnet-4-5-20251101",
    "tester": "claude-sonnet-4-5-20251101",
    "default": "claude-sonnet-4-5-20251101"
  }
}
```

### Override par ligne de commande

```bash
# Utiliser un modèle spécifique pour une invocation
./run.sh --agent developer --model claude-opus-4-5-20251101 --task F001_T003
```

---

## Gestion des Quotas (Plan Max Claude)

### Approche : Session Claude Code Orchestratrice

Au lieu de scripts bash autonomes, une **session Claude Code** sert d'orchestrateur :

```
┌─────────────────────────────────────────────────────────────────┐
│  SESSION CLAUDE CODE ORCHESTRATRICE                              │
│  - Vérifie son propre quota (visibilité native)                 │
│  - Lit config.json, application.md, features/, tasks.json       │
│  - Décide quel agent lancer selon quota disponible              │
│  - Lance les sous-sessions via Task tool ou Bash                │
│  - Gère les interruptions et reprises intelligemment            │
└─────────────────────────┬───────────────────────────────────────┘
                          │
          ┌───────────────┼───────────────┬───────────────┐
          ▼               ▼               ▼               ▼
   [Business Analyst] [Architect]   [Developer]    [Reviewer/Tester]
   (sous-session)     (sous-session) (sous-session)  (sous-session)
```

### Avantages

| Aspect | Bénéfice |
|--------|----------|
| **Quota visible** | Claude Code connaît son propre état |
| **Décision intelligente** | Peut prioriser selon quota restant |
| **Gestion d'erreurs** | Réagit en temps réel aux interruptions |
| **Moins de scripts** | Logique dans Claude Code, pas bash |
| **Contexte préservé** | L'orchestrateur garde la vue d'ensemble |

### Comportement de l'orchestrateur

```markdown
## Instructions pour la session orchestratrice

1. **Avant chaque lancement d'agent** :
   - Évaluer le quota restant (si faible, prioriser tâches critiques)
   - Choisir le modèle approprié (Opus si quota OK, Sonnet si quota bas)

2. **Lancement d'un agent** :
   - Utiliser Task tool pour les agents légers
   - Utiliser Bash + claude CLI pour les sessions isolées

3. **Si interruption détectée** :
   - Marquer la tâche comme "Interrupted"
   - Libérer les locks
   - Attendre ou passer à une tâche moins gourmande

4. **Si quota critique** :
   - Sauvegarder l'état actuel
   - Informer l'utilisateur
   - Proposer de reprendre plus tard
```

### Configuration

```json
{
  "execution": {
    "quotaCheck": {
      "enabled": true,
      "minRemainingPercent": 10,
      "lowQuotaStrategy": "switch-to-sonnet",
      "criticalQuotaStrategy": "pause-and-save"
    }
  }
}
```

| Paramètre | Description |
|-----------|-------------|
| `enabled` | Active la vérification de quota |
| `minRemainingPercent` | Seuil d'alerte (défaut: 10%) |
| `lowQuotaStrategy` | `switch-to-sonnet`, `prioritize-critical`, `pause` |
| `criticalQuotaStrategy` | `pause-and-save`, `notify-user` |

### Stratégies selon niveau de quota

```
Quota > 30%  → ✓ Mode normal (Opus pour BA/Architect, Sonnet pour Dev)
Quota 10-30% → ⚠️ Mode économique (Sonnet pour tous, tâches prioritaires)
Quota < 10%  → 🔶 Mode critique (pause, sauvegarde état, attente)
Quota = 0%   → ❌ Arrêt complet, notification utilisateur
```

### Gestion de l'interruption en cours d'exécution

Si la limite est atteinte **pendant** l'exécution d'un agent :

**Détection :**
```bash
# Watchdog dans ralph_wiggum_task.sh
timeout --signal=TERM $MAX_TASK_DURATION claude ... || {
  EXIT_CODE=$?
  if [[ $EXIT_CODE -eq 124 ]] || [[ $EXIT_CODE -eq 137 ]]; then
    # Timeout ou kill - possiblement quota atteint
    ./utils/status_updater.sh set_status "$TASK_ID" "Interrupted" "Session terminated unexpectedly"
  fi
}
```

**Comportements :**

| Situation | Statut | Action |
|-----------|--------|--------|
| Session terminée normalement | `Implemented` ou `Error` | Normal |
| Session interrompue (quota/crash) | `Interrupted` | Libère lock, attend reprise |
| Lock expiré (60 min) | `Interrupted` | Auto-release, tâche reprend |

**Reprise automatique :**
```bash
# Cron ou script de reprise
./run.sh --resume-interrupted

# Comportement:
# 1. Cherche les tâches en statut "Interrupted"
# 2. Vérifie si quota disponible
# 3. Relance les tâches (compteur attempts++)
```

**Configuration :**
```json
{
  "execution": {
    "quotaCheck": {
      "enabled": true,
      "minRemainingPercent": 10,
      "pauseOnLowQuota": true,
      "maxTaskDurationMinutes": 30,
      "autoResumeInterrupted": true
    }
  }
}
```

**Nouveau statut de tâche : `Interrupted`**
```
Pending → InProgress → Implemented
              ↓              ↓
          Interrupted    Reviewed → Tested
              ↓
          Pending (auto-resume quand quota OK)
```

### Stratégies d'optimisation du quota

1. **Prioriser les tâches critiques** quand le quota est bas
2. **Utiliser Sonnet** pour les tâches moins complexes
3. **Planifier les tâches Opus** en début de période de quota
4. **Mode batch** : regrouper les petites tâches
5. **Checkpoints** : pour les tâches longues, sauvegarder l'état intermédiaire

---

## Types d'Agents

### Architecture des rôles (approche hybride)

| Rôle | Agent | Source | Responsabilité |
|------|-------|--------|----------------|
| **Business Analyst** | `business-analyst` | **À créer** | Lit `application.md`, décompose en features |
| **Architect** | `code-architect` | **Existant** | Décompose features en tâches atomiques |
| **Developer** | `developer` | **À créer** (basé sur `code-simplifier`) | Implémente les tâches |
| **Reviewer** | `code-reviewer` | **Existant** | Revoit le code implémenté |
| **Tester** | `pr-test-analyzer` | **Existant** | Valide les critères d'acceptation |

### Agents existants à réutiliser

**Emplacement** : `~/.claude/plugins/marketplaces/claude-plugins-official/plugins/`

```
feature-dev/agents/
├── code-architect.md      → Architect
├── code-reviewer.md       → Reviewer
└── code-explorer.md       → (support)

pr-review-toolkit/agents/
├── pr-test-analyzer.md    → Tester
├── code-simplifier.md     → (base pour Developer)
└── ...
```

### Agents à créer

**1. `agents/business-analyst.md`** - Nouveau
```markdown
# Business Analyst Agent

## Rôle
Analyser application.md et décomposer en features fonctionnelles.

## Inputs
- application.md (description de l'application)
- context/glossary.md (terminologie métier)

## Outputs
- features/feature_XXX.json pour chaque feature identifiée

## Règles
- Chaque feature doit être indépendante autant que possible
- Identifier les dépendances inter-features
- Prioriser par valeur métier
```

**2. `agents/developer.md`** - Nouveau (basé sur code-simplifier)
```markdown
# Developer Agent

## Rôle
Implémenter une tâche atomique selon ses spécifications.

## Inputs
- Tâche depuis tasks.json
- Contexte du code existant
- Contraintes et patterns à respecter

## Outputs
- Code implémenté
- Tests unitaires si requis
- Mise à jour du status de la tâche

## Règles
- Respecter les acceptance criteria
- Ne pas modifier les fichiers dans constraints.mustNotModify
- Suivre les patterns définis dans constraints.patterns
```

### Workflow des agents

```
┌─────────────────────────────────────────────────────────────────┐
│  application.md                                                  │
└─────────────────────────┬───────────────────────────────────────┘
                          │
                          ▼
┌─────────────────────────────────────────────────────────────────┐
│  BUSINESS ANALYST (à créer)                                      │
│  - Analyse application.md                                       │
│  - Génère features/feature_XXX.json                             │
└─────────────────────────┬───────────────────────────────────────┘
                          │
          ┌───────────────┼───────────────┐
          ▼               ▼               ▼
┌─────────────┐   ┌─────────────┐   ┌─────────────┐
│ ARCHITECT   │   │ ARCHITECT   │   │ ARCHITECT   │
│ (existant)  │   │ (existant)  │   │ (existant)  │
│ code-       │   │ code-       │   │ code-       │
│ architect   │   │ architect   │   │ architect   │
│ → tasks.json│   │ → tasks.json│   │ → tasks.json│
└──────┬──────┘   └──────┬──────┘   └──────┬──────┘
       │                 │                 │
       ▼                 ▼                 ▼
┌─────────────┐   ┌─────────────┐   ┌─────────────┐
│ DEVELOPER   │   │ DEVELOPER   │   │ DEVELOPER   │
│ (à créer)   │   │ (à créer)   │   │ (à créer)   │
│ Ralph       │   │ Ralph       │   │ Ralph       │
│ Wiggum loop │   │ Wiggum loop │   │ Wiggum loop │
└──────┬──────┘   └──────┬──────┘   └──────┬──────┘
       │                 │                 │
       ▼                 ▼                 ▼
┌─────────────┐   ┌─────────────┐   ┌─────────────┐
│ REVIEWER    │   │ REVIEWER    │   │ REVIEWER    │
│ (existant)  │   │ (existant)  │   │ (existant)  │
│ code-       │   │ code-       │   │ code-       │
│ reviewer    │   │ reviewer    │   │ reviewer    │
└──────┬──────┘   └──────┬──────┘   └──────┬──────┘
       │                 │                 │
       ▼                 ▼                 ▼
┌─────────────┐   ┌─────────────┐   ┌─────────────┐
│ TESTER      │   │ TESTER      │   │ TESTER      │
│ (existant)  │   │ (existant)  │   │ (existant)  │
│ pr-test-    │   │ pr-test-    │   │ pr-test-    │
│ analyzer    │   │ analyzer    │   │ analyzer    │
└─────────────┘   └─────────────┘   └─────────────┘
```

---

## Workflow détaillé

### Phase 1 : Décomposition Master (Business Analyst)
```bash
# Agent Business Analyst analyse application.md et génère les features
claude --prompt "$(cat agents/business-analyst.md)" \
       --context application.md \
       --context context/glossary.md \
       --output features/
```

### Phase 2 : Décomposition Features (Architect - parallélisable)
```bash
# Agent Architect (existant: code-architect) décompose chaque feature en tâches
for feature in features/*.json; do
  claude --prompt "$(cat agents/architect-task-decompose.md)" \
         --context "$feature" \
         --output "${feature%.*}/tasks.json" &
done
wait
```

### Phase 3 : Implémentation (Developer - parallélisable avec locks)

Chaque tâche atomique est exécutée via une **boucle Ralph Wiggum** dédiée :

```bash
#!/bin/bash
# ralph_wiggum_task.sh - Exécute une tâche avec retry automatique

TASK_ID="$1"
FEATURE_DIR="$2"
CONFIG_FILE="${3:-config.json}"

# Charger la configuration
MAX_RETRIES=$(jq -r '.execution.ralphWiggum.maxRetries' "$CONFIG_FILE")
RETRY_DELAY=$(jq -r '.execution.ralphWiggum.retryDelaySeconds' "$CONFIG_FILE")
ATTEMPT=0

while [[ $ATTEMPT -lt $MAX_RETRIES ]]; do
  ATTEMPT=$((ATTEMPT + 1))
  echo "=== Tentative $ATTEMPT/$MAX_RETRIES pour $TASK_ID ==="

  # Acquérir le lock
  ./utils/lock_manager.sh acquire "$TASK_ID" "$FEATURE_DIR"

  # Mettre à jour le statut → InProgress
  ./utils/status_updater.sh set_status "$TASK_ID" "InProgress" "$ATTEMPT"

  # Lancer Agent Developer pour implémenter la tâche
  claude --prompt "$(cat agents/developer.md)" \
         --context "$FEATURE_DIR/tasks.json" \
         --task-id "$TASK_ID"

  EXIT_CODE=$?

  # Libérer le lock
  ./utils/lock_manager.sh release "$TASK_ID"

  # Vérifier le résultat
  if [[ $EXIT_CODE -eq 0 ]]; then
    ./utils/status_updater.sh set_status "$TASK_ID" "Implemented"

    # Phase Review (Agent Reviewer - existant: code-reviewer)
    echo "=== Review de $TASK_ID ==="
    claude --prompt "$(cat agents/reviewer-prompt.md)" \
           --context "$FEATURE_DIR/tasks.json" \
           --task-id "$TASK_ID"

    REVIEW_CODE=$?
    if [[ $REVIEW_CODE -ne 0 ]]; then
      ./utils/status_updater.sh set_status "$TASK_ID" "Error" "Review failed"
      echo "✗ Review échouée pour $TASK_ID"
      sleep "$RETRY_DELAY"
      continue
    fi
    ./utils/status_updater.sh set_status "$TASK_ID" "Reviewed"

    # Phase Test (Agent Tester - existant: pr-test-analyzer)
    echo "=== Test de $TASK_ID ==="
    claude --prompt "$(cat agents/tester-prompt.md)" \
           --context "$FEATURE_DIR/tasks.json" \
           --task-id "$TASK_ID"

    TEST_CODE=$?
    if [[ $TEST_CODE -ne 0 ]]; then
      ./utils/status_updater.sh set_status "$TASK_ID" "Error" "Tests failed"
      echo "✗ Tests échoués pour $TASK_ID"
      sleep "$RETRY_DELAY"
      continue
    fi
    ./utils/status_updater.sh set_status "$TASK_ID" "Tested"

    # Commit Git automatique (1 commit par tâche)
    TASK_TITLE=$(jq -r ".tasks[] | select(.id == \"$TASK_ID\") | .title" "$FEATURE_DIR/tasks.json")
    git add -A
    git commit -m "feat($TASK_ID): $TASK_TITLE"

    echo "✓ Tâche $TASK_ID implémentée, reviewée, testée et committée"
    exit 0
  else
    ./utils/status_updater.sh set_status "$TASK_ID" "Error" "Attempt $ATTEMPT failed"
    echo "✗ Échec tentative $ATTEMPT pour $TASK_ID"
    sleep "$RETRY_DELAY"
  fi
done

echo "✗ Tâche $TASK_ID en erreur après $MAX_RETRIES tentatives"
./utils/status_updater.sh set_status "$TASK_ID" "Error" "Max retries ($MAX_RETRIES) reached"
exit 1
```

**Orchestration de plusieurs tâches en parallèle :**

```bash
#!/bin/bash
# run_feature_tasks.sh - Lance toutes les tâches d'une feature

FEATURE_DIR="$1"
CONFIG_FILE="${2:-config.json}"

# Charger la configuration
MAX_PARALLEL=$(jq -r '.execution.maxParallelSessions' "$CONFIG_FILE")

# Récupérer les tâches Pending triées par priorité
TASKS=$(jq -r '.tasks[] | select(.status == "Pending") | .id' "$FEATURE_DIR/tasks.json")

# Exécuter avec parallélisation contrôlée
echo "$TASKS" | xargs -P "$MAX_PARALLEL" -I {} ./ralph_wiggum_task.sh {} "$FEATURE_DIR" "$CONFIG_FILE"
```

### Script principal run.sh

```bash
#!/bin/bash
# run.sh - Script principal d'orchestration du framework

set -e

CONFIG_FILE="config.json"
AGENT=""
FEATURE=""
TASK=""
UPDATE=""
FULL_PIPELINE=false

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
    *)
      echo "Option inconnue: $1"
      exit 1
      ;;
  esac
done

# Fonction: Vérification quota (Plan Max Claude)
check_quota() {
  if [[ "$(jq -r '.execution.quotaCheck.enabled' "$CONFIG_FILE")" != "true" ]]; then
    return 0
  fi

  local MIN_PERCENT=$(jq -r '.execution.quotaCheck.minRemainingPercent' "$CONFIG_FILE")

  # Récupérer l'utilisation via Claude CLI
  local USAGE_INFO=$(claude --usage 2>/dev/null || echo '{"remaining_percent": 100}')
  local REMAINING=$(echo "$USAGE_INFO" | jq -r '.remaining_percent // 100')

  if (( $(echo "$REMAINING < $MIN_PERCENT" | bc -l) )); then
    echo "⚠️  Quota faible: ${REMAINING}% restant (seuil: ${MIN_PERCENT}%)"

    if [[ "$(jq -r '.execution.quotaCheck.pauseOnLowQuota' "$CONFIG_FILE")" == "true" ]]; then
      echo "⏸️  Pause automatique. Reprise possible demain ou après reset du quota."
      echo "   Pour forcer: ./run.sh --ignore-quota ..."
      exit 2
    fi
  fi

  echo "✓ Quota OK: ${REMAINING}% restant"
  return 0
}

# Fonction: Obtenir le modèle pour un agent
get_model_for_agent() {
  local AGENT_TYPE="$1"
  local MODEL=$(jq -r ".models[\"$AGENT_TYPE\"] // .models.default" "$CONFIG_FILE")
  echo "$MODEL"
}

# Fonction: Nouvelle session Claude CLI (isolée)
invoke_agent() {
  local AGENT_TYPE="$1"
  local AGENT_PROMPT="$2"
  local CONTEXT_FILES="$3"

  echo "=== Nouvelle session: $AGENT_TYPE ==="

  # Vérifier le quota avant invocation
  check_quota

  # Obtenir le modèle configuré pour cet agent
  local MODEL=$(get_model_for_agent "$AGENT_TYPE")
  echo "   Modèle: $MODEL"

  # Chaque invocation = nouvelle session Claude CLI
  claude --print \
         --model "$MODEL" \
         --dangerously-skip-permissions \
         --prompt "$AGENT_PROMPT" \
         $CONTEXT_FILES
}

# Mode: Pipeline complet
if [[ "$FULL_PIPELINE" == true ]]; then
  echo "=== Exécution pipeline complet ==="

  # Phase 1: Business Analyst
  invoke_agent "business-analyst" \
    "$(cat agents/business-analyst.md)" \
    "--context application.md --context context/glossary.md"

  # Phase 2: Architect (toutes les features)
  for feature in features/*.json; do
    invoke_agent "architect" \
      "$(cat agents/architect-task-decompose.md)" \
      "--context $feature"
  done

  # Phase 3: Developer (toutes les tâches)
  ./scripts/run_feature_tasks.sh features/ "$CONFIG_FILE"

  exit 0
fi

# Mode: Agent individuel
case $AGENT in
  business-analyst)
    if [[ -n "$UPDATE" ]]; then
      INPUT_FILE="application_update_${UPDATE}.md"
    else
      INPUT_FILE="application.md"
    fi
    invoke_agent "business-analyst" \
      "$(cat agents/business-analyst.md)" \
      "--context $INPUT_FILE --context context/glossary.md"
    ;;

  architect)
    if [[ -n "$FEATURE" ]]; then
      invoke_agent "architect" \
        "$(cat agents/architect-task-decompose.md)" \
        "--context features/${FEATURE}.json"
    else
      for feature in features/*.json; do
        invoke_agent "architect" \
          "$(cat agents/architect-task-decompose.md)" \
          "--context $feature"
      done
    fi
    ;;

  developer)
    if [[ -n "$TASK" ]]; then
      ./scripts/ralph_wiggum_task.sh "$TASK" "features/" "$CONFIG_FILE"
    elif [[ -n "$FEATURE" ]]; then
      ./scripts/run_feature_tasks.sh "features/${FEATURE}/" "$CONFIG_FILE"
    else
      ./scripts/run_feature_tasks.sh "features/" "$CONFIG_FILE"
    fi
    ;;

  reviewer)
    if [[ -n "$TASK" ]]; then
      invoke_agent "reviewer" \
        "$(cat agents/reviewer-prompt.md)" \
        "--context features/ --task-id $TASK"
    else
      echo "Erreur: --task requis pour reviewer"
      exit 1
    fi
    ;;

  tester)
    if [[ -n "$TASK" ]]; then
      invoke_agent "tester" \
        "$(cat agents/tester-prompt.md)" \
        "--context features/ --task-id $TASK"
    else
      echo "Erreur: --task requis pour tester"
      exit 1
    fi
    ;;

  *)
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
    exit 1
    ;;
esac
```

---

## Gestion des Locks

### Types de locks (granularité configurable)

| Type | Portée | Cas d'usage |
|------|--------|-------------|
| `file` | Un fichier spécifique | Modification ciblée (ex: ajouter un champ) |
| `directory` | Tout un répertoire | Création de nouveaux fichiers, refactoring |
| `pattern` | Glob pattern | Ensemble de fichiers liés (ex: `src/models/*.ts`) |

### Structure des locks

```
locks/
├── files/
│   └── src_components_UserForm.tsx.lock
├── directories/
│   └── src_models.lock
└── patterns/
    └── src_api_endpoints_*.lock
```

### Acquisition
1. Session vérifie le lock approprié selon `lockType` défini dans la tâche
2. Si non existant → crée le lock avec session_id et timestamp
3. Si existant → vérifie expiration (défaut: 60 min)
   - Expiré → prend le lock
   - Actif → passe à une autre tâche ou attend
4. **Vérification de conflits** : Un lock directory bloque aussi les locks file dans ce répertoire

### Libération
1. À la fin de la tâche (succès ou erreur)
2. Mise à jour du status dans tasks.json
3. Suppression du fichier .lock

### Format lock
```json
{
  "session_id": "impl_f001_t003_20260202143000",
  "locked_at": "2026-02-02T14:30:00Z",
  "expires_at": "2026-02-02T15:30:00Z",
  "task_id": "task_003",
  "lock_type": "file | directory | pattern",
  "target": "src/components/UserForm.tsx",
  "scope": ["src/components/UserForm.tsx"]
}
```

### Champ lockType dans les tâches

Ajouter à la structure de tâche :
```json
{
  "outputs": {
    "files": ["src/components/UserForm.tsx"],
    "lockType": "file",
    "lockTarget": "src/components/UserForm.tsx"
  }
}
```

Ou pour un répertoire :
```json
{
  "outputs": {
    "files": ["src/models/User.ts", "src/models/Customer.ts"],
    "lockType": "directory",
    "lockTarget": "src/models/"
  }
}
```

---

## États des tâches

```
Pending ──────► InProgress ──────► Implemented
                    │                    │
                    ├─────────────►     ▼
                    │              Reviewed ──► Tested
                    │
                    ├──► Interrupted ──► Pending (auto-resume quand quota OK)
                    │         │
                    │         └──► Error (si max retries atteint)
                    │
                    ▼
                 Error ◄─────────── Blocked
                    │
                    ▼
                 Pending (retry)
```

**Nouveau statut `Interrupted`** : Session interrompue (quota atteint, crash, timeout).
- Le lock est libéré automatiquement
- La tâche peut reprendre automatiquement quand le quota est restauré
- Après N interruptions → passe en `Error`

---

## Système de Mémoire Partagée

### Principes

1. **Hiérarchie multi-niveaux** : Organisation par domaine métier avec sous-catégories
2. **Consultation** : Chaque agent peut rechercher et lire les entrées pertinentes
3. **Contribution** : Un agent peut créer/modifier une entrée s'il juge utile pour d'autres agents
4. **Versioning** : Chaque modification conserve l'historique complet
5. **Inclusion cumulative** : Les nouvelles versions incluent le contenu précédent encore valide

### Structure de la mémoire

```
memory/
├── _index.json                           # Index global (catégories, stats)
├── domain/
│   ├── _index.json                       # Index catégorie
│   ├── rules/
│   │   ├── business_rules.md             # Version courante
│   │   ├── business_rules.v2.md          # Archive v2
│   │   └── business_rules.v1.md          # Archive v1
│   └── workflows/
│       └── main_workflow.md
├── architecture/
│   ├── _index.json
│   ├── patterns/
│   │   ├── service_pattern.md
│   │   └── repository_pattern.md
│   └── decisions/
│       └── tech_stack.md
├── ui_patterns/
│   ├── product_screen_layout.md
│   └── form_validation.md
└── configuration/
    └── app_settings_structure.md
```

### Format d'une entrée mémoire

```markdown
---
id: "mem_domain_workflow_001"
version: 3
created: "2026-01-15T10:00:00Z"
updated: "2026-02-02T14:30:00Z"
author: "agent:architect"
task_origin: "F001_T003"
category: "domain/workflows"
tags: ["domain", "workflow", "validation"]
supersedes: "mem_domain_workflow_001.v2"
includes_previous: true
audit_trail:
  - version: 1
    date: "2026-01-15T10:00:00Z"
    author: "agent:business-analyst"
    reason: "Initial creation"
  - version: 2
    date: "2026-01-20T15:00:00Z"
    author: "agent:developer"
    reason: "Added field mappings"
  - version: 3
    date: "2026-02-02T14:30:00Z"
    author: "agent:architect"
    reason: "Added update handling rules"
---

# Main Workflow

## Contenu actuel (v3)
### Règles de gestion des mises à jour
[Nouveau contenu ajouté en v3...]

## Contenu précédent toujours valide (v2)
### Mapping des champs
[Contenu v2 toujours applicable...]

## Contenu initial (v1) - toujours valide
### Workflow de base
[Contenu v1 toujours applicable...]
```

### Index de catégorie (_index.json)

```json
{
  "category": "domain/workflows",
  "description": "Processus et workflows métier",
  "entries": [
    {
      "id": "mem_domain_workflow_001",
      "title": "Main Workflow",
      "file": "workflow.md",
      "version": 3,
      "tags": ["workflow", "validation"]
    },
    {
      "id": "mem_domain_validation_001",
      "title": "Validation Rules",
      "file": "validation_rules.md",
      "version": 1,
      "tags": ["validation", "rules"]
    }
  ],
  "subcategories": [],
  "related_categories": ["domain/rules", "architecture/patterns"]
}
```

### Opérations sur la mémoire

**Consultation (tous les agents)**
```bash
# Rechercher dans la mémoire
./utils/memory_manager.sh search "form validation"
./utils/memory_manager.sh search --category "domain/workflows" "workflow"

# Lire une entrée
./utils/memory_manager.sh read "mem_domain_workflow_001"
./utils/memory_manager.sh read --version 2 "mem_domain_workflow_001"
```

**Contribution (agents autorisés)**
```bash
# Créer une nouvelle entrée
./utils/memory_manager.sh create \
  --category "domain/rules" \
  --title "Field Validation Rules" \
  --tags "validation,rules" \
  --author "agent:developer" \
  --task "F002_T005" \
  --file content.md

# Mettre à jour une entrée (crée nouvelle version)
./utils/memory_manager.sh update \
  --id "mem_domain_workflow_001" \
  --author "agent:architect" \
  --task "F001_T010" \
  --reason "Added update rules" \
  --include-previous true \
  --file new_content.md
```

### Intégration avec les agents

**Principe : Les agents sont autonomes pour maintenir la mémoire.**

Chaque agent reçoit dans son prompt :
```markdown
## Mémoire partagée (maintenance autonome par les agents)

Vous êtes responsable de consulter ET maintenir la mémoire partagée.

### Consultation sélective (AVANT chaque tâche)
**IMPORTANT : Ne chargez que les entrées pertinentes pour éviter de saturer le contexte.**

1. Recherchez par mots-clés liés à votre tâche :
   `./utils/memory_manager.sh search "<query>" --max-results 5`

2. Filtrez par catégorie pertinente :
   `./utils/memory_manager.sh search --category "domain/workflows" --max-results 3`

3. Lisez uniquement les entrées identifiées comme pertinentes :
   `./utils/memory_manager.sh read "<entry_id>"`

### Contribution (PENDANT/APRÈS chaque tâche)
Si vous découvrez ou apprenez quelque chose d'utile pour d'autres agents :

1. **Créer une entrée** :
   `./utils/memory_manager.sh create --category "..." --title "..." ...`

2. **Mettre à jour une entrée existante** :
   `./utils/memory_manager.sh update --id "..." --include-previous true ...`

3. **Créer une nouvelle catégorie** (si thème non existant) :
   `./utils/memory_manager.sh create-category --path "nouveau/theme" ...`

4. **Classifier une entrée inbox** :
   `./utils/memory_manager.sh move --id "..." --to-category "..." ...`

### Règles de contribution
- Créez une entrée si l'information sera utile à ≥2 autres tâches
- Préférez mettre à jour une entrée existante plutôt qu'en créer une nouvelle
- Créez une nouvelle catégorie seulement si aucune existante ne convient
- En cas de doute sur la catégorie, utilisez _inbox avec suggested-category
```

### Optimisation du contexte

**Principe : Charger UNIQUEMENT les entrées mémoire pertinentes pour la tâche.**

**Configuration (config.json) :**
```json
{
  "memory": {
    "maxEntriesPerQuery": 5,
    "maxTotalEntriesPerTask": 10,
    "summaryMode": true,
    "relevanceThreshold": 0.7
  }
}
```

**Stratégie de consultation par tâche :**

```bash
# 1. Extraire les mots-clés de la tâche
TASK_KEYWORDS=$(jq -r '.tags | join(" ")' task.json)

# 2. Recherche ciblée avec limite
./utils/memory_manager.sh search "$TASK_KEYWORDS" \
  --max-results 5 \
  --relevance-threshold 0.7

# 3. Optionnel: résumé compact (si summaryMode=true)
./utils/memory_manager.sh read "<entry_id>" --summary
```

**Modes de lecture :**

| Mode | Usage | Taille contexte |
|------|-------|-----------------|
| `--summary` | Vue d'ensemble rapide | ~100 tokens |
| `--headers` | Structure seulement | ~50 tokens |
| `--full` (défaut) | Contenu complet | Variable |
| `--section "nom"` | Section spécifique | Variable |

**Exemple - Tâche Developer :**
```bash
# Tâche: "Implémenter validation du formulaire utilisateur"

# Recherche ciblée (pas toute la mémoire)
./utils/memory_manager.sh search "form validation user" \
  --category "domain" \
  --max-results 3

# Résultats: mem_domain_validation_001, mem_ui_form_001
# Charger seulement ces 2 entrées pertinentes
```

### Responsabilités par type d'agent

| Agent | Catégories à consulter | Contribution typique |
|-------|------------------------|---------------------|
| **Business Analyst** | glossary, domain/rules | Nouvelles règles métier, définitions |
| **Architect** | architecture/*, domain/workflows | Décisions d'architecture, patterns validés |
| **Developer** | ui_patterns, architecture/patterns | Snippets réutilisables, edge cases |
| **Reviewer** | standards, best_practices, anti_patterns | Anti-patterns détectés, corrections types |
| **Tester** | test_cases, edge_cases, validation | Scénarios de test, cas limites découverts |

### Exemples de contributions autonomes

**Business Analyst découvre une règle métier :**
```bash
./utils/memory_manager.sh create \
  --category "domain/rules" \
  --title "Règle de validation formulaire" \
  --tags "validation,form,rules" \
  --author "agent:business-analyst" \
  --task "F001_T002" \
  --content "Le champ email doit contenir..."
```

**Architect crée une nouvelle catégorie :**
```bash
./utils/memory_manager.sh create-category \
  --path "architecture/security" \
  --description "Patterns de sécurité" \
  --related "architecture/patterns,domain/rules"

./utils/memory_manager.sh create \
  --category "architecture/security" \
  --title "Pattern authentification JWT" \
  ...
```

**Developer met à jour avec inclusion :**
```bash
./utils/memory_manager.sh update \
  --id "mem_ui_form_validation_001" \
  --author "agent:developer" \
  --task "F003_T015" \
  --reason "Ajout validation async pour email" \
  --include-previous true \
  --content "## Validation email async\n..."
```

**Tester classifie depuis inbox :**
```bash
./utils/memory_manager.sh move \
  --id "inbox_pending_003" \
  --to-category "domain/workflows" \
  --create-category-if-missing false
```

### Règles de versioning

1. **Création** : Version 1, pas de `supersedes`
2. **Mise à jour** :
   - Incrémenter version
   - Archiver version précédente (`entry.v{n-1}.md`)
   - Si `includes_previous: true` : inclure contenu encore valide
   - Mettre à jour `audit_trail`
3. **Consultation historique** : Toutes les versions restent accessibles

### Structure évolutive

La structure de la mémoire est **dynamique** - de nouvelles catégories peuvent être créées à tout moment.

**Processus de création de catégorie :**

```bash
# Créer une nouvelle catégorie
./utils/memory_manager.sh create-category \
  --path "architecture/security" \
  --description "Patterns de sécurité" \
  --parent "architecture" \
  --related "domain/rules"

# Créer une catégorie racine (nouveau thème)
./utils/memory_manager.sh create-category \
  --path "testing/integration" \
  --description "Tests d'intégration" \
  --related "architecture/patterns,domain/workflows"
```

**Zone de staging (inbox) :**

```
memory/
├── _inbox/                              # Entrées en attente de classification
│   ├── _index.json
│   └── pending_entry_001.md             # À classifier
├── domain/
├── architecture/
└── ...
```

Quand un agent crée une entrée mais hésite sur la catégorie :
```bash
# Créer dans inbox pour classification ultérieure
./utils/memory_manager.sh create \
  --category "_inbox" \
  --suggested-category "guarantee/???" \
  --title "Règles URDG 758" \
  --needs-classification true
```

**Commande de reclassification :**
```bash
# Déplacer une entrée vers sa catégorie finale
./utils/memory_manager.sh move \
  --id "pending_entry_001" \
  --to-category "guarantee/demand_guarantee" \
  --create-category-if-missing true
```

**Index global évolutif (_index.json) :**

```json
{
  "version": 5,
  "last_updated": "2026-02-02T15:00:00Z",
  "categories": [
    {
      "path": "domain",
      "description": "Connaissances du domaine métier",
      "entry_count": 15,
      "subcategories": ["rules", "workflows"]
    },
    {
      "path": "architecture",
      "description": "Patterns et décisions d'architecture",
      "entry_count": 23,
      "subcategories": ["patterns", "decisions"]
    },
    {
      "path": "testing",
      "description": "Stratégies et patterns de test",
      "entry_count": 8,
      "subcategories": ["unit", "integration"],
      "created": "2026-02-02T14:00:00Z",
      "created_by": "agent:architect"
    }
  ],
  "pending_classification": 2,
  "category_suggestions": [
    {
      "suggested_path": "security/authentication",
      "reason": "Multiple entries about authentication patterns",
      "suggested_by": "agent:business-analyst",
      "entries_affected": ["inbox_003", "inbox_007"]
    }
  ]
}
```

**Règles d'évolution :**

1. **Création automatique** : `--create-category-if-missing true` permet la création à la volée
2. **Inbox** : Zone temporaire pour entrées difficiles à classifier
3. **Suggestions** : Les agents peuvent suggérer de nouvelles catégories
4. **Refactoring** : Possibilité de réorganiser/fusionner des catégories
5. **Relations** : Chaque catégorie peut référencer des catégories liées

---

## Gestion des Updates

### Format des fichiers update
```
application_update_<YYMMDD:HHMM>.md
```

Exemples :
- `application_update_260202:1430.md` (02 février 2026 à 14h30)
- `application_update_260315:0900.md` (15 mars 2026 à 09h00)

### Traitement d'un update

```bash
# Traiter un fichier update spécifique
./run.sh --agent business-analyst --update 260202:1430
```

### Workflow de traitement

1. Agent Business Analyst analyse le fichier update
2. Compare avec l'état actuel des features
3. Génère :
   - Nouvelles features (si fonctionnalités ajoutées)
   - Modifications de features existantes (flag `modified: true`, `updatedFrom: "260202:1430"`)
   - Liste des tâches impactées
4. Les tâches impactées passent en `Pending` pour ré-implémentation

### Structure du fichier update
```markdown
# Application Update - 260202:1430

## Contexte
Description du contexte de la mise à jour

## Modifications

### Feature existante modifiée
- feature_001: Ajouter validation email au formulaire utilisateur

### Nouvelle feature
- Nouvelle feature: Gestion des mises à jour utilisateur

## Impact estimé
- Features impactées: feature_001, feature_003
- Nouvelles features: feature_010
```

---

## Formalisation des Tâches

### Structure complète d'une tâche atomique

```json
{
  "id": "F001_T003",
  "featureId": "feature_001",

  "title": "Ajouter le champ email au formulaire utilisateur",
  "description": "Ajouter un champ email avec validation au formulaire de création d'utilisateur",

  "type": "ui | logic | api | model | test | config | doc",

  "inputs": {
    "context": "Le formulaire utilisateur existe dans src/components/UserForm.tsx",
    "data": "Format email: RFC 5322, doit être unique",
    "references": ["feature_001/specs.md", "context/glossary.md"]
  },

  "outputs": {
    "files": ["src/components/UserForm.tsx", "src/models/User.ts"],
    "artifacts": "Champ fonctionnel avec validation",
    "lockType": "file",
    "lockTarget": "src/components/UserForm.tsx"
  },

  "acceptanceCriteria": [
    "Le champ email est visible dans le formulaire",
    "La validation refuse les emails invalides",
    "Le message d'erreur est affiché en rouge sous le champ",
    "La valeur est envoyée au backend en format valide"
  ],

  "testCriteria": {
    "unit": [
      "Test validation email invalide → erreur",
      "Test validation email valide → succès",
      "Test format email en sortie"
    ],
    "manual": [
      "Vérifier visuellement l'alignement du champ",
      "Tester le champ sur mobile"
    ]
  },

  "dependencies": {
    "tasks": ["F001_T001", "F001_T002"],
    "files": ["src/components/UserForm.tsx"],
    "external": []
  },

  "constraints": {
    "mustNotModify": ["src/api/endpoints.ts"],
    "patterns": "Utiliser le composant DatePicker existant",
    "performance": null
  },

  "complexity": "S | M | L | XL",
  "priority": "critical | high | medium | low",

  "status": "Pending",
  "statusHistory": [],

  "execution": {
    "assignedSession": null,
    "lockedAt": null,
    "startedAt": null,
    "completedAt": null,
    "attempts": 0,
    "maxRetries": 7
  },

  "notes": {
    "implementation": "",
    "errorLog": "",
    "reviewComments": ""
  }
}
```

### Description des champs

| Champ | Description |
|-------|-------------|
| **inputs.context** | État actuel du code pertinent |
| **inputs.data** | Formats, règles métier, contraintes |
| **inputs.references** | Fichiers à consulter |
| **outputs.files** | Fichiers créés/modifiés |
| **outputs.artifacts** | Résultat tangible attendu |
| **outputs.lockType** | Type de lock : `file`, `directory`, ou `pattern` |
| **outputs.lockTarget** | Cible du lock (fichier, répertoire, ou glob) |
| **acceptanceCriteria** | Conditions booléennes vérifiables (OUI/NON) |
| **testCriteria.unit** | Tests automatisables (code) |
| **testCriteria.manual** | Vérifications humaines nécessaires |
| **dependencies.tasks** | Tâches devant être `Implemented` avant |
| **dependencies.files** | Fichiers qui doivent exister |
| **dependencies.external** | APIs, services tiers |
| **constraints.mustNotModify** | Fichiers interdits de modification |
| **constraints.patterns** | Conventions à respecter |
| **constraints.performance** | Limites (temps, mémoire) |

### Échelle de complexité (T-shirt sizing)

| Taille | Description |
|--------|-------------|
| **S** | < 30 lignes, 1 fichier |
| **M** | 30-100 lignes, 1-2 fichiers |
| **L** | 100-300 lignes, 2-4 fichiers |
| **XL** | Trop gros → **à redécomposer** |

### Règles de validation d'une tâche

Une tâche est **bien formée** si :
- ☐ Title est un verbe d'action ("Ajouter", "Implémenter", "Corriger")
- ☐ Au moins 2 acceptance criteria
- ☐ Au moins 1 test criteria (unit ou manual)
- ☐ outputs.files est non vide
- ☐ complexity ≠ XL (sinon décomposer)
- ☐ Pas de dépendance circulaire

### Exemple générique

```json
{
  "id": "F002_T005",
  "featureId": "feature_002_user_management",
  "title": "Implémenter la validation du quota utilisateur",
  "description": "Vérifier que l'utilisateur n'a pas dépassé son quota d'utilisation",

  "type": "logic",

  "inputs": {
    "context": "Le quota utilisateur est stocké dans user.usageQuota",
    "data": "Usage actuel et limite configurée",
    "references": ["context/glossary.md#usage-quota"]
  },

  "outputs": {
    "files": ["src/services/validation/quotaValidator.ts"],
    "artifacts": "Fonction validateUserQuota(userId, requestedUsage)"
  },

  "acceptanceCriteria": [
    "Retourne true si usage ≤ quota",
    "Retourne false avec message d'erreur si usage > quota",
    "Gère le cas où quota est null (pas de limite)",
    "Supporte les quotas par période (jour/mois)"
  ],

  "testCriteria": {
    "unit": [
      "Test usage < quota → true",
      "Test usage = quota → true",
      "Test usage > quota → false + message",
      "Test quota null → true",
      "Test reset quotidien"
    ],
    "manual": []
  },

  "dependencies": {
    "tasks": ["F002_T003"],
    "files": ["src/services/user/userService.ts"],
    "external": []
  },

  "constraints": {
    "mustNotModify": [],
    "patterns": "Utiliser le QuotaCalculator existant",
    "performance": "< 100ms par validation"
  },

  "complexity": "M",
  "priority": "high",
  "status": "Pending"
}
```

---

## Fichiers critiques à implémenter

### Configuration
1. `config.json` (configuration du framework)

### Schémas JSON
2. `schemas/feature.schema.json`
3. `schemas/task.schema.json`
4. `schemas/lock.schema.json`

### Agents (à créer)
5. `agents/business-analyst.md` - **Nouveau** : Décompose application → features
6. `agents/architect-task-decompose.md` - **Nouveau** : Prompt pour code-architect
7. `agents/developer.md` - **Nouveau** : Implémente les tâches
8. `agents/reviewer-prompt.md` - **Nouveau** : Prompt pour code-reviewer (existant)
9. `agents/tester-prompt.md` - **Nouveau** : Prompt pour pr-test-analyzer (existant)

### Scripts d'orchestration
10. `run.sh` - **Script principal** avec modes d'exécution
11. `scripts/ralph_wiggum_task.sh` (boucle d'exécution par tâche)
12. `scripts/run_feature_tasks.sh` (orchestration parallèle)

### Utilitaires
13. `utils/lock_manager.sh`
14. `utils/status_updater.sh`
15. `utils/memory_manager.sh` - **Nouveau** : Gestion mémoire partagée

### Schémas mémoire
16. `schemas/memory_entry.schema.json`
17. `schemas/memory_index.schema.json`

### Fichiers de suivi
18. `status.json` (template initial)
19. `CLAUDE.md` (instructions globales pour les sessions)

---

## Vérification

1. Créer un `application.md` de test minimal
2. Lancer la session master → vérifier génération features
3. Lancer sessions feature → vérifier génération tasks
4. Lancer 2 sessions impl en parallèle → vérifier locks fonctionnels
5. Simuler une erreur → vérifier statut Error et libération lock
6. Créer un update → vérifier détection des changements

---

## Décisions prises

- [x] Durée d'expiration des locks : **60 minutes**
- [x] Stratégie de retry : **Boucle Ralph Wiggum par tâche** (max retries configurable)
- [x] Pattern d'exécution : Une boucle dédiée par tâche atomique
- [x] Intégration Git : **1 commit par tâche** (granularité fine, rollback facile)
- [x] Parallélisme : **Configurable** via `config.json` (défaut: 3)
- [x] Max itérations Ralph Wiggum : **Configurable** via `config.json` (défaut: 7)
- [x] Locks multi-niveaux : **file**, **directory**, **pattern**
- [x] Types d'agents : **Approche hybride** (réutiliser existants + créer nouveaux)
  - Business Analyst : **À créer**
  - Architect : **Existant** (code-architect)
  - Developer : **À créer**
  - Reviewer : **Existant** (code-reviewer)
  - Tester : **Existant** (pr-test-analyzer)
- [x] Sessions isolées : **Chaque agent = nouvelle session Claude CLI**
- [x] Format updates : `application_update_<YYMMDD:HHMM>.md`
- [x] Modes d'exécution : **Pipeline complet** OU **Agent individuel**
  - `--full` : tout le pipeline
  - `--agent <name>` : agent spécifique
  - `--feature` / `--task` : ciblage granulaire
- [x] Mémoire partagée : **Hiérarchique, versionnée et évolutive**
  - Structure multi-niveaux par domaine métier
  - **Maintenance autonome par les agents** (pas d'intervention manuelle)
  - Versioning avec historique pour audit
  - Inclusion cumulative du contenu précédent valide
  - **Structure évolutive** : nouvelles catégories créées par les agents
  - **Zone _inbox** : staging pour entrées à classifier par les agents
  - **Consultation sélective** : uniquement entrées pertinentes (max configurable)
  - Modes de lecture : `--summary`, `--headers`, `--full`, `--section`
- [x] Modèles LLM : **Configurable par agent**
  - Business Analyst / Architect : **Claude Opus 4.5** (défaut)
  - Developer / Reviewer / Tester : **Claude Sonnet 4.5** (défaut)
  - Override possible via `--model` ou `config.json`
- [x] Gestion quotas (Plan Max) : **Session Claude Code orchestratrice**
  - Claude Code comme orchestrateur (visibilité native sur quota)
  - Stratégies adaptatives selon niveau de quota
  - Mode économique (Sonnet) si quota bas
  - Gestion intelligente des interruptions
