# HUB_DESIGN.md — Plan de design du Hub (Aire de jeu)

> Document de référence pour la construction du hub dans Blender/Studio.
> Le code (`LobbyService.luau`) attend des **conventions de nommage précises** (§2) — les respecter
> évite tout travail de code supplémentaire : la map sera reconnue automatiquement.

---

## 1. Concept directeur

**Contraste jour/nuit.** Le hub est l'aire de jeu **de jour** : colorée, insouciante, presque naïve.
Quand un round **Infector** démarre, le code bascule automatiquement l'éclairage vers l'ambiance
nocturne oppressante (`Infector.luau` → `applyDarkAtmosphere()`), déjà scriptée. Le hub ne doit donc
**pas** être sombre par défaut — c'est la bascule qui crée l'effet.

Corollaire pour le design : chaque structure doit être lisible et reconnaissable **dans les deux
éclairages**. Prévoir des accents qui restent visibles dans le noir (néons, éléments réfléchissants) —
voir §5.

---

## 2. Conventions Studio obligatoires (à respecter au pixel près)

Le code cherche exactement cette hiérarchie dans Studio :

```
ServerStorage
└── Venues
    └── Lobby                          (Model)
        ├── SpawnPoints/                (Folder)
        │   └── ... BaseParts           (positions de spawn ; le code ajoute +5 en Y)
        └── (n'importe où dans les descendants)
            └── BasePart avec Attribute "Gamemode" = "Infector" | "Dodgeball"
```

- **`SpawnPoints/`** : un dossier contenant des BaseParts (peuvent être invisibles/`Transparency = 1`,
  juste utilisées comme repères de position). Mets-en 6 à 10, réparties sur la place centrale.
