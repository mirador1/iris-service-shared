# ADR-0057 — Conserver le polyrepo (svc + UI séparés), pas de migration vers monorepo

- **Status**: Accepted
- **Date**: 2026-04-24
- **Auteur(s)**: benoit.besson, Claude

## Contexte

Mirador est composé de deux dépôts indépendants :
- `mirador-service` (Spring Boot 4 + Java 25, backend + infra Terraform + ADRs)
- `mirador-ui` (Angular 21 zoneless, frontend SPA + Playwright e2e)

Les deux sont fortement couplés au runtime via OpenAPI :
- `mirador-service` génère un `openapi.json` à `/v3/api-docs`
- `mirador-ui` consomme ce contrat via `scripts/gen-openapi-snapshot.sh`
  → `src/app/core/api/generated.types.ts` (autogénéré)

Au cours du dev quotidien (sessions du 2026-04-23/24), un overhead de
"propagation de drift" s'est manifesté :
- Une règle CLAUDE.md ajoutée doit l'être dans 3 fichiers (global +
  svc + UI) — drift garanti à terme.
- `TASKS.md` vit dans svc, contient références à du travail UI →
  désynchronisation possible.
- 2 pipelines CI à maintenir, 2 SonarCloud à monitorer, 2 mirrors
  GitHub à pousser, 2 cadences de tag (`stable-vX` par repo).
- Un changement cross-cutting (endpoint backend + client UI) =
  2 MRs à coordonner, 2 reviews, 2 tags, fenêtre de désync où le
  backend est déployé sans matching UI.

La question s'est posée : **fusionner les deux en un monorepo
(stack Nx ou Turborepo + pnpm workspaces) ?**

## Analyse

### Arguments POUR le monorepo

1. **Changements atomiques cross-stack** — backend ajoute endpoint +
   UI consume = un commit, une MR, un cycle CI, un rollback. Net :
   zéro fenêtre de désync, lecture du diff plus claire.
2. **Outils partagés** — un CLAUDE.md (fini la propagation), un
   TASKS.md, un set d'ADRs, un `.gitlab-ci.yml`, un renovate.json.
3. **Refactor freedom** — renommer un endpoint backend = update
   `generated.types.ts` UI dans le même commit. Plus de "j'espère
   que UI marche encore après ce push backend".
4. **CI cost moindre** (contre-intuitif) — avec `rules:changes:` ou
   Nx affected, modif UI ne lance pas le pipeline backend.
   Aujourd'hui : on paie souvent les 2 pipelines pour des
   changements partagés (CLAUDE.md, ADRs, rules).
5. **Onboarding** — un clone, un `./bin/run.sh`, pas de path-juggling
   sibling.
6. **Tagging unifié** — `stable-vX.Y.Z` global = un point dans le
   temps cohérent. Plus de "svc 1.0.44 est-il compatible avec
   UI 1.0.45 ?" matrix mentale.
7. **Sonar / coverage / audit** — un projet, une vue holistique.

### Arguments CONTRE le monorepo

1. **Mélange des expertises** — un dev backend ouvre le repo et voit
   immédiatement le code Angular qu'il ne connaît pas (et inversement).
   Pollution cognitive : on doit `cd apps/svc/` ou configurer son IDE
   pour scoper. Avec polyrepo, **chaque dev clone uniquement ce qu'il
   maîtrise** — séparation cognitive nette.
2. **Réflexes différents par stack** — npm vs Maven, Vitest vs
   JUnit5, ESLint vs Checkstyle/PMD, prettier vs spotless,
   pre-commit hooks distincts. Les mélanger dans un même repo crée
   des configs cross-stack confuses (`package.json` au root qui
   dépend de `apps/svc/pom.xml` ?).
3. **Contributors potentiels filtrent par repo** — un open-source
   contributor qui ne fait que du frontend clique sur `mirador-ui`
   et sait qu'il n'a pas besoin de comprendre Spring Boot. Avec
   monorepo, il doit naviguer pour comprendre que "non, le backend
   tu peux l'ignorer".
4. **Migration coûte 4-8h** — `git filter-repo --to-subdirectory-filter`
   pour préserver blame, refonte CI en `rules:changes:`,
   consolidation tags, mise à jour scripts de release, mise à jour
   doc, mise à jour bookmarks. Une fois, mais une fois quand-même.
5. **Risk de regression** — toute migration de cette envergure casse
   au moins 1-2 trucs subtils (paths hardcodés, CI assumptions,
   IDE config, GitHub Actions, etc.). Bug surface non négligeable.
6. **Tag scheme à refondre** — `stable-vX-svc` + `stable-vX-ui` OU
   `stable-vX` global. Décision design qui touche aussi les release
   notes, le changelog, les ADRs qui référencent les tags.
7. **PR reviews potentiellement larges** — un "petit fix UI" apparaît
   à côté d'un "security backend" dans la même liste PR. Mitigation
   par PR templates + scope-prefixed titles, mais friction réelle.
8. **Monorepo tooling overhead** — Nx ajoute ~200 MB de deps,
   `nx affected` requiert un setup graph correct, plugins, etc.
   Pour 2 apps c'est overkill ; pour 5+ apps ça vaut.

### Trade-off principal : automation vs séparation cognitive

- **Monorepo** = gain en automation cross-stack (1 MR, 1 CI, 1 tag)
  mais perte en clarté cognitive (le repo mélange Angular + Spring).
