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
      - **Fix coups qui ratent de près** : `findMeleeTarget` comparait le cône en 3D brut (LookVector caméra vs position cible) — de près, la caméra 3e personne doit pointer vers le bas pour garder une cible proche à l'écran, ce qui faisait chuter le produit scalaire même parfaitement aligné à l'horizontale. Le cône est maintenant évalué en 2D (plan horizontal uniquement, `aimFlat`/`offsetFlat`), plus fidèle à "une batte vise devant le personnage" qu'à l'angle exact du regard.
- [x] **Batte physique + animation de swing** : `Motor6D` soudé à la main (R15/R6), animation Heartbeat aller-retour vers la pose de frappe
      - **Fix batte tenue à l'envers** (`createBatModel`, `ClownSurvival.luau`) : le clown semblait tenir la batte par le gros bout (tête), manche pointant vers l'extérieur — l'inverse d'une prise normale. Cause : `Handle` (manche) était lui-même le `PrimaryPart`/point d'attache du `Motor6D`, avec son point d'attache à sa PROPRE CENTER — la moitié du manche dépassait donc derrière la main (côté joueur), et la tête (`Barrel`, décalée en +X) se retrouvait relativement proche de la main plutôt que loin devant. Reconstruit avec une part `Grip` invisible dédiée comme `PrimaryPart` (point de préhension au bout du manche, pas au centre de la batte), manche et tête entièrement du même côté (-X, loin de la main). L'animation de swing existante (rotation du `Motor6D.C0` entre pose de repos/impact) n'a pas eu besoin d'être retouchée : elle s'applique au même point d'attache, donc suit automatiquement la géométrie corrigée.
      - ⚠️ *Non vérifié en jeu* : le sens exact (-X vs +X) a été déterminé par déduction à partir de la description du bug, pas testé en Studio — si la batte est encore mal orientée après ce fix (ou orientée à l'envers dans l'AUTRE sens), il suffit d'inverser le signe des deux `CFrame.new(-0.7/-1.5, 0, 0)` dans `createBatModel`.
- [x] **Knockback + ragdoll R15** façon Smash Bros
      - `applyKnockback()` → `ragdollCharacter()` : chaque `Motor6D` détaché (`Part0 = nil`) et remplacé par une `BallSocketConstraint` libre, vélocité d'impact + rotation aléatoire appliquées à chaque membre, restauré après `knockbackStunDuration`
- [x] **Bouton taunt** (réservé aux survivants) : touche F (PC) / tap (mobile), son de rire, cooldown anti-spam — `ClownSurvivalEvents.Taunt`/`TauntAvailable`
      - ⚠️ *Son à revoir* : le rire actuel (`LAUGH_SOUND_ID`, `ClownSurvival.luau`) est en place mais jugé pas très pertinent/adapté — à remplacer par un meilleur asset (choix hors scope code, comme le reste des assets audio du projet).
- [x] Passer `RoundDuration` de 90 à 300 (5 min), puis redescendu à **180 (3 min)** par la suite (valeur actuelle du code — la mention "300/5 min" avait fini par ne plus refléter la réalité, corrigé ici et dans `CLAUDE.md` § 1.bis)
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
      - Fenêtres de grâce anti faux-positif : après un knockback (`KNOCKBACK_ANTICHEAT_GRACE`, 1.5s, cas à part vu l'ampleur de la vélocité imposée) et, plus généralement, à **chaque changement d'état de déplacement** (`STATE_TRANSITION_GRACE`, 0.4s — run→idle, run→prone, air→idle à l'atterrissage, etc.) : `getMovementState` change de valeur instantanément mais la vélocité réelle met un court instant à rattraper le nouveau plafond (décélération progressive du contrôleur Humanoid), sans quoi l'anti-triche la clampait/avertissait dès la frame du changement.
      - Étendu au **hub** (`LobbyService.luau`, `stepHubAntiCheat`) : version simplifiée (pas de sprint/glissade dans le hub) qui plafonne la vitesse horizontale (`HUB_MAX_HORIZONTAL` = WalkSpeed par défaut + marge) ET la vitesse verticale montante (`HUB_MAX_UPWARD_SPEED = 60`, bien au-dessus d'un saut normal) pour bloquer speed-hacks et fly-hacks basiques. Ignore les joueurs déjà en partie (gérés par l'anti-triche du round) et le ragdoll (`PlatformStand`).
- [ ] *(non fait)* **Vraie animation de rampement/couché** — actuellement juste un rétrécissement du corps (HipHeight/BodyHeightScale), pas une posture couchée visuelle. Nécessite soit une vraie animation key-framée (Blender ou éditeur d'animation Roblox, uploadée avec un ID) jouée via Animator — je peux écrire tout le code de lecture, mais pas créer l'animation elle-même (asset) — soit, en alternative 100% scriptable mais plus rigide, faire pivoter tout le personnage à l'horizontale. Décision reportée à plus tard.
- [ ] *(non fait)* Ambiance sonore (SFX du rire du bouton taunt à remplacer par un vrai asset) et modèle 3D de batte/clown — nécessite assets, hors scope code
- [x] **Écran "WASTED" (façon GTA)** à l'infection/élimination (`ClownSurvivalStatusScreen.client.luau`) : fondu vers le noir + désaturation d'écran (`ColorCorrectionEffect`) + gros texte "INFECTÉ"/"ÉLIMINÉ" qui apparaît en se resserrant (zoom-out), affiché uniquement au joueur concerné (`ClownSurvivalEvents.StatusScreen`, déclenché depuis `infectPlayer`/`eliminatePlayer`).
- [x] **Panneau "🎪 Effectifs de la partie"** (bouton 📋 haut-droite, `ClownSurvivalRoster.client.luau`) : liste en direct des Clowns 🤡 / Enfants 🧒 / Éliminés 💀 par nom, mise à jour à chaque contamination/élimination/déconnexion. Pas d'info cachée (l'identité clown est déjà visible via le Highlight), juste une vue consolidée. Bouton visible uniquement pour les participants du round (`RosterVisible`), pas pour les joueurs restés au lobby — `broadcastRoster()`/`RosterUpdate` côté `ClownSurvival.luau`.
      - **Fix overlap avec le chrono** : `StatusHud.client.luau` ne mettait pas `IgnoreGuiInset = true` (contrairement aux autres GUI), donc son timer était positionné sous la barre native Roblox au lieu du vrai coin d'écran — chevauchait le bouton du roster selon la plateforme. Timer et bouton alignés sur la même rangée (y=74) haut-droite.
      - **Coordination des panneaux** (`shared/UI/PanelCoordinator.luau`, nouveau) : Classement global / Profil / Effectifs de la partie sont tous centrés au même endroit — en ouvrir un ferme désormais automatiquement les autres s'ils étaient affichés, pour ne pas les empiler.
- [ ] *(non fait)* Vérifier en Studio (2 clients) que le knockback/ragdoll ne propulse pas les joueurs hors des maps existantes

---

## Animation manuelle du swing de batte (remplacement du Heartbeat/Lerp) `[~]` — ⏸️ SUSPENDU (bloqué sur Studio, pas du code)

> **Objectif** : remplacer l'animation procédurale actuelle (`stepBatAnimations()`, CFrame Lerp à
> chaque Heartbeat, `ClownSurvival.luau` lignes ~262-420 et ~831-849) par une vraie animation
> key-framée dans l'**Animation Editor** de Roblox Studio, publiée en asset et jouée via
> `Animator:LoadAnimation`. Rien à faire côté code tant que l'asset n'existe pas.

**Où ça bloque** : en essayant de souder la batte (`Baseball Bat With Spike`) à la main droite
d'un rig de test (Motor6D `BatGrip`, `Part0 = RightHand`, `Part1 = handle de la batte`, créé via
script Command Bar) pour pouvoir l'animer dans l'Animation Editor, la batte ne bouge plus du
tout — ni rotation ni translation — alors même que `BatGrip` apparaît bien dans la liste des
joints sous `RightHand`. Symptôme précis : sélectionner la batte + appuyer sur Rotate affiche le
gizmo ~0.2s puis il disparaît (la pose revient en arrière) — signature typique d'**un second
joint en concurrence** qui réécrase `BatGrip` à chaque frame.

