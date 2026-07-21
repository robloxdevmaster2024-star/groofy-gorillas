# CLAUDE.md — Goofy Gorillas (Roblox)

> Fichier de contexte lu automatiquement par Claude Code à chaque session.
> Le placer à la **racine du repo** (`Goofy_Gorillas/CLAUDE.md`).

## ⚠️ À FAIRE EN DÉBUT DE CHAQUE SESSION (obligatoire)

1. **Lire ce fichier `CLAUDE.md`** en entier.
2. **Lire `docs/ROADMAP.md`** — c'est la source de vérité de l'avancement et des priorités.
3. Identifier la **phase en cours** et la **prochaine tâche `[ ]`** dans la roadmap avant toute modification.
4. **Après chaque tâche terminée**, mettre à jour `docs/ROADMAP.md` (cocher `[x]`, passer la suivante en `[~]`) **et** la section « État actuel » ci-dessous.

---

## 1. Le jeu

**Goofy Gorillas** est un *party-game / hub à minijeux* sur Roblox, inspiré du jeu du même nom. Concept : un lobby central depuis lequel les joueurs enchaînent des **gamemodes** d'action (Infector, Dodgeball brawl…) sur différentes **venues** (maps). On gagne des **Goofy Points** qui font monter de niveau, on débloque des **cosmétiques**, et entre les rounds on peut jouer à des **activités annexes** (Time Trial, Four in a Row, Gravity arcade). Présence prévue de **voice chat positionnel** et de **combat physique** (knockback basé sur la vélocité — « don't hit each other too hard »).

Cible : **PC + mobile**, avatars **R15**, vue FPS/TPS standard. Toute mécanique doit fonctionner identiquement sur PC et mobile (éviter les dépendances aux inputs spécifiques ; privilégier la détection serveur).

### 1.bis Thème du gamemode Infector — « Le Clown de nuit »

Habillage narratif retenu pour **Infector** (à implémenter, voir `docs/ROADMAP.md` Phase 2/5) :

- **Cadre** : une aire de jeu pour enfants, la nuit — ambiance sombre, stressante, oppressante (éclairage bas, brouillard léger, sons ambiants inquiétants).
- **Rôle infecteur** : un **clown**, gardien de nuit de l'aire de jeu, armé d'une **batte de baseball**.
- **Rôle survivants** : les « enfants » (joueurs non infectés).
- **Contamination** : le clown doit frapper les enfants à la batte. Un coup réussi propulse le joueur touché avec un **knockback fort basé sur la vélocité d'impact**, façon *Super Smash Bros* (envol spectaculaire, pas juste un tag silencieux). Le joueur touché devient à son tour un clown.
- **Durée de session** : **5 minutes (300s)** — le clown doit avoir « chassé » (infecté) tous les enfants avant la fin du temps.
- **Écart avec l'implémentation actuelle** (`server/Gamemodes/Infector.luau`) : contamination par simple proximité (pas d'arme), pas de knockback, `RoundDuration = 90`, pas de direction artistique définie. Ces écarts sont trackés dans la roadmap.

---

---

## 2. Stack & outillage

| Élément | Choix |
|---|---|
| Langage | **Luau** |
| Sync fichiers ↔ Studio | **Rojo** (CLI + plugin Studio) |
| Gestionnaire d'outils | **Rokit** |
| Éditeur | **VS Code** + extension **Luau Language Server** (`JohnnyMorganz.luau-lsp`) + extension Rojo |
| Versionning | Git |
| Persistance (à venir) | **ProfileStore** (données joueur) + **OrderedDataStore** (leaderboards) |

### Commandes utiles

```bash
# Lancer le serveur de sync (à laisser tourner pendant le dev)
rojo serve

# ⚠️ Sur cette machine Windows, `rojo` n'est pas dans le PATH du terminal.
# Si "rojo: not recognized", utiliser le chemin complet :
& "$env:USERPROFILE\.rokit\bin\rojo.exe" serve

# Outils
rokit install        # (ré)installe les outils déclarés dans rokit.toml
rojo --version
```

### Workflow
1. `rojo serve` dans le terminal VS Code (le laisser tourner).
2. Dans Studio : onglet **Plugins → Rojo → Connect**.
3. Coder dans VS Code → la synchro est live.
4. Tester via **Test → Clients and Servers** (Infector nécessite 2 joueurs).
5. `print(...)` visibles dans **View → Output**.

---

## 3. Structure du projet

Mapping défini dans `default.project.json` :

| Dossier disque | Service Roblox |
|---|---|
| `src/server/` | `ServerScriptService.Server` |
| `src/client/` | `StarterPlayer.StarterPlayerScripts.Client` |
| `src/shared/` | `ReplicatedStorage.Shared` |

```
src/
├── server/
│   ├── RoundManager.server.luau      # machine à états des parties
│   └── Gamemodes/
│       └── Infector.luau             # ModuleScript (gamemode)
├── client/
│   └── StatusHud.client.luau         # HUD : bandeau d'annonces + timer
└── shared/
    └── Gamemodes/
        └── Types.luau                # contrat (types) des gamemodes
```

> Note : `src/server` contient un `init.server.luau` (généré par `rojo init`), donc « Server » apparaît comme un **Script** dans l'Explorer, pas un Folder — c'est normal.

