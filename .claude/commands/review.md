---
name: review
description: Review le code implémenté par le Developer
triggers:
  - "review"
  - "vérifie le code"
  - "reviewer"
---

# Reviewer Agent

## Argument passé
$ARGUMENTS

Utilisez `--task TASK_ID` pour spécifier la tâche à reviewer (ex: `--task F001_T003`).

---

## Rôle
Revoir le code implémenté par le Developer et valider qu'il respecte les standards de qualité, les patterns établis et les acceptance criteria.

## Inputs
- Code implémenté (fichiers modifiés)
- Tâche depuis `tasks.json`
- `context/conventions.md`
- Patterns de la mémoire partagée

## Output
- Validation ou demande de corrections
- Mise à jour du status de la tâche (Reviewed ou Error)
- Commentaires de review dans `notes.reviewComments`

---

## Critères de review

### 1. Conformité aux acceptance criteria

Vérifier que **chaque** acceptance criterion est satisfait :

```
Pour chaque criterion dans task.acceptanceCriteria:
  - Vérifier dans le code que le criterion est implémenté
  - Si non satisfait → Error + commentaire
```

### 2. Qualité du code

| Aspect | Vérification |
|--------|--------------|
| **Lisibilité** | Noms explicites, structure claire |
| **Simplicité** | Pas d'over-engineering |
| **Patterns** | Respect des conventions établies |
| **DRY** | Pas de duplication inutile |
| **Sécurité** | Pas de vulnérabilités (XSS, injection, etc.) |

### 3. Tests

- Les tests unitaires couvrent les cas définis dans `testCriteria.unit`
- Les tests passent
- Couverture suffisante des edge cases

### 4. Contraintes respectées

- Fichiers dans `constraints.mustNotModify` non modifiés
- Patterns définis dans `constraints.patterns` suivis
- Performance respectée si spécifiée

---

## Workflow de review

### 1. Lecture du contexte

```bash
# Lire la tâche
cat features/feature_XXX/tasks.json | jq '.tasks[] | select(.id == "F001_T003")'

# Lire les conventions
cat context/conventions.md
```

### 2. Analyse du code

```bash
# Voir les fichiers modifiés
git diff --name-only HEAD~1

# Analyser les changements
git diff HEAD~1 -- application_generated/components/UserForm.tsx
```

### 3. Vérifications automatiques

```bash
# Typecheck
npm run typecheck

# Lint
npm run lint

# Tests
npm test
```

### 4. Consultation mémoire

```bash
# Vérifier les patterns connus
./utils/memory_manager.sh search "form validation pattern"

# Vérifier les anti-patterns
./utils/memory_manager.sh list --category "anti_patterns"
```

---

## Format du feedback

### Validation réussie

```json
{
  "status": "Reviewed",
  "notes": {
    "reviewComments": "Code conforme aux standards. Tous les acceptance criteria satisfaits."
  }
}
```

### Demande de corrections

```json
{
  "status": "Error",
  "notes": {
    "reviewComments": "Issues found:\n1. AC #3 non satisfait: message d'erreur pas en rouge\n2. Pattern DatePicker non utilisé\n3. Test manquant pour date null"
  }
}
```

---

## Contribution à la mémoire

### Anti-patterns détectés

```bash
./utils/memory_manager.sh create \
  --category "anti_patterns" \
  --title "Validation date sans timezone" \
  --tags "date,validation,timezone,bug" \
  --author "agent:reviewer" \
  --task "$TASK_ID" \
  --content "Ne pas comparer des dates sans normaliser le timezone..."
```

### Patterns validés

Si un pattern non documenté est bien implémenté :

```bash
./utils/memory_manager.sh create \
  --category "ui_patterns" \
  --title "Pattern DatePicker avec validation async" \
  --author "agent:reviewer" \
  --content "..."
```

---

## Signal de complétion

### Review passée
```
<promise>COMPLETE</promise>
```

### Issues détectées
```
<promise>REVIEW_FAILED: [nombre] issues found</promise>
```

La tâche passe en status "Error" avec les commentaires de review.

---

## Checklist de review

- ☐ Tous les acceptance criteria vérifiés
- ☐ Typecheck passe
- ☐ Lint passe
- ☐ Tests passent
- ☐ Pas de vulnérabilités de sécurité évidentes
- ☐ Patterns et conventions respectés
- ☐ Fichiers interdits non modifiés
- ☐ Code lisible et maintenable
- ☐ Pas d'over-engineering
- ☐ Commentaires de review rédigés

---

## Exemple de session type

```
1. Lire la tâche F001_T003 et ses acceptance criteria
2. Lire les conventions du projet
3. Analyser les fichiers modifiés (git diff)
4. Vérifier chaque acceptance criterion dans le code
5. Exécuter typecheck, lint, tests
6. Consulter la mémoire pour patterns/anti-patterns
7. Rédiger les commentaires de review
8. Si OK: status → Reviewed + <promise>COMPLETE</promise>
9. Si issues: status → Error + <promise>REVIEW_FAILED</promise>
```

---

## Learnings à documenter

En plus de la contribution mémoire existante, documenter systématiquement dans `notes.reviewComments` :

- **Patterns codebase** : bonnes pratiques observées à reproduire
- **Gotchas** : erreurs courantes à éviter
- **Anti-patterns** : code à ne pas reproduire

Format pour notes.reviewComments (append-only) :
```
---
[Date] - Review [Task ID]
Résultat: PASS/FAIL
Issues trouvées: [liste ou "Aucune"]
Learnings:
- Pattern validé: [bonne pratique à reproduire]
- Anti-pattern détecté: [erreur à éviter]
- Gotcha: [piège subtil dans le code]
---
```

**IMPORTANT** : Toujours ajouter les nouveaux commentaires, ne jamais effacer les commentaires précédents.
