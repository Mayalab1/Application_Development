# Framework d'Orchestration Multi-Sessions Claude CLI

## Vue d'ensemble rapide

Ce framework décompose une application en **features** puis en **tâches atomiques**, exécutées par des sessions Claude CLI indépendantes.

```
application.md → [Business Analyst] → features/*.json
                                           ↓
                        [Architect] → tasks.json (par feature)
                                           ↓
                        [Developer] → Code implémenté
                                           ↓
                        [Reviewer]  → Code reviewé
                                           ↓
                        [Tester]    → Code testé + commit
```

---

## Structure du projet

```
project_root/
├── FRAMEWORK.md          # ← VOUS ÊTES ICI - Notice de fonctionnement
├── CLAUDE.md             # Instructions globales pour Claude
├── run.sh                # Script principal d'orchestration
├── config.json           # Configuration du framework
├── application.md        # Description de l'application (à créer)
├── application_template.md # Template pour créer application.md
├── status.json           # État global du projet
│
├── context/              # Contexte partagé
│   ├── architecture.md
│   ├── conventions.md
│   └── glossary.md
│
├── features/             # Features décomposées
│   ├── feature_001_xxx/
│   │   ├── feature.json
│   │   └── tasks.json
│   └── feature_002_yyy/
│       └── ...
│
├── memory/               # Mémoire partagée hiérarchique
│   ├── _index.json
│   ├── _inbox/
│   └── [catégories]/
│
├── agents/               # Prompts des agents
│   ├── business-analyst.md
│   ├── architect-task-decompose.md
│   ├── developer.md
│   ├── reviewer-prompt.md
│   └── tester-prompt.md
│
├── schemas/              # Schémas JSON de validation
│   ├── feature.schema.json
│   ├── task.schema.json
│   ├── lock.schema.json
│   └── ...
│
├── scripts/              # Scripts d'orchestration
│   ├── ralph_wiggum_task.sh
│   └── run_feature_tasks.sh
│
├── utils/                # Utilitaires
│   ├── lock_manager.sh
│   ├── status_updater.sh
│   ├── memory_manager.sh
│   ├── check_dependencies.sh
│   ├── quality_check.sh
│   └── archive_run.sh
│
├── locks/                # Gestion des locks
├── logs/                 # Logs et archives
├── application_generated/                  # Code source généré
│
└── .claude/              # Configuration Claude Code
    └── commands/         # Skills slash commands
        ├── ba.md         # /ba - Business Analyst
        ├── architect.md  # /architect - Architect
        ├── dev.md        # /dev - Developer
        ├── review.md     # /review - Reviewer
        └── test.md       # /test - Tester
```

---

## Créer application.md

Le fichier `application.md` est le point d'entrée du pipeline. Il décrit l'application à développer et sera analysé par le Business Analyst pour être décomposé en features.

### Création

```bash
# Copier le template
cp application_template.md application.md

# Éditer avec votre description
vim application.md  # ou votre éditeur préféré
```

### Sections obligatoires

| Section | Minimum requis | Description |
|---------|----------------|-------------|
| **Introduction** | 3 lignes | Contexte, problème et solution |
| **Goals** | 3 objectifs | Mesurables et spécifiques |
| **User Stories** | 3 US | Format "En tant que... je veux... afin de..." |
| **Functional Requirements** | 3 FR | Exigences explicites |
| **Non-Goals** | 3 items | Ce que le projet ne fera PAS |

### Format des User Stories

```markdown
### US-001: [Titre court]
- **Description** : En tant que [rôle], je veux [action] afin de [bénéfice]
- **Critères d'acceptation** :
  - Critère 1 (vérifiable)
  - Critère 2 (vérifiable)
- **Priorité** : Haute/Moyenne/Basse
```

### Section Non-Goals

La section Non-Goals est **critique** pour éviter le scope creep. Elle définit explicitement ce que le projet ne fera PAS, même si cela pourrait sembler utile.

Exemples :
- ❌ Support multi-langue (v1 en français uniquement)
- ❌ Application mobile native (web responsive suffit)
- ❌ Intégration avec systèmes legacy

