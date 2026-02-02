# Instructions pour les sessions Claude CLI

Ce fichier contient les instructions globales pour toutes les sessions Claude CLI du framework d'orchestration multi-sessions.

## Contexte du projet

Ce framework décompose une application (décrite dans `application.md`) en features, puis en tâches atomiques, implémentées par des sessions Claude CLI indépendantes.

## Fichiers de référence importants

- `FRAMEWORK.md` - Notice détaillée de fonctionnement du framework
- `config.json` - Configuration du framework
- `status.json` - État global du projet
- `context/` - Contexte partagé (architecture, conventions, glossaire)
- `memory/` - Mémoire partagée hiérarchique

## Règles fondamentales

### Sessions isolées
Chaque invocation d'agent est une nouvelle session sans mémoire des sessions précédentes. Le contexte doit être reconstruit à partir des fichiers du projet.

### Signal de complétion
Toujours signaler explicitement la fin du travail :
```
<promise>COMPLETE</promise>
```

Si bloqué :
```
<promise>BLOCKED: [raison]</promise>
```

### Autonomie LLM
Les agents sont responsables de :
- Découvrir et charger les fichiers CONTEXT.md pertinents
- Consulter et contribuer à la mémoire partagée
- Évaluer si une dépendance est réellement bloquante
- Décider du niveau de lock approprié
- Évaluer si une tâche est trop complexe

### Quality checks
Le code doit passer les vérifications avant commit :
- Typecheck
- Lint
- Tests

## Conventions

### Nommage des features
Format : `feature_XXX_description_courte`

### Nommage des tâches
Format : `FXXX_TXXX` (ex: F001_T003)

### Commits
Un commit par tâche avec le format :
```
feat(F001_T003): Titre de la tâche

Co-Authored-By: Claude <noreply@anthropic.com>
```

## Mémoire partagée

### Consultation
```bash
./utils/memory_manager.sh search "query"
./utils/memory_manager.sh read "entry_id"
```

### Contribution
```bash
./utils/memory_manager.sh create --category "..." --title "..." --author "agent:developer" --content "..."
```

## Fichiers CONTEXT.md

Chaque répertoire peut avoir un fichier `CONTEXT.md` contenant :
- Patterns spécifiques au module
- Gotchas à éviter
- Dépendances entre fichiers

## Commandes utiles

```bash
# Voir le status global
cat status.json | jq '.'

# Voir les tâches d'une feature
cat features/feature_001_xxx/tasks.json | jq '.tasks[] | {id, title, status}'

# Voir les locks actifs
./utils/lock_manager.sh list

# Générer un rapport de progression
./utils/status_updater.sh report
```
