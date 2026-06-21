# Yanegi — Developer Setup & Collaboration Guide

## First-time setup

### 1. Clone the repo
```bash
git clone <repo-url>
cd yanegi-app
```

### 2. Flutter dependencies
```bash
flutter pub get
```

### 3. Cloud Functions dependencies
```bash
cd functions
npm install
cd ..
```

### 4. Firebase secrets
The `.env` file is gitignored. Create it from the template:
```bash
cp functions/.env.example functions/.env
# Then fill in the real RESEND_API_KEY (ask the team lead)
```

### 5. Run
```bash
flutter run
```

---

## Branch strategy

```
main          ← stable, production-ready code. Never push directly.
  └── develop ← integration branch. PR target for all features.
        ├── feature/anuj/feature-name   ← Anuj's work
        └── feature/friend/feature-name ← Friend's work
```

### Rules
- **Never push to `main` directly** — always via PR from `develop`
- **Never push to `develop` directly** — always via PR from a feature branch
- Feature branches are short-lived (one feature = one branch = one PR)
- PRs require at least one review before merging

---

## Daily workflow (avoiding merge conflicts)

### Start of day — sync your branch
```bash
git checkout develop
git pull origin develop
git checkout feature/your-name/your-feature
git rebase develop      # puts your commits on top of latest develop
```

### During work — commit often
```bash
git add lib/screens/your_screen.dart   # add specific files, not git add -A
git commit -m "feat: add share button to event card"
git push origin feature/your-name/your-feature
```

### Finishing a feature — open a PR
1. Push your branch
2. Open PR → `develop`
3. Tag the other person for review
4. Merge with **Squash and merge** (keeps history clean)

---

## Who owns what (prevents conflicts)

| Area | Owner |
|------|-------|
| `lib/screens/map_screen.dart` | Anuj |
| `lib/screens/chat/` | Discuss before touching |
| `functions/index.js` | Add functions at the bottom, never edit existing ones |
| `firestore.rules` | Discuss before changing — both must deploy |
| `firestore.indexes.json` | Append only, never reorder |
| `pubspec.yaml` | Coordinate dependency adds |

---

## The #1 conflict prevention rule

**Each person works in different files.**
If you both need to edit the same file, split it into smaller files first, or take turns via a short-lived pair of feature branches that are reviewed quickly.

---

## If you get a merge conflict

```bash
# On your feature branch:
git fetch origin
git rebase origin/develop

# For each conflict file:
# Open the file, find <<<<<<< markers, resolve manually
git add <resolved-file>
git rebase --continue

# Push (force needed after rebase)
git push origin feature/your-name/your-feature --force-with-lease
```
