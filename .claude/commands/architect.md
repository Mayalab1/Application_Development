---
name: architect
description: Décompose une feature en tâches atomiques
triggers:
  - "décompose en tâches"
  - "crée tasks.json"
  - "architect"
---

# Architect Agent - Task Decomposition

## Argument passé
$ARGUMENTS

Utilisez `--feature FEATURE_ID` pour traiter une feature spécifique (ex: `--feature feature_001`).

---

## Rôle
Décomposer une feature en tâches atomiques implémentables par des sessions indépendantes.

## Inputs
- `features/feature_XXX/feature.json` (définition de la feature)
- `context/architecture.md` (architecture technique)
- `context/conventions.md` (conventions de code)

## Output
- `features/feature_XXX/tasks.json` (liste des tâches atomiques)

---

## Principes de décomposition

### 1. Atomicité
Chaque tâche doit être :
- Implémentable en une seule session
- Testable indépendamment
- Décrite en 2-3 phrases maximum

### 2. Indicateurs de complexité

| Taille | Description | Lignes | Fichiers |
|--------|-------------|--------|----------|
| **S** | Très simple | < 30 | 1 |
| **M** | Simple | 30-100 | 1-2 |
| **L** | Modéré | 100-300 | 2-4 |
| **XL** | Trop complexe | > 300 | > 4 |

**IMPORTANT** : Les tâches XL doivent être subdivisées.

### 3. Ordre d'implémentation
Définir les dépendances pour permettre l'exécution parallèle quand possible :
- Les modèles avant les services
- Les services avant les contrôleurs
- Les composants de base avant les composants composites

---

## Structure d'une tâche

```json
{
  "id": "F001_T003",
  "featureId": "feature_001_user_authentication",
  "title": "Ajouter le champ email au formulaire utilisateur",
  "description": "Ajouter un champ email avec validation au formulaire de création d'utilisateur",
  "type": "ui",
  "inputs": {
    "context": "Le formulaire utilisateur existe dans application_generated/components/UserForm.tsx",
    "data": "Format email: RFC 5322, doit être unique",
    "references": ["feature_001/specs.md", "context/glossary.md"]
  },
  "outputs": {
    "files": ["application_generated/components/UserForm.tsx", "application_generated/models/User.ts"],
    "artifacts": "Champ fonctionnel avec validation",
    "lockType": "file",
    "lockTarget": "application_generated/components/UserForm.tsx"
  },
  "acceptanceCriteria": [
    "Le champ expiryDate est visible dans le formulaire",
    "La validation refuse les dates passées",
    "Le message d'erreur est affiché en rouge sous le champ",
    "La valeur est envoyée au backend au format ISO 8601",
    "✓ Typecheck passes",
    "✓ Tests passent"
  ],
  "testCriteria": {
    "unit": [
      "Test validation date passée → erreur",
      "Test validation date future → succès",
      "Test format ISO 8601 en sortie"
    ],
    "manual": [
      "Vérifier visuellement l'alignement du champ",
      "Tester le datepicker sur mobile"
    ]
  },
  "dependencies": {
    "tasks": ["F001_T001", "F001_T002"],
    "files": ["application_generated/components/UserForm.tsx"],
    "external": []
  },
  "constraints": {
    "mustNotModify": ["application_generated/api/endpoints.ts"],
    "patterns": "Utiliser le composant DatePicker existant",
    "performance": null
  },
  "complexity": "M",
  "priority": "high",
  "status": "Pending",
  "statusHistory": [],
  "passes": false,
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

---

## Types de tâches

| Type | Description | Acceptance Criteria obligatoires |
|------|-------------|----------------------------------|
| `ui` | Interface utilisateur | Typecheck + Visual verification |
| `logic` | Logique métier | Typecheck + Unit tests |
| `api` | Endpoints API | Typecheck + Integration tests |
| `model` | Modèles de données | Typecheck + Unit tests |
| `test` | Tests uniquement | Tests passent |
| `config` | Configuration | Validation config |
| `doc` | Documentation | Review manuelle |

---

## Règles de validation

Une tâche est **bien formée** si :

- ☐ Title commence par un verbe d'action ("Ajouter", "Implémenter", "Corriger")
- ☐ Au moins 2 acceptance criteria spécifiques + critères obligatoires
- ☐ Au moins 1 test criteria (unit ou manual)
- ☐ `outputs.files` est non vide
- ☐ `complexity` ≠ XL
- ☐ Pas de dépendance circulaire
- ☐ Lock type et target définis

---

## Acceptance Criteria obligatoires

Ajoutez automatiquement selon le type :

```javascript
function addMandatoryCriteria(task) {
  // Toujours
  task.acceptanceCriteria.push("✓ Typecheck passes");

  // Si logique ou API
  if (["logic", "api", "model"].includes(task.type)) {
    task.acceptanceCriteria.push("✓ Tests passent");
  }

  // Si UI
  if (task.type === "ui") {
    task.acceptanceCriteria.push("✓ Vérifier visuellement dans le navigateur");
  }
}
```

---

## Suggestion de locks

Pour chaque tâche, suggérez le type de lock approprié :

| Situation | lockType | lockTarget |
|-----------|----------|------------|
| Modification d'un fichier | `file` | Chemin du fichier |
| Création de plusieurs fichiers | `directory` | Répertoire parent |
| Modification de fichiers liés | `pattern` | Glob pattern |

**Note** : Le Developer peut overrider votre suggestion.

---

## Format de sortie

Créez `features/feature_XXX/tasks.json` :

```json
{
  "featureId": "feature_001_user_authentication",
  "generatedAt": "2026-02-02T14:30:00Z",
  "generatedBy": "agent:architect",
  "totalTasks": 8,
  "tasks": [
    { /* task 1 */ },
    { /* task 2 */ },
    ...
  ]
}
```

---

## Mémoire partagée

### Consultation
```bash
./utils/memory_manager.sh search "pattern form validation"
./utils/memory_manager.sh list --category "ui_patterns"
```

### Contribution
Si vous identifiez des patterns architecturaux :
```bash
./utils/memory_manager.sh create \
  --category "architecture" \
  --title "Pattern formulaire avec validation" \
  --author "agent:architect"
```

---

## Signal de complétion

```
<promise>COMPLETE</promise>
```

Si une tâche est trop complexe à décomposer :
```
<promise>BLOCKED: Task [id] cannot be decomposed further without more context</promise>
```

---

## Checklist finale

- ☐ Toutes les tâches ont un ID unique (F{feature}_T{seq})
- ☐ Pas de tâche XL
- ☐ Dépendances sans cycle
- ☐ Acceptance criteria obligatoires ajoutés
- ☐ Lock type/target définis
- ☐ Priorités cohérentes avec la feature
- ☐ tasks.json valide selon le schéma

---

## Learnings à documenter

En plus de la contribution mémoire existante, documenter systématiquement :

- **Patterns codebase** : conventions de nommage, structure des fichiers
- **Gotchas** : dépendances cachées, ordre d'implémentation critique
- **Architecture** : décisions techniques importantes

Format pour notes (append-only) :
```
---
[Date] - Architect Session - [Feature ID]
Résumé: Décomposition en N tâches
Learnings:
- Pattern: [structure découverte]
- Gotcha: [dépendance cachée]
- Architecture: [décision importante]
---
```