- **Polyrepo** = perte en automation (drift à propager via discipline)
  mais gain en clarté cognitive (chaque repo = un domaine).

Pour un projet **portfolio en cours de dev par 1-2 personnes**,
l'automation gagnerait. Pour un projet **avec contributeurs externes
potentiels et expertises dev front/back distinctes**, la séparation
cognitive gagne.

## Décision

**Conserver le polyrepo.** `mirador-service` et `mirador-ui` restent
deux dépôts GitLab indépendants, avec mirrors GitHub indépendants,
tags indépendants, pipelines CI indépendants.

Justification dominante : **séparation des expertises**. Un dev
backend qui ouvre `mirador-service` voit du Spring Boot, du Maven,
du Java 25 — et pas du Angular qui le déstabilise. Réciproquement
pour un dev frontend ouvrant `mirador-ui`. Cette séparation devient
critique si le projet attire des contributeurs externes
(open-source, demos publiques pour recruteurs).

Le coût de la propagation de règles cross-repo (CLAUDE.md, TASKS.md
références) est accepté comme **discipline workflow**, pas comme
défaut architectural.

## Conséquences

### Acceptées (statu quo confirmé)

- Maintien de 2 `CLAUDE.md` projet + 1 global (3 fichiers à
  synchroniser quand on ajoute une règle générale). La règle
  "When adding a general rule (workflow, style, architecture):
  also add it to ~/.claude/CLAUDE.md so it applies globally
  across all projects" continue de gérer ce cas.
- TASKS.md vit dans `mirador-service` (par convention, début
  de projet). Référence le travail UI quand pertinent. Si un
  jour le projet UI grandit indépendamment, créer un
  `mirador-ui/TASKS.md` propre.
- 2 pipelines CI indépendants. Coût en runner-minutes accepté.
- 2 cadences de tag indépendantes (`stable-vX.Y.Z` par repo).
  Quand un changement cross-cutting nécessite une corrélation,
  référencer dans le commit message + ADR.
- 2 mirrors GitHub indépendants (push manuel ou via cron
  `bin/launchd/`). Discipline workflow.

### Discipline workflow renforcée

- Pour un endpoint backend + client UI cross-cutting :
  1. PR backend qui ajoute l'endpoint (sans le client)
  2. Tag svc temporaire ou note pour traceabilité
  3. PR UI qui regen `generated.types.ts` + intègre le client
  4. Tag UI séparé
  Si la coordination devient pénible (plus de 2-3 cross-cutting
  par mois), réviser la décision.

- Pour les règles cross-repo (CLAUDE.md ADR, etc.) :
  - Ajouter au global `~/.claude/CLAUDE.md` ET aux 2 CLAUDE.md
    projet dans le même commit-set (sur les 2 repos en parallèle).
  - Le global est l'autorité ; les projet CLAUDE.md citent
    explicitement la règle globale.

### Retournements possibles (conditions de revisite)

Cette décision sera revisitée si :
- Le nombre de cross-cutting MRs > 5 par mois (pénibilité élevée).
- Un 3e service (mobile app, microservice indépendant) apparaît
  → polyrepo s'aligne mieux à plusieurs services.
- Le projet attire un dev full-stack qui demande la fusion pour
  workflow.
- L'écosystème Nx/Turborepo simplifie radicalement le coût de
  monorepo (improbable, mais possible).

Cette ADR n'est PAS un blocage permanent : c'est une décision pour
**la phase actuelle** (1-2 contributeurs, projet portfolio en
maturation). Re-évaluer à chaque audit d'architecture trimestriel.

## Alternatives envisagées

### A. Migration immédiate vers Nx

Rejetée : coût 4-8h pendant que B-7 wave + Phase C svc Checkstyle
sont en cours. Migration noise pendant feature work = friction
inutile. Si jamais la décision se retournait, faire la migration
en Q3 2026 quand le backlog se calme.

### B. Migration vers Turborepo + pnpm workspaces

Rejetée : Turborepo est optimisé JS/TS. Le backend Java + Maven
ne s'intègre pas naturellement (il faudrait un wrapper artificiel).
Nx aurait été plus adapté techniquement. Mais voir A.

### C. Symlinks ou git submodules

Rejetée : submodules sont une mauvaise approximation de monorepo
(complexité git énorme, atomicité partielle). Symlinks cassent
la portabilité Linux/macOS et les CI runners.

### D. Sous-modules monorepo virtuel via "common" repo

Rejetée : ajouterait un 3e repo "mirador-common" avec types
partagés et règles. Augmente la fragmentation, n'élimine pas
le drift, ajoute un maillon cassable. Pire des deux mondes.

## Liens

- ADR-0008 (Hexagonal architecture / dependency rule) — la séparation
  des expertises s'aligne avec le principe de dépendance vers
  l'intérieur. Polyrepo = chaque repo a sa "Clean Architecture"
  isolée.
- ADR-0044 (Hexagonal Lite) — même principe à l'intérieur d'un
  service ; polyrepo l'étend au niveau systémique.
- ADR-0055 (Shell-based release automation) — accepter la
  multiplication des scripts par repo (svc + UI ont leurs
  propres `bin/ship/`) est cohérent avec la décision polyrepo.
- ADR-0056 (Widget extraction pattern) — la discipline d'extraction
  s'applique INDÉPENDAMMENT dans chaque repo, pas de partage de
  widgets entre svc et UI. Cohérent.