**Piste la plus probable (pas encore confirmée)** : la batte a été insérée comme **Accessory**
Roblox (`Handle` + `Attachment`s type `RightGripAttachment`) — Studio maintient alors
automatiquement un `Weld`/`AccessoryWeld` séparé en plus du `BatGrip` manuel, et les deux se
battent pour la CFrame de la même part. Script de diagnostic (à lancer dans le Command Bar avant
de reprendre) donné en session — cherche tout `Weld`/`WeldConstraint`/`Motor6D`/`Motor`
supplémentaire connecté aux parts de la batte ou à `RightHand`, et vérifie `bat.ClassName` (si
`"Accessory"`, sortir les meshes du wrapper Accessory vers un `Model` simple).

**Pour reprendre** :
1. Lancer le script de diagnostic (liste tous les joints présents sur la batte + RightHand).
2. Si un `Weld`/`AccessoryWeld` en trop apparaît → le supprimer, ne garder que `BatGrip`.
3. Si `bat.ClassName == "Accessory"` → convertir en `Model` simple avant de re-souder.
4. Une fois la batte pilotable, animer dans l'Animation Editor (épaule + coude R15, `BatGrip`
   pour le snap de poignet), publier → récupérer l'`rbxassetid`.
5. Revenir vers moi avec l'ID publié pour brancher `Animator:LoadAnimation` côté serveur et
   retirer `stepBatAnimations()`.

---

## Phase 3 — Méta & rétention  `[~]`

- [x] **Leaderboards** (OrderedDataStore) : Goofy Points global
      - `LeaderboardService.luau` : OrderedDataStore "GoofyPoints_Global_v1", UpdateScore + Refresh
      - `LeaderboardGui.client.luau` : overlay centré (Tab + bouton 🏆 haut-gauche), top 10, joueur local mis en valeur
      - DataService : UpdateScore au chargement + après AddGoofyPoints
      - RoundManager : Refresh après attribution des GP de fin de round
      - ⚠️ Time Trial = « plus bas gagne » → stocker en négatif / inverser à l'affichage (Phase 4)
