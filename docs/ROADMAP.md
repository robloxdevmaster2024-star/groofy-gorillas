# ROADMAP — Goofy Gorillas

> Source de vérité unique pour l'avancement du projet.
> **À lire au début de chaque session** (avec `CLAUDE.md`) et **à mettre à jour** dès qu'une tâche change d'état.
> Légende : `[ ]` à faire · `[~]` en cours · `[x]` fait

---

## Statut global

**Phase actuelle : Phase 2 — Profondeur de jeu**
Phase 1 complète ✅. Prochain maillon : chargement de maps (venues) + 2ᵉ gamemode Dodgeball.

---

## Phase 0 — Fondations  `[x]`

- [x] Setup Rokit + Rojo + extensions VS Code
- [x] Pont VS Code ↔ Studio fonctionnel (Connect OK, sync live testée)
- [x] `default.project.json` (mapping server/client/shared)
- [x] Structure de dossiers `src/`

---

## Phase 1 — Boucle de jeu minimale (MVP)  `[x]`

- [x] Contrat des gamemodes — `shared/Gamemodes/Types.luau`
- [x] Round Manager (machine à états, rotation auto) — `server/RoundManager.server.luau`
- [x] Gamemode **Infector** complet — `server/Gamemodes/Infector.luau`
- [x] HUD de statut (bandeau + timer) — `client/StatusHud.client.luau`
- [x] **DataService (DataStoreService)** — persistance joueur
      - champs : `goofyPoints`, `level`, `ownedCosmetics`, `equipped`, `achievements`, `bestTimes`
      - API : `GetProfile(player)`, `AddGoofyPoints(player, n)`, `GetLevel`, `GetNextThreshold`
      - branché au RoundManager : +50 GP gagnant, +15 GP participation
      - auto-save 60s + BindToClose + 3 tentatives sur les erreurs DataStore
      - *Critère de validation : les points survivent à un rejoin.*
- [x] Affichage niveau + points dans le HUD / leaderstats
      - `PlayerStats.client.luau` : panneau bas gauche (niv, GP, barre de progression)
      - Notification "NIVEAU X atteint !" avec fade-out
      - `PlayerConfig.luau` : courbe de niveaux data-driven (Niv 1→20)

---

## Phase 2 — Profondeur de jeu  `[ ]`

- [x] **Chargement de maps** : venues dans `ServerStorage.Venues`, clonées par round, passées via `ctx.Map` + `ctx.SpawnCFrames`
      - `MapManager.luau` : LoadRandom, Unload, fallback grille circulaire si pas de maps
      - Joueurs téléportés aux spawn points avant `Start()`
      - Convention map : Model avec dossier `SpawnPoints/` contenant des BaseParts
- [ ] **2ᵉ gamemode : Dodgeball** (valide la solidité du framework)
- [ ] **Système de settings / édition des gamemodes** : overrides des `DefaultSettings` (lumières off, arme imposée…) + UI host
- [ ] (Optionnel) 3ᵉ gamemode pour stresser le framework

---

## Phase 3 — Méta & rétention  `[ ]`

- [ ] **Leaderboards** (OrderedDataStore) : Goofy Points global, etc.
      - ⚠️ Time Trial = « plus bas gagne » → stocker en négatif / inverser à l'affichage
- [ ] **Cosmétiques** : modèle layered clothing vs accessoires classiques *(décision en attente)*
      - shop + équipement **serveur** (anti-triche) + aperçu client
- [ ] **Achievements + easter eggs** (flags persistés)

---

## Phase 4 — Activités annexes  `[ ]`

- [ ] **Four in a Row** (Connect 4) — logique victoire serveur, UI client
- [ ] **Gravity arcade** — high score → OrderedDataStore
- [ ] **Time Trial** — parcours + chrono + PB persisté + leaderboard

---

## Phase 5 — Immersion & polish  `[ ]`

- [ ] **Voice chat positionnel** (Audio API ; activation Creator Dashboard + vérification d'identité)
- [ ] **Combat physique** : knockback basé sur la vélocité de collision (« don't hit each other too hard »), ragdoll au-delà d'un seuil
- [ ] VFX / SFX / juice
- [ ] **Optimisation mobile** (perf, UI tactile, polycount maps)
- [ ] Passe d'équilibrage des gamemodes

---

## Idées / backlog (non priorisé)

- Vote des joueurs pour le gamemode (remplacer la rotation auto)
- Menu host (un joueur décide mode + settings)
- Système de parties privées / lobbies
- Daily rewards / streaks

---

## Décisions en attente

| Sujet | Options | Statut |
|---|---|---|
| Cosmétiques | Layered clothing (pro, complexe) vs Accessoires classiques | ⏳ à trancher |
| Sélection gamemode | Rotation auto (actuel) vs Vote vs Menu host | rotation auto pour l'instant |