### Conseils pour une bonne description

1. **Soyez spécifique** : évitez les termes vagues comme "interface intuitive"
2. **Utilisez des verbes d'action** : "Le système doit afficher..." plutôt que "Une interface de..."
3. **Définissez les limites** : les Non-Goals sont aussi importants que les Goals
4. **Listez les questions ouvertes** : les points non résolus permettent au BA de poser les bonnes questions

---

## Commandes principales

### Pipeline complet
```bash
./run.sh --full
```
Exécute tout le pipeline : Business Analyst → Architect → Developer → Reviewer → Tester

### Agents individuels

```bash
# Business Analyst - Décompose application.md en features
./run.sh --agent business-analyst
./run.sh --agent business-analyst --update 260202:1430  # Traite un update

# Architect - Décompose features en tâches
./run.sh --agent architect                              # Toutes les features
./run.sh --agent architect --feature feature_001       # Une feature

# Developer - Implémente les tâches
./run.sh --agent developer                             # Toutes les tâches Pending
./run.sh --agent developer --task F001_T003            # Une tâche
./run.sh --agent developer --feature feature_001      # Tâches d'une feature

# Reviewer - Review le code
./run.sh --agent reviewer --task F001_T003

# Tester - Teste les acceptance criteria
./run.sh --agent tester --task F001_T003
```

### Options communes
```bash
--config <file>     # Fichier de configuration alternatif
--model <model>     # Override du modèle LLM
--ignore-quota      # Ignorer les vérifications de quota
--resume-interrupted # Reprendre les tâches interrompues
```

---

## Cycle de vie d'une tâche

```
Pending → InProgress → Implemented → Reviewed → Tested → [Commit]
              ↓
          Interrupted → (auto-resume)
              ↓
           Error → Pending (retry)
```

### États possibles
| État | Description |
|------|-------------|
| `Pending` | En attente d'exécution |
| `InProgress` | En cours d'implémentation |
| `Implemented` | Code écrit, en attente de review |
| `Reviewed` | Review passée, en attente de tests |
| `Tested` | Tests passés, prêt pour commit |
| `Interrupted` | Session interrompue (quota/crash) |
| `Error` | Échec après max retries |
| `Blocked` | Bloquée par dépendance |

---

## Rôles des agents

### Business Analyst
- **Input** : `application.md`
- **Output** : `features/*.json`
- **Responsabilité** : Décomposer l'application en features fonctionnelles
- **IMPORTANT** : Doit poser 3-5 questions de clarification AVANT de décomposer

### Architect
- **Input** : `feature_XXX.json`
- **Output** : `tasks.json`
- **Responsabilité** : Décomposer chaque feature en tâches atomiques
- **Règle** : Si une tâche ne peut être décrite en 2-3 phrases, la subdiviser

### Developer
- **Input** : Tâche depuis `tasks.json`
- **Output** : Code implémenté
- **Responsabilité** : Implémenter UNE tâche atomique
- **Signal de fin** : Émettre `<promise>COMPLETE</promise>` quand terminé

### Reviewer
- **Input** : Code implémenté
- **Output** : Validation ou demande de corrections
- **Responsabilité** : Vérifier qualité, patterns, sécurité

### Tester
- **Input** : Code reviewé
- **Output** : Résultats des tests
- **Responsabilité** : Valider les acceptance criteria

---

## Règles critiques

### Pour TOUS les agents

1. **Sessions isolées** : Chaque invocation = nouvelle session sans mémoire
2. **Contexte via fichiers** : Lire les fichiers du projet pour comprendre l'état
3. **Signal COMPLETE** : Toujours signaler explicitement la fin
   ```
   <promise>COMPLETE</promise>
   ```
4. **Si bloqué** : Signaler avec raison
   ```
   <promise>BLOCKED: [raison]</promise>
   ```

### Acceptance Criteria obligatoires