- [x] **Menu Profil** (bouton 👤 haut-gauche, `ProfileMenu.client.luau`) : panneau à onglets Profil (niveau/XP + barre de progression, Goofy Points, victoires/parties jouées totales, séries de victoires **par gamemode** avec record), Succès (débloqués uniquement, icône/nom/desc via `AchievementsConfig`), Cosmétiques (placeholder "bientôt disponible", système pas encore décidé), Réglages (volume musique/SFX perso, boutons +/− par pas de 10%, appliqué localement via `SoundGroup` + persisté serveur)
      - `DataService.luau` : `GetProfileSnapshot` (RemoteFunction, instantané filtré du profil) + `UpdatePlayerSettings` (RemoteEvent, clamp 0..1 côté serveur) ; TEMPLATE étendu avec `stats.winStreaks`/`stats.bestStreaks` (par gamemode) et `settings.musicVolume`/`settings.sfxVolume`
      - `RoundRunner.luau` : calcule le streak par gamemode à la fin de chaque round (incrémenté sur victoire, remis à 0 sur défaite, `bestStreaks` garde le record)
      - `SoundGroups.server.luau` (nouveau) : crée les `SoundGroup` globaux `Music`/`SFX` sous `SoundService` ; tous les `Sound` de Clown Survival (cri, rire, impact batte) + la respiration d'épuisement y sont routés pour que le réglage ait un effet
      - ⚠️ *Non fait* : aucune musique d'ambiance ne joue encore dans le jeu — le slider "Volume musique" est fonctionnel/persisté mais inerte tant qu'aucun `Sound` n'est routé dans le groupe `Music`
      - **Récompenses d'action en direct (Clown Survival)** — GP accordés pendant le round, pas juste à la fin : +5 GP par kill (`POINTS.KILL`), +10 GP "premier sang" (`POINTS.FIRST_BLOOD`, une fois par round), bonus de combo dès x2 (`POINTS.COMBO_MILESTONES` = x2→5, x3→10, x5→20), donné à CHAQUE coup dès que le palier est atteint — pas juste une fois : un combo x4 donne le bonus du x3 (palier le plus haut atteint), x6+ continue de donner le bonus du x5 indéfiniment (`getComboBonus`) ; côté survivant, symétrique avec des **paliers de survie dans le temps** (`POINTS.SURVIVAL_MILESTONES` : toutes les 30s, 5 GP sur la 1ère moitié du round (0-90s), 10 GP sur la 2ᵉ moitié (90-180s), `stepSurvivalMilestones` en Heartbeat) — global au round (pas par joueur), donné à TOUS les survivants encore non-touchés au moment où le palier de temps est atteint, +15 GP survivant "jamais touché" (`POINTS.NEVER_TOUCHED`, calculé automatiquement en fin de round — l'infection étant permanente, tout participant encore non-infecté/non-éliminé à la fin n'a par construction jamais été touché). Toutes restent dues même si la victoire finale du round est vidée (actions réelles, pas un bonus de victoire).
            - `RoundRunner.luau` injecte `ctx.AwardActionGP(player, amount)` dans le contexte du round : le gamemode reste décorrélé de `DataService`/ProfileStore (comme partout ailleurs), il ne voit que ce callback. `ClownSurvival.GetNeverTouchedSurvivors()` (même pattern que `GetWinnerRoles`/`GetKillCounts`) pour le bonus de fin de round.
      - **Stats par rôle (Clown Survival)** : `stats.clownWins`/`stats.survivorWins` (incrémentées dans `RoundRunner.luau` via `GetWinnerRoles`, seulement sur une victoire "réelle") et `stats.totalClownKills` (une action DANS la partie, créditée même si la victoire finale est vidée) — `ClownSurvival.luau` expose `GetKillCounts()` (même pattern que `GetWinnerRoles()`) pour rester décorrélé de la persistance.
      - **Onglet Profil réorganisé par mode** : la section générique "Séries de victoires par mode" a été remplacée par un bloc par gamemode déjà joué — titre = nom du mode (ex. "CLOWN SURVIVAL", sans emoji), et en dessous les détails propres à ce mode. Pour Clown Survival : Victoire en tant que clown / en tant qu'enfant (sans emoji), Éliminations, Série de victoires (actuelle + record). Tout mode sans stats dédiées retombe sur juste la série de victoires en attendant. **Convention à suivre pour tout nouveau gamemode** : lui donner le même traitement dans `ProfileMenu.client.luau` (`rebuildModesSection`) — un titre + ses lignes de détail pertinentes, sur ce modèle.
      - **Pop "+X GP" façon GTA** (`PlayerStats.client.luau`) : à chaque changement de Goofy Points (`DataUpdated`), le delta (`gp - lastGP`) fait apparaître un label au-dessus du panneau niveau/GP qui monte de `GP_POPUP_RISE` px en s'estompant (fondu texte + contour, `TweenInfo` Quad Out, ~1.1s), vert si gain / rouge si perte. Pops simultanés (ex. kill + palier de combo dans la même frame) empilés verticalement via `activeGPPopups`/`GP_POPUP_STACK_OFFSET` plutôt que superposés. Pas de pop au tout premier `DataUpdated` du chargement (`lastGP` initialisé à `nil`, sinon un retour de session ferait apparaître un pop géant reflétant tout le total).
