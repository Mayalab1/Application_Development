# Conventions de Code

Ce document définit les conventions de code à respecter dans le projet.

## Conventions générales

### Nommage

- **Variables** : camelCase
- **Constantes** : UPPER_SNAKE_CASE
- **Classes** : PascalCase
- **Fichiers** : kebab-case ou camelCase selon le framework

### Commentaires

- Éviter les commentaires évidents
- Documenter le "pourquoi", pas le "quoi"
- JSDoc/TSDoc pour les APIs publiques

### Structure de code

- Une responsabilité par fonction/classe
- Fonctions courtes (< 30 lignes)
- Maximum 3 niveaux d'imbrication

## Conventions spécifiques

### TypeScript/JavaScript

```typescript
// Préférer les interfaces aux types pour les objets
interface User {
  id: string;
  name: string;
}

// Utiliser const par défaut
const value = 42;

// Arrow functions pour les callbacks
items.map((item) => item.id);
```

### React (si applicable)

```tsx
// Composants fonctionnels
const MyComponent: React.FC<Props> = ({ title }) => {
  return <div>{title}</div>;
};

// Hooks personnalisés avec préfixe "use"
const useCustomHook = () => { ... };
```

### API/Backend

```typescript
// RESTful naming
GET    /api/v1/users
POST   /api/v1/users
GET    /api/v1/users/:id
PUT    /api/v1/users/:id
DELETE /api/v1/users/:id
```

## Tests

- Nommer les tests de manière descriptive
- Un fichier de test par module (`*.test.ts` ou `*.spec.ts`)
- Structure AAA : Arrange, Act, Assert

```typescript
describe('UserService', () => {
  it('should create a new user with valid data', () => {
    // Arrange
    const userData = { name: 'John' };

    // Act
    const result = userService.create(userData);

    // Assert
    expect(result.name).toBe('John');
  });
});
```

## Git

### Commits

Format : `type(scope): description`

Types :
- `feat` : Nouvelle fonctionnalité
- `fix` : Correction de bug
- `refactor` : Refactoring
- `test` : Ajout/modification de tests
- `docs` : Documentation
- `chore` : Maintenance

### Branches

- `main` : Production
- `develop` : Développement
- `feature/xxx` : Features
- `fix/xxx` : Corrections
