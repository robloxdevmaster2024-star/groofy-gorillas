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
- [x] Gamemode **Clown Survival** complet — `server/Gamemodes/ClownSurvival.luau`
- [x] HUD de statut (bandeau + timer) — `client/StatusHud.client.luau`
- [x] **DataService** — persistance joueur, migré de DataStoreService brut vers **ProfileStore** (session-lock, anti-perte)
      - champs : `goofyPoints`, `level`, `ownedCosmetics`, `equipped`, `achievements`, `bestTimes`, `stats`
      - API inchangée : `GetProfile(player)`, `AddGoofyPoints(player, n)`, `GetLevel`, `GetNextThreshold`
      - branché au RoundManager : +50 GP gagnant, +15 GP participation
      - *Critère de validation : les points survivent à un rejoin.*
      - **Migration ProfileStore (voir aussi section dédiée plus bas)** : `src/server/ProfileStore.luau` vendored depuis MadStudioRoblox/ProfileStore (licence MIT) — session-lock, auto-save (300s) et `BindToClose` gérés EN INTERNE par la librairie, retries déjà intégrés dans `StartSessionAsync`/les sauvegardes. Store renommé `GoofyGorillas_v1` → `GoofyGorillas_v2` (nouveau format, décision assumée : pas de données de test réelles à migrer).
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
      - `SettingsSchema` data-driven ajouté dans Clown Survival et Dodgeball
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
- [x] **Bouton "JOUER" bas-centre** — recherche de serveur sans marcher sur une zone
      - `LobbyService.luau` : `joinQueue()` extrait (réutilisé par zones + remote), RemoteEvents `RequestJoinQueue`/`RequestLeaveQueue`, RemoteFunction `GetGamemodes`
      - `PlayButton.client.luau` : bouton bas-centre → menu de sélection de gamemode → file d'attente, overlay "Recherche…" + annulation, se synchronise avec `PlayerZone` (masqué si déjà en file/zone)