- [ ] **Cosmétiques** : modèle layered clothing vs accessoires classiques *(décision en attente — mise en pause au profit des classements hebdo/multiples ci-dessous)*
- [x] **Classements hebdomadaires + multiples** (`LeaderboardService.luau` réécrit, `shared/WeekId.luau`, `shared/Config/LeaderboardsConfig.luau`) : 3 boards (Goofy Points, Victoires, Meilleure série) x 2 périodes (ALL TIME cumulatif, HEBDO qui repart à zéro) = 6 `OrderedDataStore`. La période hebdo utilise un nom de store suffixé par le numéro de semaine ISO courant (`WeekId.Current()`, ex. `GG_LB_gp_Weekly_v1_2026-W31`) — changer de semaine revient juste à écrire dans un store neuf, l'ancien reste intact et consultable (pas de tâche de reset planifiée, tout est paresseux).
      - `DataService.luau` : `stats.weekly = {weekId, gp, wins, bestStreak}` + `DataService.EnsureCurrentWeek(player)` (reset paresseux si `WeekId.Current()` a changé). `AddGoofyPoints` pousse GP alltime + hebdo à chaque gain (donc pop GTA et classement hebdo restent synchro).
      - `RoundRunner.luau` : pousse Victoires (alltime + hebdo) à chaque vraie victoire, et Meilleure série (max tous gamemodes confondus, alltime + hebdo) à chaque round joué non vidé.
      - `LeaderboardService.OnRefresh(callback)` (nouveau) : permet à un système 100% serveur (le podium) de se resynchroniser sans passer par le RemoteEvent client.
      - `LeaderboardGui.client.luau` : 2 rangées d'onglets (période x board) pilotées par `LeaderboardsConfig` ; tout le payload (6 listes) est envoyé d'un coup, changer d'onglet ne fait que re-rendre depuis le cache local. Molette native (ScrollingFrame) déjà fonctionnelle, top 25 par liste.
      - **Podium 3D dans le Hub** (`LeaderboardPodium.luau`, nouveau, appelé depuis `LobbyService.Start`) : 3 plateformes or/argent/bronze avec BillboardGui nom+score du top 3, + un panneau `SurfaceGui` avec les mêmes onglets et une liste scrollable (molette native) jusqu'au top 25. 100% serveur — un `TextButton` dans un `SurfaceGui` du monde 3D émet déjà `MouseButton1Click` côté serveur, pas de RemoteEvent nécessaire pour piloter les onglets. Affichage **partagé** entre tous les joueurs (un seul état d'onglet à la fois, façon borne d'arcade). Convention Studio : Part nommée `PodiumAnchor` dans `ServerStorage.Venues.Lobby` (position + orientation, face -Z du panneau) ; sans map Lobby, position de repli fixe.
      - **Comment déplacer le podium** : `ServerStorage.Venues.Lobby` **n'existe pas encore** dans Studio à ce jour — le Hub tourne entièrement sur le repli procédural (zones colorées, voir `ZONE_FALLBACK_POSITIONS` dans `LobbyService.luau`). Deux méthodes selon l'état du projet :
        1. **Si une map Lobby existe dans Studio** (méthode prioritaire, ne touche pas au code) : y placer une Part nommée `PodiumAnchor` à l'endroit voulu, orientée pour que sa face -Z ("Front") regarde vers où les joueurs se tiendront.
        2. **Sinon (cas actuel, pas de map Lobby)** : éditer `FALLBACK_CFRAME = CFrame.new(0, 0, 35)` en haut de `LeaderboardPodium.luau` — coordonnées monde, mêmes repères que les zones procédurales du Hub (`±80` sur X/Z).
      - **Avatars du top 3 sur les socles** : construits à partir du `userId` (pas du `Player` en ligne — le top 3 peut être hors ligne ou sur un autre serveur) via `Players:GetHumanoidDescriptionFromUserId` + `Players:CreateHumanoidModelFromDescription` (rig R15), mis en cache indéfiniment par `userId` (une requête réseau par joueur affiché une seule fois par vie du serveur, pas à chaque changement d'onglet). Présentoir statique (parts anchorées, non solides, scripts de personnage retirés) posé pieds sur le socle, rotation lente continue façon vitrine de boutique. Le `BillboardGui` nom+score est remonté au-dessus de la tête de l'avatar plutôt qu'au-dessus du socle nu.
      - ⚠️ *Non testé en jeu* : `Players:CreateHumanoidModelFromDescription` peut échouer (rate limit, compte introuvable) — géré par `pcall` + cache `false` pour ne pas re-tenter en boucle, mais le rendu visuel de secours (socle vide, juste le nom/score en billboard) n'a pas été vérifié en conditions réelles.
      - **Fix quota DataStore** (`LeaderboardService.luau`) : `UpdateScore` écrivait un `SetAsync` à CHAQUE appel — avec les récompenses d'action très fréquentes (kill, combo, palier de survie toutes les 30s pour chaque survivant), ça remplissait vite la file de requêtes DataStore avec plusieurs joueurs actifs (`"DataStore request was added to queue"`, repéré en test). Écritures désormais regroupées par `(board, période, joueur)` : seule la valeur la PLUS RÉCENTE est retenue, écrite une seule fois après `UPDATE_DEBOUNCE = 10s` d'inactivité sur cette clé. Nouveau `LeaderboardService.Flush()` (écrit immédiatement tout ce qui est en attente, sans annuler les écritures déjà programmées) appelé juste avant le `Refresh()` de fin de round dans `RoundRunner.luau` — sinon le classement affiché juste après un round aurait pu rester en retard jusqu'au prochain cycle automatique (90s).
      - **Limite connue en test Studio** : les comptes simulés de "Test → Clients and Servers" ont des `UserId` négatifs (ex. `-1`), qui n'existent pas côté service Avatar réel — `GetHumanoidDescriptionFromUserId` échoue systématiquement pour eux (confirmé par log `[LeaderboardPodium] Avatar indisponible pour userId -1`), ce n'est pas un bug. Géré proprement (skip silencieux, pas de warn spam pour ce cas prévisible). Fonctionnera normalement en jeu publié (vrais UserId positifs) — **à revérifier avec un vrai compte avant de considérer ce point clos**.
      - **Accord singulier/pluriel** (`LeaderboardsConfig.FormatScore(board, score)`) : "1 victoire" vs "5 victoires", "1 victoire d'affilée" vs "5 victoires d'affilées" — GP reste invariable. Utilisé pour toutes les lignes de classement (panneau UI + podium), pas pour l'en-tête de colonne (qui reste au pluriel, comme un intitulé).
      - **Fix position du panneau 3D** : il apparaissait initialement DEVANT le podium (masquait les socles) — repositionné derrière (+Z local, à l'opposé de la face -Z/"Front" par laquelle les joueurs approchent) et nettement plus haut (au-dessus des avatars + leur billboard nom/score).
      - **Grossissement x3 du panneau, bas ancré** (`BOARD_SCALE = 3`) : panneau 3x plus grand en studs, `PixelsPerStud` divisé par le même facteur pour que tout le layout (déjà défini en pixels fixes) grossisse proportionnellement sans rien retoucher. Le calcul de hauteur du panneau (`buildBoard`) était déjà écrit de façon à ce que le BAS reste fixe quelle que soit `BOARD_H` (seul le centre remonte) — la mise à l'échelle n'a donc pas eu besoin d'ajustement séparé pour l'ancrage.
      - ⚠️ *Non testé en jeu* : le calcul ISO week (`shared/WeekId.luau`) gère les cas limites de bord d'année (semaine 52/53, chevauchement déc/jan) via l'algorithme standard, mais n'a été vérifié qu'en lecture de code, pas en conditions réelles à un changement de semaine.
      - ⚠️ *Non fait* : pas de UI dédiée pour retrouver le rang du joueur courant s'il est hors du top 25 affiché (juste surligné en jaune s'il est dans la liste, comme avant).
      - shop + équipement **serveur** (anti-triche) + aperçu client
- [x] **Achievements + easter eggs** (flags persistés)
      - `AchievementsConfig.luau` (shared) : 14 succès data-driven (progression, gameplay, easter egg)
      - `AchievementService.luau` : conditions par trigger ("gp_change", "round_win", "round_played")
      - `AchievementToast.client.luau` : pop-up animée bas-droit, pile max 3, slide + fade-out
      - `ClownSurvival.GetWinnerRoles()` : distingue clown vs survivant pour achievements ciblés
      - DataService : champ `stats { gamesPlayed, gamesWon }` ajouté au template + Check après GP
      - RoundManager : incrémente stats, Check "round_win" (avec rôle) et "round_played" après chaque round
- [x] **Fix dérive du chrono affiché** — `RoundRunner.luau` calculait le temps restant en comptant les itérations d'une boucle `for ... do task.wait(1) ... end` : `task.wait(1)` ne garantit jamais exactement 1s (léger dépassement à chaque appel), et ça s'accumulait au fil du round (~3s de dérive constatée vers 60s, plus au fil du temps) — le chrono affiché n'était plus synchro avec le temps réel, ni avec les récompenses de survie de `ClownSurvival.luau` (elles basées sur `os.clock()` en continu, donc déjà précises). Le chrono est maintenant recalculé à chaque tick à partir du temps réel écoulé (`os.clock() - loopStartTime`) plutôt que du compteur d'itérations.
- [x] **Victoires "vidées" (rounds avortés par déconnexions)** — `RoundRunner.luau`, générique (tous gamemodes) :
      - Une fin de round PRÉCOCE (via `CheckWin`, pas un timeout normal) où **plus de 50% des participants du round** (`VOID_DISCONNECT_RATIO`) sont partis ET où le round a duré **moins de 20s** (`MIN_MEANINGFUL_ROUND_DURATION`) est traitée comme une victoire vidée — la partie ne s'est pas vraiment jouée.
      - Vidée : pas de bonus GP vainqueur, pas d'incrément `gamesWon`, série de victoires par gamemode gelée (ni incrémentée ni remise à 0), pas de succès "round_win". Conservé : GP de **participation** (15) pour ceux restés jusqu'au bout, `gamesPlayed`, succès "round_played" — ce n'est pas leur faute si la partie s'est vidée.
      - Une victoire rapide mais légitime (personne n'est parti) n'est PAS pénalisée : les deux conditions (durée courte + déconnexions massives) doivent être réunies.
      - `ClownSurvival.CheckWin()` : fix symétrie — un clown seul restant (tout le monde parti) gagne désormais par défaut, comme c'était déjà le cas pour un survivant seul restant.
- [x] **Clown d'urgence** si le dernier clown se déconnecte tôt dans le round (`ClownSurvival.luau`, `EMERGENCY_REINFECT_WINDOW = 20s`) : au lieu de finir la partie (victoire survivants non "réelle"), un survivant présent est désigné au hasard nouveau clown (`promoteRandomSurvivorToClown`) — banner dédié pour lui ("Il n'y a plus de clown dans la partie, tu es infecté !") et pour tout le monde. Reste éligible à la victoire finale du camp clown comme n'importe quel clown (voir règle ci-dessous). Passé les 20 premières secondes, un clown qui se déconnecte termine la partie normalement (survivants gagnants).
- [x] **Changement de règle : tous les clowns actuels gagnent** (`ClownSurvival.luau`, `CheckWin`/`GetWinnerRoles`) — quand le camp clown gagne (tous les enfants infectés/éliminés), TOUS les joueurs actuellement clowns comptent désormais comme gagnants (GP vainqueur, `clownWins`, succès "round_win"), qu'ils l'aient été dès le départ OU contaminés en cours de round. **Revient sur une décision précédente** : jusqu'ici, seuls les infecteurs ORIGINAUX (clowns de départ + clown d'urgence) gagnaient — un enfant contaminé en cours de round "perdait" en se faisant toucher, même si son camp l'emportait au final. Suppression complète du tracking `originalClowns` (devenu inutile, tous les usages retirés) ; `CheckWin()` retourne directement `infectors` (déjà "tous les clowns actuels connectés", filtré en tête de fonction) au lieu de reconstruire une liste filtrée.
- [x] **Changement de règle : le dernier enfant est toujours éliminé, jamais contaminé** (`ClownSurvival.luau`, `infectPlayer`, nouveau `countActiveSurvivors()`) — **revient sur la note ci-dessus** ("comportement du dernier enfant N'A PAS changé") : un coup qui touche le DERNIER enfant restant (`countActiveSurvivors() <= 1` au moment du coup) déclenche désormais toujours `eliminatePlayer` plutôt que `infectPlayer`, quelle que soit la taille de la partie. Repéré en testant à 2 joueurs : avec le plafond de clowns planché à 2 (`computeMaxClowns`), la contamination du seul enfant restant passait toujours (1 clown actif < plafond 2) — l'élimination ne pouvait donc JAMAIS se déclencher dans une partie à 2 joueurs. Message banner d'élimination rendu générique ("💀 Tu es éliminé !", avant : "Trop de clowns dans le parc...") puisqu'il y a maintenant 2 raisons possibles de finir éliminé plutôt que contaminé.
- [x] **`CLOWN_CAP_RATIO` : 40% → 30%, plancher 2 → 1** (`ClownSurvival.luau`, `computeMaxClowns`) — corrige un cas repéré en test à **3 joueurs pile** : `ceil(0.4×3)=2`, donc 2 clowns possibles pour 1 seul enfant restant, SANS aucune élimination (déséquilibre clowns > enfants). Vérifié par calcul (voir conversation) qu'à 30% ce cas précis se referme (`ceil(0.3×3)=1`, le clown de départ sature déjà le plafond, aucune contamination supplémentaire possible pour 3 joueurs) sans casser les autres tailles de partie testées (2 à 16 joueurs). Le plancher à 2 (qui existait pour garantir que le tout premier coup d'une partie fonctionne toujours) est abaissé à 1 : `ceil()` ne peut de toute façon jamais tomber sous 1, et son ancien rôle est désormais couvert autrement par la règle du dernier enfant ci-dessus (un plafond bas ne bloque plus rien, il fait juste basculer plus tôt en élimination — un résultat normal).
      - ⚠️ **Pas définitif, vraie réflexion à avoir** : ce 30% a été choisi pour corriger UN cas précis observé en test (3 joueurs), pas via une vraie passe d'équilibrage/playtest. À revoir sérieusement plus tard, notamment en tenant compte des **déconnexions en cours de partie** — `computeMaxClowns()` recalcule déjà le plafond sur l'effectif ENCORE PRÉSENT (`activePlayers`, pas figé au début du round), mais l'interaction entre ça, ce nouveau ratio, et les règles de "victoire vidée" (`VOID_DISCONNECT_RATIO`/`MIN_MEANINGFUL_ROUND_DURATION` dans `RoundRunner.luau`) n'a pas été retravaillée ensemble — sujets voisins actuellement traités séparément.

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