Chaque tâche DOIT inclure selon son type :
- **Toutes** : "✓ Typecheck passes"
- **Avec logique** : + "✓ Tests passent"
- **UI** : + "✓ Vérifier visuellement dans le navigateur"

### Quality checks avant commit

Le commit est bloqué si :
- ❌ Typecheck échoue
- ❌ Lint échoue
- ❌ Tests échouent

---

## Gestion des locks (autonomie LLM)

**Vous décidez** quel niveau de lock acquérir selon votre analyse.

### Types de locks
| Type | Usage |
|------|-------|
| `file` | Modification d'un seul fichier existant |
| `directory` | Création de fichiers ou modifications multiples |
| `pattern` | Fichiers liés (ex: `*.test.ts`) |

### Acquisition (votre responsabilité)
```bash
./utils/lock_manager.sh acquire --type <type> --target "<path>" --task "$TASK_ID"
```

### Comportement
- Expiration après 60 minutes
- Libération automatique en fin de session

### En cas de conflit
Signaler `<promise>BLOCKED: Lock conflict</promise>` et passer à une autre tâche.

---

## Mémoire partagée (chargement autonome)

**Vous décidez** quelles entrées mémoire charger selon votre tâche.

### Découverte
```bash
# Voir les catégories disponibles
cat memory/_index.json | jq '.categories[].path'

# Rechercher par mots-clés
./utils/memory_manager.sh search "form validation"
```

### Consultation
```bash
./utils/memory_manager.sh read "mem_domain_workflow_001"
./utils/memory_manager.sh read "..." --summary  # Vue rapide
```

### Contribution
Si vous découvrez une information utile pour d'autres agents :
```bash
./utils/memory_manager.sh create \
  --category "domain/rules" \
  --title "Règle métier découverte" \
  --content "..."
```

---

## Fichiers CONTEXT.md distribués (multi-LLM)

Chaque répertoire peut avoir un `CONTEXT.md` local avec :
- Patterns spécifiques au module
- Gotchas à éviter
- Dépendances entre fichiers

**Chargement autonome** : Vous décidez quels CONTEXT.md charger.
```bash
# Découvrir les CONTEXT.md existants
find application_generated/ -name "CONTEXT.md" -type f

# Lire ceux pertinents pour votre tâche
cat application_generated/components/CONTEXT.md
```

---

## Gestion des quotas

| Niveau | Action |
|--------|--------|
| > 30% | Mode normal |
| 10-30% | Mode économique (tâches prioritaires seulement) |
| < 10% | Pause et sauvegarde état |
| 0% | Arrêt complet |

Les modèles configurés sont TOUJOURS respectés (pas de bascule automatique).

---

## Boucle Ralph Wiggum

Chaque tâche s'exécute dans une boucle de retry :

```
Tentative 1 → Échec → Tentative 2 → ... → Tentative 7 → Error
                 ↓
              Succès → Review → Test → Quality Check → Commit
```

- Max 7 tentatives par défaut (configurable)
- Délai de 10 secondes entre tentatives

---

## Checklist avant de commencer

En tant que nouvelle session LLM, vérifiez :

1. ☐ Lire ce fichier `FRAMEWORK.md`
2. ☐ Lire `CLAUDE.md` (instructions spécifiques)
3. ☐ Vérifier `status.json` (état global)
4. ☐ Identifier votre rôle (quel agent êtes-vous ?)
5. ☐ Lire la tâche assignée dans `tasks.json`
6. ☐ Consulter la mémoire partagée si pertinent
7. ☐ Vérifier les locks avant modification

---

## Configuration

Le fichier `config.json` contient tous les paramètres configurables :

| Paramètre | Description | Défaut |
|-----------|-------------|--------|
| `maxParallelSessions` | Sessions d'implémentation simultanées | 3 |
| `ralphWiggum.maxRetries` | Tentatives max par tâche | 7 |
| `models.business-analyst` | Modèle pour BA | claude-opus-4-5 |
| `models.developer` | Modèle pour Developer | claude-sonnet-4-5 |
| `pipeline.reviewerEnabled` | Activer le Reviewer | true |
| `pipeline.testerEnabled` | Activer le Tester | true |
| `locks.expirationMinutes` | Durée d'expiration des locks | 60 |
| `git.autoCommit` | Commit auto après tâche | true |
| `qualityChecks.enabled` | Quality checks activés | true |