- [x] **Fix : bouton "JOUER" caché/inactif pendant une partie en cours**
      - `PlayerZone` transporte désormais un flag `inRound` (true au lancement du round, false au retour au lobby)
      - `PlayButton.client.luau` : le bouton reste invisible + inactif tant que `inRound = true` (empêche de relancer une partie pendant qu'on joue déjà)
      - `LobbyService.luau` : garde serveur `playersInRound` — `joinQueue()` ignore toute requête d'un joueur déjà en partie (anti-triche)

---

## Clown Survival — Reskin « Le Clown de nuit » (ex-"Infector")  `[x]`

> Thème officiel retenu pour Clown Survival, voir `CLAUDE.md` § 1.bis.

- [x] Remplacer la contamination par proximité par une **arme batte de baseball** (hitbox serveur, swing via cône de portée `meleeRange`/`MELEE_CONE_DOT`)
      - `ClownSurvivalEvents.Swing` (client → serveur, LookVector caméra) + `ClownSurvivalEvents.SetActive` (serveur → client, active/désactive le bouton de frappe)
      - `ClownSurvivalInput.client.luau` : clic gauche PC + bouton mobile dédié 🏏
- [x] **Batte physique + animation de swing** : `Motor6D` soudé à la main (R15/R6), animation Heartbeat aller-retour vers la pose de frappe
- [x] **Knockback + ragdoll R15** façon Smash Bros
      - `applyKnockback()` → `ragdollCharacter()` : chaque `Motor6D` détaché (`Part0 = nil`) et remplacé par une `BallSocketConstraint` libre, vélocité d'impact + rotation aléatoire appliquées à chaque membre, restauré après `knockbackStunDuration`
- [x] **Bouton taunt** (réservé aux survivants) : touche F (PC) / tap (mobile), son de rire, cooldown anti-spam — `ClownSurvivalEvents.Taunt`/`TauntAvailable`
- [x] Passer `RoundDuration` de 90 à **300** (5 min)
- [x] Reskin visuel minimal : highlight clown (rose/rouge), banners re-thémés 🤡, ambiance sombre via `Lighting` (ClockTime minuit, ambient sombre, fog) restaurée au `Stop()`
- [x] Win conditions (`CheckWin`/`ResolveTimeout`) inchangées et cohérentes (rôles clown/enfant = infecté/survivant)
- [x] Renommage complet **Infector → Clown Survival** (fichiers, module, events, achievements, docs)
- [x] **Sprint + glissade** (tout le monde) et **combo de frappes** (stamp animé au-dessus du clown, dégradé blanc→rouge, glow néon, particules) — voir `ClownSurvival.luau` (stamina/slide/combo) et `ClownSurvivalCombo.client.luau`
- [x] **Se coucher / ramper** (survivants uniquement) : bascule (toggle) touche C (PC) / bouton mobile 🧎, hitbox abaissée (HipHeight/BodyHeightScale, comme la glissade mais persistant) pour passer sous des obstacles bas, vitesse réduite (`PRONE_WALK_SPEED`) — `ClownSurvivalEvents.ToggleProne`/`ProneAvailable`, forcé au relevé si contaminé/éliminé — `ClownSurvivalProne.client.luau`
- [~] **Bunny hop** (tout le monde) — EN PAUSE, conception faite mais à peaufiner avant de considérer ça fini :
      - Atterrissage détecté via `Humanoid.StateChanged` (fiable, physique), saut enchaîné validé sur un VRAI ré-appui (`ClownSurvivalEvents.BhopJumpPressed`, front montant client) plutôt que sur l'état "Jumping" du Humanoid — sinon maintenir Espace suffit à bhop en boucle sans timing.
      - Bonus de vitesse (`bhopBoost`, +`BHOP_SPEED_BONUS_PER_HOP`/saut bien timé, plafond anti-abus `BHOP_MAX_SPEED`) remis à zéro si la fenêtre (`BHOP_LANDING_WINDOW`) expire sans ré-appui valide. `ClownSurvivalBhop.client.luau`.
      - ⚠️ *Limite connue* : la détection par front montant ne couvre que le clavier PC (Espace) — le bouton de saut mobile par défaut de Roblox (CoreGui) ne peut pas être intercepté proprement sans le remplacer entièrement ; sur mobile, "maintenir pour spam" reste possible pour l'instant.
      - À reprendre : retester le feeling en jeu (valeurs BHOP_* à ajuster ?), régler la limite mobile, décider si un feedback visuel/sonore doit accompagner un saut bien enchaîné.
- [x] **Capacités actives du clown** : Dash (touche Q / bouton mobile 💨, ruée à vitesse imposée façon glissade — décélération en racine carrée vers `BASE_WALK_SPEED`, `DASH_SPEED=46`, `DASH_DURATION=1.2s`, pilotable pendant la ruée (`DASH_TURN_RATE`, suit progressivement les touches tenues), direction = mouvement/orientation du PERSONNAGE (pas la caméra, comme la glissade), cooldown 6s, effets : traînée double + kick de FOV + camera shake) et Vision (touche R / bouton mobile 👁️, révèle les survivants à travers les murs via `Highlight` créé côté client du clown UNIQUEMENT — donc invisible pour les autres joueurs —, fondu d'entrée/sortie du glow (0.3s), `VISION_DURATION=2.5s`, `VISION_COOLDOWN=35s`). Cooldowns confirmés par le serveur (`DashPerformed`/`VisionGranted`), jamais optimistes côté client (même classe de bug que le bouton "se coucher" corrigée en amont). `ClownSurvivalClownAbilities.client.luau`.
      - ⚠️ *Non fait* : pas de vrai SFX de dash (whoosh) — feedback actuellement visuel uniquement. Nécessite un asset audio, comme le rire du taunt.
      - Valeurs à valider en jeu, premier jet d'équilibrage (revu une fois côté durée dash / cooldown+durée vision).
      - Glissade pilotable elle aussi pendant son déroulé (`SLIDE_TURN_RATE`, même principe que le dash).
- [x] **Anti-triche mouvement** : état de déplacement centralisé côté serveur (`getMovementState` → `idle`/`run`/`slide`/`prone`/`air`/`dash`, seule source de vérité), réutilisé à la fois pour la priorité de `WalkSpeed` et pour un plafond de vitesse légitime par état (`STATE_MAX_SPEED` + marge `SPEED_TOLERANCE`). Toute vitesse horizontale au-delà du plafond (speed-hack potentiel) est automatiquement ramenée à la limite (composante verticale intacte), avec un `warn()` serveur pour visibilité. Le ragdoll/knockback (`Humanoid.PlatformStand`) est exempté du contrôle (vélocité imposée légitime). État diffusé au client concerné (`MovementStateChanged`) pour une machine à états propre côté client aussi — `ClownSurvivalMovementState.client.luau` (inclut un petit indicateur de debug coin haut-gauche, facilement retirable).
      - À valider : jouer avec un exploit de vitesse connu (ou un script de test) pour confirmer que la correction se déclenche sans faux-positifs en jeu normal (marge `SPEED_TOLERANCE` à ajuster si besoin).
      - Étendu au **hub** (`LobbyService.luau`, `stepHubAntiCheat`) : version simplifiée (pas de sprint/glissade dans le hub) qui plafonne la vitesse horizontale (`HUB_MAX_HORIZONTAL` = WalkSpeed par défaut + marge) ET la vitesse verticale montante (`HUB_MAX_UPWARD_SPEED = 60`, bien au-dessus d'un saut normal) pour bloquer speed-hacks et fly-hacks basiques. Ignore les joueurs déjà en partie (gérés par l'anti-triche du round) et le ragdoll (`PlatformStand`).
- [ ] *(non fait)* **Vraie animation de rampement/couché** — actuellement juste un rétrécissement du corps (HipHeight/BodyHeightScale), pas une posture couchée visuelle. Nécessite soit une vraie animation key-framée (Blender ou éditeur d'animation Roblox, uploadée avec un ID) jouée via Animator — je peux écrire tout le code de lecture, mais pas créer l'animation elle-même (asset) — soit, en alternative 100% scriptable mais plus rigide, faire pivoter tout le personnage à l'horizontale. Décision reportée à plus tard.
- [ ] *(non fait)* Ambiance sonore (SFX du rire du bouton taunt à remplacer par un vrai asset) et modèle 3D de batte/clown — nécessite assets, hors scope code
- [ ] *(non fait)* Vérifier en Studio (2 clients) que le knockback/ragdoll ne propulse pas les joueurs hors des maps existantes

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
      - `ClownSurvival.GetWinnerRoles()` : distingue clown vs survivant pour achievements ciblés
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
| Matchmaking cross-serveur | Voir « Architecture serveur » ci-dessous | ✅ implémenté (voir plus bas) |

---

## Architecture serveur — Hub vs Places séparées (tranché : 1 seule Place)

**Contexte** : le jeu tourne en **une seule Place Roblox**. Question posée deux fois (et confirmée la 2ᵉ fois) : séparer le hub (menu/déambulation) du jeu dans deux Places Roblox différentes ?

**Conclusion actée (confirmée)** : **ne pas séparer en deux Places**. Le vrai problème n'était pas "hub vs jeu" mais le **matchmaking** limité au pool de joueurs d'un seul serveur. Résolu via matchmaking cross-serveur SUR LA MÊME PLACE (voir section suivante), sans la lourdeur de deux projets Rojo / deux places à synchroniser.

**À ne pas refaire** : proposer de scinder en deux Places distinctes pour ce problème — ce n'est pas la bonne réponse, cf. ci-dessus. Si un jour une vraie 2ᵉ Place est voulue (ex. un mini-jeu complètement à part), ce serait une décision séparée, pas une réponse au problème de matchmaking.

---

## Matchmaking cross-serveur `[~]` — ⏸️ SUSPENDU (code fait, désactivé le temps de débloquer le test)

> **État exact** : tout le code est écrit et en place, mais **désactivé** via un seul flag :
> `src/server/MatchmakingConfig.luau` → `Enabled = false`. Repasser à `true` pour tout réactiver
> d'un coup (`LobbyService`, `RoundManager` et le bouton "Jouer" lisent tous ce flag). Rien à
> réécrire pour reprendre.
>
> **Pourquoi suspendu** : `TeleportService:ReserveServer` renvoyait une `403 Forbidden` en test.
> Cause probable : "Enable Studio Access to API Services" décoché (Game Settings > Security)
> et/ou le fait qu'un vrai test cross-serveur ne peut être validé qu'en jeu **publié** (pas dans
> "Test → Clients and Servers" de Studio, qui ne crée pas de vrais serveurs séparés). À vérifier
> avant de réactiver.

- [x] **`MatchmakingService.luau`** (nouveau, `src/server/`) : file d'attente partagée en `MemoryStoreService`, une par gamemode.
      - **Enqueue** : bouton "Jouer" → `MatchmakingService.Enqueue(player, gamemodeName)` → `MemoryStoreQueue:AddAsync(player.UserId, 300)`.
      - **Coordination** : TOUS les serveurs Hub font tourner la même boucle (`runCoordinatorFor`, toutes les 3s/gamemode) — sans danger car `queue:ReadAsync(minPlayers, true, 0)` (allOrNothing) est atomique côté MemoryStoreService : un seul serveur "gagne" un lot exact à la fois. Le gagnant réserve un serveur (`TeleportService:ReserveServer`) et écrit une affectation par joueur matché dans une `MemoryStoreSortedMap` partagée (`ClownGorillasMatchAssignments`, TTL 60s).
      - **Dequeue** : un joueur ne peut être téléporté QUE depuis son propre serveur d'origine (TeleportService ne téléporte pas un joueur distant) — donc chaque serveur Hub surveille (toutes les 2s) si une affectation est apparue pour SES PROPRES joueurs en recherche, et exécute lui-même `TeleportService:TeleportAsync` avec le `ReservedServerAccessCode` partagé. C'est ce qui permet à des joueurs de serveurs différents de se rejoindre : chacun est téléporté par son serveur d'origine, vers le même accessCode.
      - Marche en parallèle de la file locale par zone (marcher sur une zone colorée = match instantané, même serveur uniquement, comportement inchangé) — seul le bouton "Jouer" utilise la recherche cross-serveur.
- [x] **`RoundManager.server.luau`** : détecte au démarrage si CE serveur est un serveur de match réservé (`game.PrivateServerId ~= ""` + `TeleportData.isMatchServer` du premier joueur, via `TeleportOptions:SetTeleportData` posé par `MatchmakingService`). Si oui : attend une courte fenêtre de grâce (5s, le temps que les joueurs arrivent de plusieurs serveurs différents), lance directement `RoundRunner.RunRound(...)` (sans passer par `LobbyService`/le hub), puis à la fin renvoie tout le monde vers un serveur public normal (`TeleportService:TeleportAsync`, sans accessCode réservé). Sinon (serveur public normal) : démarre `LobbyService.Start(...)` comme avant — **sans bloquer** sur l'attente d'un joueur (sinon le tout premier `PlayerAdded` du hub serait raté par `LobbyService`, régression identifiée et évitée).
- [ ] *(à tester en jeu, pas juste en lecture de code)* : lancer 2 serveurs de test (2 fenêtres Studio "Test → Clients and Servers" avec des joueurs différents, ou 2 serveurs publiés) cliquant "Jouer" sur le même gamemode, et vérifier qu'ils atterrissent bien dans la même partie malgré des serveurs d'origine différents — critère de validation de cette feature.
- [ ] *(non fait)* Pas de mécanisme de remboursement/reset si un joueur quitte la file AVANT d'être matché mais APRÈS qu'un lot ait déjà été lu (fenêtre de course rare, dégrade proprement : personne d'autre n'est bloqué, juste ce joueur "gaspille" une place dans un lot ailleurs — acceptable pour l'instant vu l'échelle du jeu).

---

## Progression joueur — ProfileStore `[x]`

- [x] **`src/server/ProfileStore.luau`** (vendored, licence MIT) : récupéré tel quel depuis [MadStudioRoblox/ProfileStore](https://github.com/MadStudioRoblox/ProfileStore) (successeur de ProfileService, même auteur). Choisi plutôt qu'une solution maison car il couvre déjà nativement les 4 points techniques demandés :
      - **Session-lock** : `ProfileStore:StartSessionAsync(key, params)` garantit qu'un profil n'est actif que sur UN SEUL serveur à la fois.
      - **Reconnexion rapide** : si le profil est encore verrouillé ailleurs, `StartSessionAsync` **réessaie automatiquement en interne** (toutes les ~10s, jusqu'à ~120s avant d'abandonner) — c'est ce qui couvre le choix "attendre puis réessayer" plutôt que kick immédiat.
      - **Anti-perte** : auto-save périodique (300s) ET sauvegarde de fermeture (`game:BindToClose`) gérées **entièrement en interne** par la librairie (vérifié dans le code source : elle boucle sur tous les profils actifs et les sauvegarde au shutdown) — `DataService.luau` n'a donc plus besoin de sa propre boucle d'auto-save ni de son propre `BindToClose`.
      - **pcall + retries** : déjà intégrés aux appels DataStore internes de ProfileStore (`GetAsync`/`SetAsync`/`UpdateAsync`).
- [x] **`DataService.luau` réécrit** autour de `ProfileStore.New("GoofyGorillas_v2", TEMPLATE)` : API publique **inchangée** (`GetProfile`, `AddGoofyPoints`, `GetLevel`, `GetNextThreshold`) donc aucun autre fichier (`RoundRunner`, `AchievementService`, `LeaderboardService`) n'a eu besoin d'être modifié — `GetProfile(player)` renvoie toujours la table de données brute (`profile.Data`), pas l'objet `Profile` de ProfileStore.
      - `profile:AddUserId()` (conformité GDPR) + `profile:Reconcile()` (comble les champs ajoutés au TEMPLATE après coup) à chaque chargement.
      - `profile.OnSessionEnd` → si un autre serveur vole la session, le joueur est **kick** avec message clair (cas limite après épuisement des tentatives internes de `StartSessionAsync`, pas le chemin normal).
      - Store renommé `GoofyGorillas_v1` → `GoofyGorillas_v2` : nouveau format (décision assumée avec l'utilisateur — pas de données de test réelles à préserver, on repart à zéro).
- [ ] *(à tester en jeu)* Rejoindre/quitter plusieurs fois de suite pour valider "les données survivent à un rejoin" ET observer l'Output pour confirmer qu'aucun warning DataStore n'apparaît (critère de validation).
- [ ] *(à tester)* Le cas session-lock lui-même (ouvrir 2 sessions Studio "Test → Clients and Servers" avec le même compte, ou simuler un rejoin très rapide) pour confirmer le comportement d'attente/retry.