## Phase 6 — UI complète  `[~]`

> Menu principal, HUD, écran de fin. Chevauche beaucoup l'existant (Jouer/Profil/Réglages/HUD/notifs
> déjà présents mais dispersés dans plusieurs fichiers/panneaux séparés plutôt qu'unifiés) — voir
> détail dans la conversation qui a initié cette phase. Point de départ choisi : écran de fin de
> partie (le plus gros vrai manque, le reste n'était qu'un banner texte).

- [x] **Écran de fin de partie** (`EndScreen.client.luau`, nouveau) : classement stylé des PARTICIPANTS du round (gagnants en tête, puis triés par GP gagnés CE round précis — pas le total cumulé), highlight du joueur local, rôle affiché si le gamemode en a un (🤡 Clown / 🧒 Enfant pour Clown Survival), tag 🏆 sur les lignes gagnantes. Titre contextuel : 🏆 VICTOIRE / 💀 DÉFAITE / ⏱️ PARTIE ANNULÉE (rounds vidés, voir `MIN_MEANINGFUL_ROUND_DURATION`) / fallback générique si le joueur local n'est pas dans les résultats. Bouton **🔄 REJOUER** (relance directement `RequestJoinQueue` pour le MÊME gamemode, sans repasser par le menu de sélection) + **✕ Fermer**. Fade in/out + léger slide, auto-dismiss après 10s (fenêtre de retour au lobby ≈ 8s côté serveur : `RunRound`'s `task.wait(5)` + `LobbyService.RETURN_DELAY` = 3s). S'intègre à `PanelCoordinator` comme les autres panneaux centrés.
      - `RoundRunner.luau` : nouveau `RemoteEvent` `RoundEndSummary`, diffusé uniquement aux participants du round (pas tout le serveur). Nouveau suivi `roundGPEarned` par joueur (wrapper `award()` autour de tous les `DataService.AddGoofyPoints` du round, actions ET bonus de fin) pour distinguer "GP gagnés CE round" du total cumulé du profil.
      - ⚠️ *Non testé en jeu* : lisible/responsive PC uniquement vérifié en lecture de code — pas de vérification tactile mobile (safe zones, taille des boutons) ni de test avec 2+ joueurs réels en Studio.
      - **Titre objectif par camp + sections Clowns/Enfants/Éliminés** : le titre affichait juste "VICTOIRE"/"DÉFAITE" (point de vue du joueur local) — précisé en "🏆 VICTOIRE DES CLOWNS"/"🏆 VICTOIRE DES ENFANTS" pour les gamemodes à rôles (nouveau `summary.winningRole`, calculé côté serveur à partir du statut du premier gagnant), ressenti personnel ("🎉 Tu as gagné !"/"😢 Tu as perdu.") déplacé dans le sous-titre. Classement replacé par un regroupement en sections (même ordre que le panneau "Effectifs de la partie" en direct : 🤡 Clowns → 🧒 Enfants → 💀 Éliminés) au lieu d'un tag de rôle collé au nom sur liste plate ; pas de médaillon de rang dans ce mode groupé (pas de sens dans "Éliminés"), conservé pour les gamemodes sans rôle (liste plate classique, ex. Dodgeball).
            - Nouveau `ClownSurvival.GetParticipantRoles()` : statut ACTUEL (clown/survivor/eliminated) de TOUS les participants, pas juste les gagnants — distinct de `GetWinnerRoles()` qui ne couvre que les gagnants et rétrograde volontairement les clowns infectés en cours de round à "survivor" pour les stats/achievements (règle de jeu : seuls les infecteurs ORIGINAUX comptent comme gagnants, voir `CheckWin`). Les deux cohabitent : `GetWinnerRoles` reste la source pour les stats persistées (`clownWins`/`survivorWins`, inchangé), `GetParticipantRoles` sert uniquement à l'affichage de l'écran de fin.
