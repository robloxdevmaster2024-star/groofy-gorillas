# ROADMAP — Goofy Gorillas

> Source de vérité unique pour l'avancement du projet.
> **À lire au début de chaque session** (avec `CLAUDE.md`) et **à mettre à jour** dès qu'une tâche change d'état.
> Légende : `[ ]` à faire · `[~]` en cours · `[x]` fait

---

## Statut global

**Phase actuelle : Phase 3 — Méta & rétention (en cours)**
Phase 2 complète ✅. Cosmétiques restants. Lobby hub implémenté (hors roadmap officielle, ajouté en session).

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
- [x] **2ᵉ gamemode : Dodgeball** (valide la solidité du framework)
      - balles serveur (CanCollide = true, Touched avec délai 0.2s anti-self-hit)
      - direction = LookVector caméra envoyé par le client (RemoteEvent)
      - validation cooldown + direction côté serveur (anti-cheat)
      - joueurs éliminés : Highlight gris + WalkSpeed 0
      - bouton mobile dédié (évite conflit swipe caméra)
      - RemoteEvents créés au chargement du module (WaitForChild client fiable)
- [x] **Système de settings / édition des gamemodes** : overrides des `DefaultSettings` + UI host
      - `GameSettings.luau` : stockage overrides par gamemode, host = 1er joueur connecté, RemoteEvents
      - `SettingsMenu.client.luau` : panneau haut-droit pendant l'intermission (host = boutons +/−, autres = lecture seule)
      - `SettingsSchema` data-driven ajouté dans Infector et Dodgeball
      - RoundManager : sélection du mode AVANT l'intermission (le mode est annoncé dès le début du décompte)
- [ ] (Optionnel) 3ᵉ gamemode pour stresser le framework

---

## Lobby Hub (ajout hors phases)  `[x]`

- [x] **Système de lobby + zones** — refonte majeure de l'orchestration
      - `LobbyService.luau` : lobby map (Studio) ou zones procédurales colorées, queues par gamemode, countdown 15s, un round à la fois
      - `RoundRunner.luau` : logique d'exécution d'un round extraite de RoundManager (callable, yields)
      - `LobbyHud.client.luau` : panneau bas-centre animé (slide-in), barre de progression, statut countdown
      - `RoundManager.server.luau` : réduit à ~15 lignes (crée GameStatus + démarre LobbyService)
      - Convention Studio : `ServerStorage.Venues.Lobby` → `SpawnPoints/` + Parts avec `Attribute("Gamemode")`
      - Fallback procédural : plateformes colorées aux 4 points cardinaux si pas de map lobby

---

## Infector — Reskin « Le Clown de nuit »  `[x]`

> Thème officiel retenu pour Infector, voir `CLAUDE.md` § 1.bis.

- [x] Remplacer la contamination par proximité par une **arme batte de baseball** (hitbox serveur, swing via cône de portée `meleeRange`/`MELEE_CONE_DOT`)
      - `InfectorEvents.Swing` (client → serveur, LookVector caméra) + `InfectorEvents.SetActive` (serveur → client, active/désactive le bouton de frappe)
      - `InfectorInput.client.luau` : clic gauche PC + bouton mobile dédié 🏏
- [x] **Knockback basé sur la vélocité d'impact** façon Smash Bros
      - `applyKnockback()` : `AssemblyLinearVelocity` (horizontal + vertical) + `Humanoid.PlatformStand` pendant `knockbackStunDuration`
- [x] Passer `RoundDuration` de 90 à **300** (5 min)
- [x] Reskin visuel minimal : highlight clown (rose/rouge), banners re-thémés 🤡, ambiance sombre via `Lighting` (ClockTime minuit, ambient sombre, fog) restaurée au `Stop()`
- [x] Win conditions (`CheckWin`/`ResolveTimeout`) inchangées et cohérentes (rôles clown/enfant = infecté/survivant)
- [ ] *(non fait)* Ambiance sonore (SFX) et modèle 3D de batte/clown — nécessite assets, hors scope code
- [ ] *(non fait)* Vérifier en Studio (2 clients) que le knockback ne propulse pas les joueurs hors des maps existantes

---

## Phase 3 — Méta & rétention  `[~]`

- [x] **Leaderboards** (OrderedDataStore) : Goofy Points global
      - `LeaderboardService.luau` : OrderedDataStore "GoofyPoints_Global_v1", UpdateScore + Refresh
      - `LeaderboardGui.client.luau` : overlay centré (Tab + bouton 🏆 haut-gauche), top 10, joueur local mis en valeur
      - DataService : UpdateScore au chargement + après AddGoofyPoints
      - RoundManager : Refresh après attribution des GP de fin de round
      - ⚠️ Time Trial = « plus bas gagne » → stocker en négatif / inverser à l'affichage (Phase 4)
- [ ] **Cosmétiques** : modèle layered clothing vs accessoires classiques *(décision en attente)*
      - shop + équipement **serveur** (anti-triche) + aperçu client
- [x] **Achievements + easter eggs** (flags persistés)
      - `AchievementsConfig.luau` (shared) : 14 succès data-driven (progression, gameplay, easter egg)
      - `AchievementService.luau` : conditions par trigger ("gp_change", "round_win", "round_played")
      - `AchievementToast.client.luau` : pop-up animée bas-droit, pile max 3, slide + fade-out
      - `Infector.GetWinnerRoles()` : distingue infecteur vs survivant pour achievements ciblés
      - DataService : champ `stats { gamesPlayed, gamesWon }` ajouté au template + Check après GP
      - RoundManager : incrémente stats, Check "round_win" (avec rôle) et "round_played" après chaque round

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