### Conventions de nommage Rojo
- `*.server.luau` → **Script** (serveur)
- `*.client.luau` → **LocalScript** (client)
- `*.luau` → **ModuleScript**
- `init.*.luau` → transforme le dossier parent en Script/LocalScript/Module

---

## 4. Architecture

### Round Manager (cœur, côté serveur)
Machine à états en boucle infinie :

```
WAITING (attente du nombre min de joueurs)
   ↓
INTERMISSION (décompte)
   ↓
PREP (LoadCharacter de tous les participants)
   ↓
ROUND (gamemode.Start → boucle CheckWin → ou ResolveTimeout au temps écoulé)
   ↓
END (gamemode.Stop, annonce des gagnants, [TODO] attribution Goofy Points)
   ↓
retour WAITING
```

Le RoundManager crée lui-même le `RemoteEvent` **`ReplicatedStorage.GameStatus`** (annonces serveur → clients). Sélection du gamemode : **rotation aléatoire** pour l'instant (vote/menu host prévus plus tard).

### Contrat des gamemodes (le pattern clé)
Le RoundManager ne connaît **aucun** gamemode spécifique. Chaque mode est un ModuleScript qui implémente la même interface (voir `shared/Gamemodes/Types.luau`) :

```
Name, Description, MinPlayers, RoundDuration, DefaultSettings
Start(ctx)                 -- ctx = { Players, Settings, Map }
CheckWin() -> winners?, reason?     -- fin anticipée si non-nil
ResolveTimeout() -> winners, reason -- qui gagne au temps écoulé
OnPlayerRemoving(player)
Stop()
```

➡️ **Ajouter un gamemode = créer un module conforme dans `src/server/Gamemodes/` et l'ajouter à la liste `AVAILABLE_GAMEMODES` du RoundManager.** Rien d'autre à toucher. C'est ce qui rendra plus tard l'« édition des gamemodes » (settings configurables) quasi gratuite.

### Communication serveur → client
Via `GameStatus:FireAllClients{ kind = "banner"|"timer", text = "..." }`.
Le HUD client (`StatusHud.client.luau`) écoute et affiche.

---

## 5. Règles & conventions de dev (IMPORTANT)

- **Scripts directement** : fournir le code Luau complet, pas de fichiers `.rbxm`.
- **Robustes, bien commentés, personnalisés** au projet (PC + mobile, R15, FPS, personnages standard).
- **Server-authoritative** : toute logique sensible (scoring, infection, équipement, dégâts) est validée **côté serveur** — jamais faire confiance au client (anti-triche).
- **Parité PC/mobile** : préférer les détections serveur (ex. infection par proximité) plutôt que des inputs clients ; toute UI doit être tactile-compatible.
- **Data-driven** : le contenu (cosmétiques, courbe de niveaux, défs d'achievements, settings de gamemode) vit dans des tables de config sous `shared/`, séparé de la logique.
- **Réponses structurées, étapes claires, actionnable avant la théorie.**
- S'inspirer des scripts qui marchent fournis par Clément plutôt que de les copier tels quels.

---

## 6. État actuel ✅

Boucle de jeu minimale **fonctionnelle et testée** :
- `RoundManager.server.luau` — machine à états complète, rotation auto, création du RemoteEvent GameStatus.
- `Gamemodes/Infector.luau` — thème **« Le Clown de nuit »** (voir § 1.bis) : clown(s) de départ au hasard, arme batte via `InfectorEvents.Swing` (hitbox cône `meleeRange`/`MELEE_CONE_DOT`), **knockback vélocité façon Smash Bros** (`AssemblyLinearVelocity` + `Humanoid.PlatformStand`), ambiance sombre via `Lighting` (restaurée au `Stop()`), highlight clown, conditions de victoire survivants/clowns + timeout, `RoundDuration = 300` (5 min).
- `InfectorInput.client.luau` — clic gauche PC + bouton mobile 🏏, actif seulement pour les joueurs devenus clowns (`SetActive` individuel).
- `StatusHud.client.luau` — bandeau d'annonces central + timer coin haut-droit.
- `shared/Gamemodes/Types.luau` — contrat des gamemodes.
- Config actuelle : `MIN_PLAYERS = 2`, intermission 10 s, round Infector 300 s (5 min).

---

## 7. Roadmap

➡️ **La roadmap complète et l'avancement vivent dans [`docs/ROADMAP.md`](docs/ROADMAP.md).**
Ne pas dupliquer les étapes ici : ce fichier reste l'unique source de vérité. La consulter en début de session (cf. encadré tout en haut) pour connaître la phase en cours et la prochaine tâche.

**Prochaine tâche prévue :** DataService (Goofy Points + niveaux via ProfileStore) — Phase 1.

---

## 8. Pipeline Blender → Roblox (rappel)

- Modéliser low/mid-poly (cible mobile), appliquer les transforms (Ctrl+A), UV-unwrap.
- Export **FBX** → import via **Asset Manager → Import 3D**.
- Matériaux PBR via **SurfaceAppearance** (Color / Normal / Roughness / Metalness) — baker le procédural en textures.
- Maps : baisser `CollisionFidelity` (Box/Hull) pour la perf.
- Cosmétiques rigés : `Attachment` aux points R15 → `Accessory`.