- [ ] **Menu principal à onglets** (Jouer / Boutique / Inventaire / Niveau / Paramètres) — aujourd'hui ce sont des boutons/panneaux séparés (`PlayButton`, `ProfileMenu`, `LeaderboardGui`...), pas un vrai menu unifié à onglets. Boutique/Inventaire bloqués tant que les cosmétiques ne sont pas tranchés.
- [~] **HUD in-game consolidé** (rôle, timer 3 min, cooldowns) — dispersé aujourd'hui entre `StatusHud`, `PlayerStats`, `ClownSurvivalRoster`, `ClownSurvivalMovementState`. Reste à faire : vraie consolidation en un seul HUD cohérent (pas juste des panneaux séparés côte à côte).
      - [x] **Compte à rebours "prochain cri"** (`ClownSurvivalScreamCountdown.client.luau`, nouveau) : le mécanisme de cri automatique périodique des survivants existait déjà côté serveur (`SCREAM_INTERVAL = 25`, `startScreamLoop`, `ClownSurvival.luau`) — juste aucun indice visuel pour prévenir le joueur avant qu'il ne crie. Nouveau `RemoteEvent` `ScreamCountdown` (`ClownSurvivalEvents`), diffusé aux survivants vivants (pas les clowns) à chaque cycle, désactivé aux mêmes 3 points que `TauntAvailable` (élimination/infection/promotion clown d'urgence). Envoie une **durée** (`SCREAM_INTERVAL`), pas un timestamp serveur (`os.clock()` n'est PAS synchronisé entre machines — piège identifié et corrigé en cours de route) ; le client calcule l'échéance à partir de son propre `os.clock()` à la réception. Pastille sous le bandeau d'annonces (`StatusHud`), texte passe au rouge sous 3s, `TextSize` fixe (pas `TextScaled` — cf. règle des compteurs numériques).
            - **Fix état persistant entre rounds** : un joueur survivant lors d'un round PRÉCÉDENT (widget actif) qui commence le round SUIVANT en clown DE DÉPART ne recevait jamais d'événement pour l'éteindre (contrairement à une infection/élimination EN COURS de round, déjà gérée) — le compte à rebours de l'ancien round restait affiché indéfiniment, figé à 0s une fois écoulé. Même bug pour un survivant qui GAGNE en tenant jusqu'au bout du chrono : `Stop()` remettait déjà à zéro Taunt/Prone/Sprint/Dash/Vision/Roster via `FireAllClients(false)` mais avait oublié `ScreamCountdown`. `screamCountdownEvent:FireAllClients(false)` ajouté dans `Stop()`.
            - **Visible aux CLOWNS aussi** (pas juste les survivants) : les clowns en profitent pour ajuster leur chasse (s'arrêter de bouger pour mieux entendre où le prochain cri va se produire). `broadcastScreamCountdown()` diffuse désormais à tous les participants encore en jeu (`player.Parent and not eliminated[player]`, donc clowns ET survivants), seuls les ÉLIMINÉS ne le voient plus. Les `false` explicites envoyés lors d'une infection (`infectPlayer`/`promoteRandomSurvivorToClown`/clowns de départ dans `Start()`) ont été retirés — devenus inutiles puisqu'on ne veut plus masquer le widget en devenant clown.
            - **Fix dérive vs le chrono de round** : la boucle de cri utilisait `task.wait(SCREAM_INTERVAL)` directement — même classe de bug que la dérive du chrono déjà corrigée dans `RoundRunner.luau` (`task.wait` ne garantit jamais exactement la durée demandée, les dépassements s'accumulaient cycle après cycle). Le cri réel finissait par déraper par rapport au compte à rebours affiché côté client. Corrigé en calculant chaque échéance à partir d'un instant de référence FIXE (`startTime + N × SCREAM_INTERVAL`) plutôt qu'en enchaînant des `task.wait`, empêchant l'erreur de s'accumuler.
            - **Taille réduite** (100×42 au lieu de 176×68, toujours ~2x plus compact) : libellé "PROCHAIN CRI" remis (icône + libellé + compteur empilés sur 2 lignes plutôt que 1 seule, pour garder le texte lisible à cette taille). Agrandi de +20% ensuite via `UIScale` sur le panneau (même technique que `ButtonHover.luau`) plutôt qu'en recalculant chaque taille/position à la main.
            - **Repositionné + reskin** : déplacé du centre-haut (sous le bandeau) vers le **coin bas-droit**, au-dessus du bouton mobile de frappe (`ClownSurvivalInput.client.luau`, 120px à `y=-160`) pour ne pas le chevaucher côté clown sur mobile. Widget "carte" avec barre d'accent colorée (façon toast de succès), icône `🔊` qui pulse en continu (`UIScale` tweené via `sin()`, plus rapide/prononcé sous 3s), libellé + compteur, et une **barre de progression** qui se vide au fil du temps en plus du texte — le tout passant au rouge dans les 3 dernières secondes (texte, barre, icône, contour).
- [x] **Notifications & juice UI** (`shared/UI/UISound.luau`, nouveau) : module partagé `PlayClick()`/`PlayOpen()`/`PlayNotify()`, routé via le `SoundGroup` "SFX" (respecte le réglage de volume perso).
      - **Son d'ouverture centralisé** : `PanelCoordinator.NotifyOpened()` joue `PlayOpen()` automatiquement — TOUS les panneaux centrés (Classement, Profil, Effectifs, écran de fin) en profitent gratuitement, rien à répéter par fichier. Fermeture (`PlayClick()`) ajoutée dans chaque `setVisible(false)`.
      - **Clics** : bouton Jouer + sélection de gamemode + annuler la recherche (`PlayButton`), Rejouer/Fermer (`EndScreen`).
      - **Notifications** (`PlayNotify()`) : pop-in d'un succès (`AchievementToast`), passage de niveau (`PlayerStats`).
      - ⚠️ *IDs placeholder* (`rbxassetid://0`, silencieux tant que non renseignés) : même situation que le rire du taunt/le whoosh du dash déjà dans le projet — le code est prêt, il ne manque que le choix des vrais assets audio (3 IDs à renseigner dans `UISound.luau`, `SOUND_IDS`, pour tout activer d'un coup).
      - **Effet de survol** (`shared/UI/ButtonHover.luau`, nouveau) : léger rétrécissement (x0.94, x0.96 pour les petits boutons d'onglet) au survol souris, retour à la taille normale en quittant — `TweenService`, 0.12s. Rétrécissement CENTRÉ sur le bouton quel que soit son `AnchorPoint` (compensation de Position en pixels via `AbsoluteSize`, sinon le bouton "fond" vers son coin ancré). Appliqué à tous les boutons UI cliquables (Jouer + sélection de gamemode + annuler la recherche, ouvrir/fermer Classement/Profil/Effectifs/écran de fin, onglets Classement/Profil, +/- volume). PC uniquement en pratique (`MouseEnter`/`MouseLeave` ne se déclenchent pas au toucher mobile, pas de régression). **Exclu volontairement** : le podium 3D (`LeaderboardPodium.luau`) — ses boutons sont dans un `SurfaceGui` créé et PARTAGÉ côté serveur entre tous les joueurs qui le voient ; y appliquer ce module tel quel ferait rétrécir le bouton pour TOUT LE MONDE dès qu'UN SEUL joueur passe la souris dessus (documenté en tête de `ButtonHover.luau`). Boutons d'action gameplay (Taunt, Dash/Vision, Sprint/Glissade, batte...) également exclus de cette passe — hors scope "menu/UI", à étendre plus tard si voulu.
      - **Fix bouton Profil disparu** : `require(ButtonHover)` manquant dans `ProfileMenu.client.luau` — le script plantait dès le premier `ButtonHover.Apply(...)` (variable `nil`), ce qui coupait l'exécution AVANT la création du bouton Profil (plus bas dans le fichier). Vérifié que les autres fichiers touchés avaient bien leur `require`.
      - **Réécriture via `UIScale`** (remplace l'approche initiale qui tweenait `Size`/`Position` directement) : deux bugs corrigés d'un coup — (1) le contenu à `TextSize` fixe (texte des boutons "JOUER", sélection de gamemode...) ne suivait pas le rétrécissement du fond du bouton ; (2) les boutons gérés par un `UIListLayout` (onglets, menu de sélection de gamemode Clown Survival/Dodgeball) ne rétrécissaient PAS de façon centrée — modifier `Size` déclenche un recalcul du layout qui réécrase la `Position` selon ses propres règles d'alignement. `UIScale` (enfant du bouton, `Scale` tweené entre 1 et le facteur de réduction) met à l'échelle tout le sous-arbre (texte compris) sans jamais toucher `Size`/`Position` — donc invisible pour `UIListLayout`, et intrinsèquement centré.
      - **Fix emojis des boutons toggle** (Classement/Profil/Effectifs) : premier essai (`TextScaled = true` + `UIPadding`) avait fait grossir les emoji par rapport à leur taille d'origine — revert complet vers le simple `TextSize = 22` fixe d'origine ; le nouveau `ButtonHover` via `UIScale` fait déjà rétrécir l'emoji correctement au survol sans avoir besoin de `TextScaled`.
      - **Fix "petit saut" au survol** (repéré sur les boutons de sélection de gamemode Clown Survival/Dodgeball) : `AutoButtonColor` (activé par défaut sur tout `GuiButton`, même sans le régler explicitement) assombrit/éclaircit le fond INSTANTANÉMENT au survol, sans easing — en conflit avec le tween fluide en `UIScale` : en quittant le bouton, la couleur revenait d'un coup pendant que la taille était encore en train de retrécir/regrossir en douceur. `ButtonHover.Apply()` force désormais `button.AutoButtonColor = false` sur tout bouton auquel il s'applique (notre effet remplace déjà ce retour visuel).
- [ ] **Direction artistique UI** (palette/typo/composants cohérents, safe zones mobile) — chaque panneau a aujourd'hui ses propres couleurs codées en dur, pas de design system partagé.

---

## Idées / backlog (non priorisé)

- Vote des joueurs pour le gamemode (remplacer la rotation auto)
- Menu host (un joueur décide mode + settings)
- Système de parties privées / lobbies
- Daily rewards / streaks
- Clown Survival — mécanique lumières : le clown peut allumer les lumières (avantage pour repérer les enfants ?), les enfants doivent accomplir des tâches pour les éteindre

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
- [x] *(testé en jeu)* Rejoindre/quitter plusieurs fois de suite : Goofy Points/niveau survivent bien à un rejoin.
- [ ] *(non testé, décision assumée)* Cas session-lock (2 sessions simultanées sur le même compte) — **pas testable facilement en Studio** : "Test → Clients and Servers" charge systématiquement des comptes de test différents à chaque client, impossible de simuler 2 sessions du même joueur sans un vrai test en jeu publié (2 fenêtres connectées au même compte). Reporté ; le code (`StartSessionAsync` + retries internes de ProfileStore) est en place et considéré fiable (comportement documenté de la librairie), juste non vérifié manuellement.