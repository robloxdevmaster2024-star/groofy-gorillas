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
- [x] **Knockback + ragdoll R15** façon Smash Bros
      - `applyKnockback()` → `ragdollCharacter()` : chaque `Motor6D` détaché (`Part0 = nil`) et remplacé par une `BallSocketConstraint` libre, vélocité d'impact + rotation aléatoire appliquées à chaque membre, restauré après `knockbackStunDuration`
- [x] **Bouton taunt** (réservé aux survivants) : touche F (PC) / tap (mobile), son de rire, cooldown anti-spam — `ClownSurvivalEvents.Taunt`/`TauntAvailable`
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
- [ ] **Cosmétiques** : modèle layered clothing vs accessoires classiques *(décision en attente)*
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
- [x] **Clown d'urgence** si le dernier clown se déconnecte tôt dans le round (`ClownSurvival.luau`, `EMERGENCY_REINFECT_WINDOW = 20s`) : au lieu de finir la partie (victoire survivants non "réelle"), un survivant présent est désigné au hasard nouveau clown (`promoteRandomSurvivorToClown`) — banner dédié pour lui ("Il n'y a plus de clown dans la partie, tu es infecté !") et pour tout le monde. Marqué `originalClowns` (pas de sa faute d'être forcé dans ce rôle), reste éligible à la victoire finale du camp clown. Passé les 20 premières secondes, un clown qui se déconnecte termine la partie normalement (survivants gagnants).

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
- [x] *(testé en jeu)* Rejoindre/quitter plusieurs fois de suite : Goofy Points/niveau survivent bien à un rejoin.
- [ ] *(non testé, décision assumée)* Cas session-lock (2 sessions simultanées sur le même compte) — **pas testable facilement en Studio** : "Test → Clients and Servers" charge systématiquement des comptes de test différents à chaque client, impossible de simuler 2 sessions du même joueur sans un vrai test en jeu publié (2 fenêtres connectées au même compte). Reporté ; le code (`StartSessionAsync` + retries internes de ProfileStore) est en place et considéré fiable (comportement documenté de la librairie), juste non vérifié manuellement.