- **Zones de gamemode** : n'importe quel BasePart dans le modèle `Lobby`, tant qu'il a l'**Attribute**
  `Gamemode` réglé sur `"Infector"` ou `"Dodgeball"` (Attributes = onglet dans les Properties de
  Studio, pas un nom d'instance). Cette part sert de **volume de déclenchement** (`Touched`) — elle
  doit englober la zone au sol où le joueur doit marcher pour rejoindre la file. Le code lui ajoute
  automatiquement un `BillboardGui` par-dessus (compteur de joueurs, statut, countdown) : **ne mets
  rien toi-même dessus**, laisse la part "propre" (elle peut être visuellement une simple zone au sol
  en dessous d'une vraie structure décorative).
- Si aucun `ServerStorage.Venues.Lobby` n'existe, le code génère un hub procédural de secours (dalles
  colorées) — donc tu peux tester le jeu avant que le design soit fini, sans rien casser.

---

## 3. Plan d'implantation (vue du dessus)

Échelle de référence utilisée par le fallback procédural actuel (à garder si possible, pour une
taille de map cohérente avec les distances de contamination/portée déjà tunées) :

```
                         (0, 0, +80)
                        ZONE DODGEBALL
                        [terrain clôturé]
                              |
                              |
 (-80,0,0)                   |                    (+80,0,0)
ZONE INFECTOR  ------- PLACE CENTRALE -------  STAND COSMÉTIQUES
[toboggans/                (spawn,               + TOTEM LEADERBOARD
 balançoires]              carrousel)             + MUR ACHIEVEMENTS
                              |
                              |
                         (0, 0, -80)
                    EMPLACEMENTS RÉSERVÉS
                 (Phase 4 : Puissance 4, arcade,
                        Time Trial — vides
                    pour l'instant, juste marqués)
```

- **Place centrale** (rayon ~25 studs) : point de spawn, structure centrale emblématique (carrousel
  ou cage à écureuil), c'est le cœur social du hub.
- **Zone Infector** (côté -X) : littéralement le coin toboggans/balançoires — cohérent avec le thème,
  et ça prépare visuellement le joueur à l'endroit qui va s'assombrir.
- **Zone Dodgeball** (côté +X) : terrain clôturé façon cour de récré (grillage bas, marquages au sol).
- **Stand + totem + mur** (au fond, +Z ou -X selon place dispo) : purement décoratifs pour l'instant
  (voir §6, aucune interactivité requise dans cette passe).
- **Emplacements Phase 4** (-Z) : simples marqueurs au sol (une dalle + un panneau "Bientôt
  disponible"), pas besoin de les construire en détail maintenant.

Garde au moins **15-20 studs de dégagement** entre chaque zone pour éviter que les joueurs se
percutent en se déplaçant entre les files.

---

## 4. Palette de couleurs

### 4.1 Couleurs de zone (à respecter — déjà codées dans les billboards)

| Zone | RGB | Hex | Usage |
|---|---|---|---|
| Infector | `220, 50, 50` | `#DC3232` | Accents structure, marquages sol |
| Dodgeball | `50, 100, 220` | `#3264DC` | Accents structure, marquages sol |
| Défaut (autres zones futures) | `120, 90, 200` | `#785AC8` | Réservé |

### 4.2 Couleur signature "Clown"

| Élément | RGB | Hex | Usage |
|---|---|---|---|
| Rose/magenta clown | `230, 30, 130` | `#E61E82` | Accent sur le carrousel, le stand, tout élément qui doit évoquer le clown (déjà utilisée pour le highlight des joueurs infectés) |

### 4.3 Palette "Jour" (hub par défaut)

Ambiance actuelle codée dans `default.project.json` (Lighting de base) : `Brightness = 2`,
`Ambient = (0,0,0)`, technologie Voxel. Pour le hub de jour, viser des couleurs **saturées et
franches**, typiques d'un playground :

| Élément | Couleur | Matériau |
|---|---|---|
| Structures playground (toboggan, balançoires, carrousel) | Rouge vif, jaune vif, bleu vif, orange | `Plastic` / `SmoothPlastic` (rendu "jouet") |
| Poteaux, chaînes, structures métalliques | Gris acier `(140,140,145)` | `Metal` |
| Sol / allées | Sable clair `(230,210,170)` ou herbe `(90,160,70)` | `Sand`, `Grass` |
| Bancs, clôtures bois | Brun `(120,85,55)` | `WoodPlanks` |
| Stand cosmétiques | Blanc + rayures couleur zone | `SmoothPlastic` |

### 4.4 Palette "Nuit" (référence — déjà scriptée, ne pas construire manuellement)

Ces valeurs sont appliquées automatiquement par `Infector.luau` au démarrage d'un round et restaurées
à la fin — **information pour toi**, pour prévisualiser dans Studio comment tes structures rendront :

| Propriété Lighting | Valeur |
|---|---|
| `ClockTime` | `0` (minuit) |
| `Ambient` | `(20, 20, 30)` |
| `OutdoorAmbient` | `(15, 15, 25)` |
| `FogColor` | `(10, 10, 15)` |
| `FogStart` / `FogEnd` | `15` / `90` studs |
| `Brightness` | `1` |

➡️ **Conséquence concrète** : au-delà de ~90 studs, tout disparaît dans le fog. Les structures
importantes (zones de gamemode, repères de navigation) doivent être **à moins de 90 studs de tout
point où un joueur peut se trouver**, sinon elles deviennent invisibles pendant Infector.

---

## 5. Éléments qui doivent rester visibles la nuit

Ajoute des accents **`Neon`** ou avec `Material = Neon` / `Enum.Material.Neon` (s'auto-illumine, pas
besoin de lumière externe) sur :
- Le contour du carrousel central (guirlande lumineuse).
- Les bords des zones de gamemode (liseré au sol dans la couleur de zone §4.1).
- Les panneaux/enseignes (stand, totem, mur) pour rester lisibles.

Couleurs Neon recommandées : reprendre les couleurs de zone (§4.1) pour les liserés de zone, et le
rose clown (§4.2) pour les accents du carrousel/stand.

---

## 6. Structures — fiches techniques

### 6.1 Carrousel central (place)
- **Rôle** : point de spawn, repère visuel principal, cœur social.
- **Dimensions indicatives** : ~16-20 studs de diamètre, 8-10 studs de haut.
- **Matériaux** : `SmoothPlastic` (couleurs vives, chevaux/animaux stylisés), `Metal` (poteau central,
  armature), liseré `Neon` rose clown en bordure du toit.
- **Détail thématique** (optionnel mais fort) : si tu modélises des animaux de carrousel, des visages
  légèrement "too wide grin" (sourire trop large) sont un bon easter egg discret du thème clown, sans
  être too on-the-nose pour un hub censé rester accueillant de jour.

### 6.2 Zone Infector — coin toboggans/balançoires
- **Volume trigger** : couvrir toute la zone où les joueurs doivent marcher pour rejoindre la file
  (~20x20 studs), `Attribute("Gamemode") = "Infector"`.
- **Décor autour** : toboggan, structure à balançoires, bac à sable.
- **Couleurs** : rouge zone (§4.1) en accent (poteaux, toboggan), reste en palette jour (§4.3).
- **CollisionFidelity** : `Box` ou `Hull` sur toutes les parts complexes (perf mobile, cf. §8).

### 6.3 Zone Dodgeball — terrain clôturé
- **Volume trigger** : ~20x20 studs, `Attribute("Gamemode") = "Dodgeball"`.
- **Décor** : grillage bas (transparent partiellement, `Transparency ≈ 0.3`), marquages au sol façon
  terrain de sport.
- **Couleurs** : bleu zone (§4.1) en accent.

### 6.4 Stand cosmétiques (décoratif pour l'instant)
- **Forme** : petit kiosque/camion façon marchand de glace.
- **Couleurs** : blanc + rayures dans une couleur de zone, ou rose clown en accent toit.
- **Pas d'interactivité à construire maintenant** — la logique shop viendra plus tard (décision
  layered clothing vs accessoires encore en attente, voir `ROADMAP.md`). Prévoir juste un
  emplacement clair et un `ProximityPrompt` placeholder si tu veux, mais non requis.

### 6.5 Totem leaderboard
- **Forme** : totem/obélisque ou panneau de score vertical, ~8-10 studs de haut.
- **Rôle actuel** : purement décoratif (le leaderboard fonctionne déjà via overlay UI, Tab ou bouton
  🏆). Pas besoin de l'alimenter en données 3D pour l'instant.
- **Couleurs** : métal + liseré doré/or pour évoquer un trophée.

### 6.6 Mur des Achievements
- **Forme** : mur ou panneau large, ~10-15 studs de large.
- **Rôle actuel** : décoratif (les achievements sont déjà notifiés via toast client).
- **Couleurs** : fond sombre neutre avec liseré coloré, façon "Wall of Fame".

### 6.7 Emplacements Phase 4 (réservés)
- Une dalle au sol + un panneau texte "Bientôt disponible" par activité (Puissance 4, arcade
  gravité, Time Trial). Pas de structure détaillée requise maintenant.

---

## 7. UI (état actuel — pas de travail requis de ton côté)

Toute l'UI du hub est déjà **en overlay écran** (ScreenGui), indépendante du design 3D :

| UI | Fichier | Position écran |
|---|---|---|
| Statut de zone / countdown | `LobbyHud.client.luau` | Bas-centre |
| Stats joueur (niveau, GP, progression) | `PlayerStats.client.luau` | Bas-gauche |
| Leaderboard global | `LeaderboardGui.client.luau` | Overlay centré (Tab ou bouton 🏆 haut-gauche) |
| Achievements (toasts) | `AchievementToast.client.luau` | Bas-droite |
| Settings host (pendant countdown) | `SettingsMenu.client.luau` | Haut-droite |

➡️ Aucune UI 3D (BillboardGui autre que celui des zones, déjà généré par le code) n'est nécessaire.
Si tu veux plus tard rendre le totem/mur interactifs (ex. ouvrir le leaderboard en s'approchant), ce
sera un ajout de code séparé, pas un sujet de design — dis-le-moi quand tu y es et je le branche.

---

## 8. Pipeline & contraintes techniques (rappel)

- Modéliser low/mid-poly (cible mobile), appliquer les transforms (Ctrl+A), UV-unwrap.
- Export **FBX** → import via **Asset Manager → Import 3D** dans Studio.
- Matériaux PBR via **SurfaceAppearance** uniquement si tu veux du photoréalisme — pour ce style
  cartoon/jouet, les `Material` standards de Roblox (`Plastic`, `SmoothPlastic`, `Neon`, `Metal`,
  `WoodPlanks`, `Sand`, `Grass`) suffisent et coûtent moins cher en perf.
- **CollisionFidelity** : `Box` ou `Hull` sur toutes les structures complexes (perf mobile).
- Une fois le modèle importé dans Studio, organise-le en respectant **exactement** la hiérarchie du
  §2 (`ServerStorage.Venues.Lobby`, `SpawnPoints/`, Attributes `Gamemode`) — le code reconnaîtra la
  map automatiquement sans que j'aie besoin de retoucher `LobbyService.luau`.

---

## 9. Checklist avant de considérer le hub "prêt"

- [ ] `ServerStorage.Venues.Lobby` existe avec `SpawnPoints/` (6-10 points)
- [ ] Zone Infector : BasePart avec `Attribute("Gamemode") = "Infector"`, volume couvrant la zone de
      marche
- [ ] Zone Dodgeball : idem avec `"Dodgeball"`
- [ ] Toutes les structures importantes sont à moins de 90 studs de tout point accessible (contrainte
      fog nocturne, §4.4)
- [ ] Accents `Neon` posés sur carrousel + bordures de zones (visibilité nocturne, §5)
- [ ] `CollisionFidelity` réglé sur les parts complexes
- [ ] Test en Studio (`rojo serve` + Connect) : les billboards de zone apparaissent bien au-dessus
      des zones construites, sans se superposer à du décor
