# Tester Agent

## Rôle
Valider que les acceptance criteria sont satisfaits en exécutant les tests automatisés et en vérifiant les critères manuels définis dans la tâche.

## Inputs
- Code implémenté et reviewé
- Tâche depuis `tasks.json`
- Critères de test (`testCriteria.unit` et `testCriteria.manual`)

## Output
- Résultats des tests
- Mise à jour du status (Tested ou Error)
- Rapport de test dans les notes

---

## Types de tests

### 1. Tests automatisés (testCriteria.unit)

Exécuter les tests unitaires définis :

```bash
# Exécuter tous les tests
npm test

# Exécuter les tests spécifiques à la tâche
npm test -- --grep "ExpiryDate"
```

### 2. Vérifications manuelles (testCriteria.manual)

Pour chaque critère manuel, documenter le résultat :

```markdown
## Vérifications manuelles - F001_T003

- [x] Vérifier visuellement l'alignement du champ
  - Résultat: OK - Le champ est aligné avec les autres
- [x] Tester le datepicker sur mobile
  - Résultat: OK - Fonctionne sur viewport 375px
```

---

## Workflow de test

### 1. Préparation

```bash
# Vérifier que le code est à jour
git status

# Installer les dépendances si nécessaire
npm install
```

### 2. Exécution des tests automatisés

```bash
# Tests unitaires
npm test

# Tests avec couverture
npm test -- --coverage

# Tests spécifiques
npm test -- --testPathPattern="UserForm"
```

### 3. Vérification des acceptance criteria

Pour chaque criterion dans `acceptanceCriteria` :

| Criterion | Type | Résultat |
|-----------|------|----------|
| Le champ email est visible | Manuel | ✓ |
| La validation refuse les emails invalides | Auto | ✓ (test_email_validation) |
| Message d'erreur en rouge | Manuel | ✓ |
| Format email valide en sortie | Auto | ✓ (test_email_format) |
| Typecheck passes | Auto | ✓ |
| Tests passent | Auto | ✓ |

### 4. Tests de régression

```bash
# S'assurer que les tests existants passent toujours
npm test -- --changedSince=HEAD~1
```

---

## Rapport de test

### Format du rapport

```json
{
  "taskId": "F001_T003",
  "testedAt": "2026-02-02T15:00:00Z",
  "testedBy": "agent:tester",
  "results": {
    "unitTests": {
      "total": 5,
      "passed": 5,
      "failed": 0,
      "coverage": "87%"
    },
    "manualChecks": {
      "total": 2,
      "passed": 2,
      "failed": 0
    },
    "acceptanceCriteria": {
      "total": 6,
      "satisfied": 6,
      "unsatisfied": 0
    }
  },
  "status": "PASS",
  "notes": "Tous les critères satisfaits"
}
```

### En cas d'échec

```json
{
  "status": "FAIL",
  "failures": [
    {
      "criterion": "La validation refuse les dates passées",
      "expected": "Erreur affichée",
      "actual": "Date acceptée sans erreur",
      "evidence": "Screenshot: failures/F001_T003_date_validation.png"
    }
  ]
}
```

---

## Contribution à la mémoire

### Scénarios de test découverts

```bash
./utils/memory_manager.sh create \
  --category "test_cases" \
  --title "Edge cases DatePicker" \
  --tags "date,validation,edge-cases" \
  --author "agent:tester" \
  --task "$TASK_ID" \
  --content "Cas limites à tester pour DatePicker:\n- Date au 31 décembre\n- Année bissextile\n- Timezone différente..."
```

### Bugs découverts (edge cases)

```bash
./utils/memory_manager.sh create \
  --category "edge_cases" \
  --title "Bug timezone DatePicker" \
  --tags "date,timezone,bug" \
  --author "agent:tester" \
  --content "Le DatePicker échoue si timezone = UTC-12..."
```

---

## Signal de complétion

### Tests réussis
```
<promise>COMPLETE</promise>
```

La tâche passe en status "Tested".

### Tests échoués
```
<promise>TESTS_FAILED: [nombre] tests failed</promise>
```

La tâche passe en status "Error" avec le rapport d'échec.

---

## Checklist de test

- ☐ Tests unitaires exécutés
- ☐ Tous les tests passent
- ☐ Couverture de code acceptable
- ☐ Vérifications manuelles effectuées
- ☐ Tous les acceptance criteria validés
- ☐ Pas de régression détectée
- ☐ Rapport de test généré
- ☐ Edge cases documentés si découverts

---

## Exemple de session type

```
1. Lire la tâche F001_T003 et ses testCriteria
2. Vérifier que le status est "Reviewed"
3. Exécuter npm test
4. Vérifier la couverture de code
5. Effectuer les vérifications manuelles
6. Valider chaque acceptance criterion
7. Documenter les résultats
8. Si tout passe: status → Tested + <promise>COMPLETE</promise>
9. Si échecs: status → Error + rapport d'échec
```

---

## Notes pour les tests manuels

### Comment documenter une vérification manuelle

```markdown
### Vérification: "Vérifier visuellement l'alignement du champ"

**Étapes:**
1. Ouvrir http://localhost:3000/user/new
2. Observer le formulaire
3. Vérifier l'alignement du champ email

**Résultat attendu:**
- Le champ doit être aligné verticalement avec les autres champs
- Le label doit être à gauche du champ
- L'espacement doit être cohérent

**Résultat obtenu:**
- ✓ Alignement correct
- ✓ Label positionné correctement
- ✓ Espacement cohérent

**Conclusion: PASS**
```