---

## Skills Claude Code

Le framework fournit des slash commands pour invoquer chaque agent directement dans Claude Code.

### Commandes disponibles

| Skill | Usage | Description |
|-------|-------|-------------|
| `/ba` | `/ba` ou `/ba --update 260202:1430` | Business Analyst - Décompose application.md en features |
| `/architect` | `/architect` ou `/architect --feature feature_001` | Architect - Décompose features en tâches |
| `/dev` | `/dev --task F001_T003` | Developer - Implémente une tâche |
| `/review` | `/review --task F001_T003` | Reviewer - Review le code |
| `/test` | `/test --task F001_T003` | Tester - Valide les acceptance criteria |

### Exemples d'utilisation

```bash
# Démarrer l'analyse d'une nouvelle application
/ba

# Traiter une mise à jour de l'application
/ba --update 260202:1430

# Décomposer une feature spécifique en tâches
/architect --feature feature_001_user_auth

# Pipeline complet pour une tâche
/dev --task F001_T003
/review --task F001_T003
/test --task F001_T003
```

### Workflow Learnings

Chaque agent doit documenter systématiquement ses découvertes dans `notes.implementation` (append-only). Format recommandé :

```markdown
---
[Date] - [Task ID]
Résumé: Brève description du travail effectué
Fichiers modifiés: liste des fichiers
Learnings:
- Patterns codebase: conventions découvertes, structures récurrentes
- Gotchas: pièges évités, comportements inattendus
- Dépendances: relations entre fichiers découvertes
---
```

---

## Exemple de workflow complet

```bash
# 1. Créer application.md à partir du template
cp application_template.md application.md
vim application.md  # Compléter avec votre description

# 2. Décomposition en features (via CLI ou skill)
./run.sh --agent business-analyst
# ou: /ba

# 3. Décomposition en tâches (toutes les features)
./run.sh --agent architect
# ou: /architect

# 4. Implémentation parallèle (3 sessions max)
./run.sh --agent developer
# ou pour une tâche: /dev --task F001_T003

# 5. Vérifier le status
cat status.json | jq '.features[] | {id, status}'

# 6. Reprendre les tâches interrompues
./run.sh --resume-interrupted

# 7. Générer un rapport de progression
./utils/status_updater.sh report
```

---

## Utilitaires disponibles

### Lock Manager
```bash
./utils/lock_manager.sh acquire <task_id> <feature_dir>
./utils/lock_manager.sh release <task_id>
./utils/lock_manager.sh check <file_path>
./utils/lock_manager.sh list
./utils/lock_manager.sh cleanup
```

### Status Updater
```bash
./utils/status_updater.sh set_status <task_id> <status> [reason]
./utils/status_updater.sh get_status <task_id>
./utils/status_updater.sh update_feature <feature_id>
./utils/status_updater.sh report
```

### Memory Manager
```bash
./utils/memory_manager.sh search <query>
./utils/memory_manager.sh read <entry_id>
./utils/memory_manager.sh list
./utils/memory_manager.sh create --category <cat> --title <t> ...
./utils/memory_manager.sh update --id <id> --author <a> ...
```

### Quality Check
```bash
./utils/quality_check.sh <task_id>
```

### Archive Run
```bash
./utils/archive_run.sh <feature_id>
```

### Check Dependencies
```bash
./utils/check_dependencies.sh [dependencies.json]
```

---

## Support et dépannage

### Logs
Les logs de session sont dans `logs/sessions/`.

### Archives
Les archives par feature sont dans `logs/archives/`.

### Locks bloqués
```bash
# Nettoyer les locks expirés
./utils/lock_manager.sh cleanup

# Forcer la libération d'un lock
./utils/lock_manager.sh release <task_id>
```

### Tâches interrompues
```bash
./run.sh --resume-interrupted
```
