# Goofy Gorillas — Brief complet (jeu, règles, univers graphique)

> Document autonome, pensé pour être copié-collé dans une conversation avec une IA (Claude ou autre)
> afin d'affiner la direction artistique du décor. Il contient tout le contexte nécessaire sans
> supposer d'accès au code du projet.

---

## 1. Type de jeu

**Goofy Gorillas** est un *party-game / hub à minijeux* multijoueur sur Roblox, dans l'esprit de
jeux comme *Fall Guys* ou du party-game mobile du même nom. Un **lobby central** (l'aire de jeu) sert
de point de rassemblement social depuis lequel les joueurs rejoignent des **gamemodes** courts et
intenses. Entre les parties, on progresse (points, niveaux, cosmétiques, succès).

**Plateformes cibles** : PC + mobile, avatars Roblox standards **R15**, vue à la troisième/première
personne classique. Toute mécanique doit fonctionner identiquement sur les deux plateformes.

**Ton général** : le nom "Goofy" annonce un jeu fun et absurde façon party-game familial — mais le
gamemode phare (voir §2.2) introduit une tension volontaire avec une ambiance horrifique légère,
façon bascule jour/nuit. Le jeu n'est **pas** un survival-horror sérieux ; c'est un party-game coloré
qui flirte avec l'inquiétant sur un mode précis, sans jamais devenir glauque ou gore.

---

## 2. Règles du jeu

### 2.1 Boucle générale (hub)

1. Les joueurs spawnent dans le **hub** (l'aire de jeu), un espace social libre.
2. Des **zones au sol**, une par gamemode, servent de file d'attente : marcher dessus rejoint la
   queue. Un affichage flottant montre le nombre de joueurs et le statut (en attente / prêt /
   lancement).
3. Dès qu'assez de joueurs sont dans une file (variable selon le mode, 2 minimum), un **countdown de
   15 secondes** démarre. Pendant ce countdown, le premier joueur connecté ("host") peut ajuster
   certains paramètres du mode (ex. nombre d'infecteurs de départ).
4. Le round démarré, les joueurs sont téléportés sur la map du gamemode. Un seul round tourne à la
   fois sur le serveur.
5. À la fin du round (victoire ou temps écoulé), les gagnants sont annoncés, des points sont
   distribués, puis tout le monde revient au hub après quelques secondes.
6. Progression méta : points ("Goofy Points") → niveaux → cosmétiques à débloquer (système en cours
   de conception) ; succès/achievements avec notifications ; classement global affiché en overlay.

### 2.2 Gamemode phare — Clown Survival, dit **« Le Clown de nuit »**

C'est le mode le plus caractéristique du jeu, celui qui porte l'identité visuelle forte.

**Prémisse** : l'aire de jeu, la nuit. Un **clown**, gardien de nuit du lieu, armé d'une **batte de
baseball**, chasse les autres joueurs ("les enfants"). Quand il frappe quelqu'un, ce joueur est
propulsé violemment dans les airs (façon *Super Smash Bros* — un vrai envol spectaculaire, pas un
simple recul) puis se transforme lui-même en clown et rejoint la chasse.

**Règles précises** :
- 1 (ou plusieurs, configurable) clown au départ, choisi au hasard parmi les joueurs.
- Le clown frappe avec sa batte dans un cône devant lui, à courte portée (quelques mètres), avec un
  temps de recharge entre deux coups (~1 seconde).
- Un coup réussi : la victime s'envole (knockback), perd le contrôle de son personnage pendant
  environ une seconde, devient clown à son tour (elle obtient elle aussi une batte et peut chasser).
- **Durée du round : 5 minutes.**
- **Le camp des clowns gagne** si tous les autres joueurs ont été transformés avant la fin du temps.
- **Le camp des "enfants" survivants gagne** si le temps s'écoule sans que tout le monde soit
  transformé (seuls ceux qui n'ont jamais été touchés comptent comme gagnants).
- Twist : si les clowns gagnent, seuls les clowns **du tout début** (pas ceux convertis en cours de
  partie) sont considérés vainqueurs — being converti reste une "défaite" narrative même si ton camp
  gagne à la fin.
- **Ambiance** : au lancement du round, l'éclairage bascule d'un hub lumineux et coloré vers une
  ambiance sombre, oppressante, avec du brouillard dense (visibilité réduite à quelques dizaines de
  mètres) — le sentiment recherché est le stress et la traque, sans gore ni violence graphique
  explicite.

### 2.3 Gamemode secondaire — Dodgeball

Un brawl de ballons classique : les joueurs se lancent des balles, dernier debout gagne. Ce mode
**ne partage pas** l'ambiance horrifique de Clown Survival — il reste dans le ton "fun/goofy" par défaut du
hub, en franc contraste. Utile pour rappeler que le jeu n'est pas *que* de l'horreur.

### 2.4 Méta-progression (contexte, moins prioritaire pour le décor)

Points de jeu cumulables, courbe de niveaux, classement global visible en jeu, succès à débuts variés
(progression, exploits en partie, easter eggs), et un système de cosmétiques à venir (non finalisé).

---

## 3. Univers graphique — ce qui est déjà tranché

- **Registre visuel** : cartoon/jouet, pas réaliste. Formes simples, couleurs saturées, silhouettes
  lisibles de loin — cohérent avec l'esthétique low-poly typique de Roblox et avec le ton "party-game
  familial" du nom Goofy Gorillas.
- **Contraste jour/nuit comme moteur central** : le hub (et la map Clown Survival avant le round) est
  lumineux, coloré, presque naïf. Dès qu'un round Clown Survival démarre, l'éclairage devient nocturne et
  angoissant. C'est cette **bascule** qui doit porter l'effet horrifique, pas un décor qui serait
  sombre en permanence.
- **Couleurs d'identité déjà figées** (utilisées ailleurs dans l'UI du jeu, à respecter pour la
  cohérence) :
  - Rouge vif `#DC3232` associé au gamemode Clown Survival.
  - Bleu vif `#3264DC` associé au gamemode Dodgeball.
  - Rose/magenta vif `#E61E82` = couleur signature du "clown" (utilisée sur les joueurs transformés).
- **Contrainte du brouillard nocturne** : pendant un round Clown Survival, le brouillard rend tout ce qui
  dépasse ~90 mètres invisible, et l'ambiance générale est très sombre (proche du noir). Tout élément
  de décor important doit soit être proche du joueur, soit porter des accents lumineux
  auto-éclairés (façon néon) pour rester visible.
- **Cible technique** : mobile + PC, donc plutôt low/mid-poly, matériaux simples (pas de rendu
  photoréaliste type PBR lourd).

---

## 4. Univers graphique — questions ouvertes à approfondir

C'est la partie sur laquelle un retour créatif est recherché. Points à trancher :

1. **Curseur d'horreur** : jusqu'où pousser le "creepy" ? Repères possibles — plutôt léger et
   suggestif (une ombre, un silence soudain, rien de choquant montré), ou plus marqué façon
   attraction hantée de fête foraine (visages déformés, distorsions), en restant familial (pas de
   gore, pas de sang) ?
2. **Design du clown** : costume de cirque classique très coloré et flamboyant, ou plutôt un
   costume usé, sale, "abandonné" — cohérent avec l'idée d'un gardien de nuit seul depuis longtemps
   dans un parc désert ?
3. **Style des structures de l'aire de jeu** : reproduction assez fidèle d'un vrai playground pour
   enfants (toboggans, balançoires, bac à sable réalistes en proportions), ou version exagérée/jouet
   (couleurs suraturées, formes arrondies excessives, échelle légèrement décalée) ?
4. **Niveau de texture/finition** : rendu "flat shaded" très cartoon (à la Fall Guys, couleurs unies
   sans texture), ou décor texturé avec un peu d'usure/rouille pour suggérer le passage du temps et
   l'abandon nocturne ?
5. **Indices narratifs présents même de jour** : le hub de jour doit-il être parfaitement propre et
   innocent (le twist nocturne surprend totalement), ou y glisser de petits indices discrets
   (affiche de clown légèrement déchirée, jouet cassé dans un coin, une caméra de surveillance) que
   les joueurs attentifs peuvent repérer ?
6. **Traitement des couleurs la nuit** : les couleurs vives du jour doivent-elles rester
   partiellement reconnaissables sous l'éclairage nocturne (juste assombries), ou le contraste
   doit-il être total (quasi noir et blanc, seuls les accents néon ressortent) ?
7. **Échelle par rapport à l'avatar** : les avatars Roblox R15 standards font environ 5 unités
   ("studs") de haut — les structures doivent-elles paraître normales à cette échelle, ou légèrement
   surdimensionnées pour accentuer un sentiment d'être "petit" face au clown ?
8. **Ambiance sonore** (hors décor visuel mais lié à la direction artistique) : musique de fête
   légèrement dissonante en fond permanent, ou silence quasi total qui se brise au lancement du
   round nocturne ?

---

## 5. Éléments de décor à concevoir (liste des assets)

- **Structure centrale du hub** : un élément emblématique et social (ex. carrousel) servant de point
  de repère et de spawn.
- **Zone du gamemode Clown Survival** : coin toboggans/balançoires/bac à sable — c'est l'endroit qui
  s'assombrit quand le round démarre, donc son design de jour doit "annoncer" discrètement ce basculement.
- **Zone du gamemode Dodgeball** : terrain clôturé façon cour de récréation/terrain de sport.
- **Éléments décoratifs secondaires** : un stand (type kiosque/camion de glaces, pour un futur shop
  cosmétique), un totem/panneau de classement, un mur d'affichage des succès.
- **Emplacements réservés** pour de futures activités annexes (jeu de plateau grandeur nature, borne
  d'arcade, parcours chronométré) — pas besoin de détail poussé pour l'instant, juste des marqueurs
  au sol cohérents avec le style général.
- **Le personnage du clown lui-même** (tenue, batte de baseball) — c'est l'asset le plus visible et
  le plus important pour l'identité du jeu.
- *(Optionnel)* une tenue "enfant" par défaut si on veut aller au-delà des avatars Roblox standards.

---

## 6. Contraintes techniques à respecter dans toute proposition

- Modélisation low/mid-poly, pensée pour mobile.
- Formes et silhouettes lisibles à distance, y compris dans le brouillard nocturne.
- Pas de dépendance à des shaders/matériaux avancés non standards — rester dans les matériaux de
  base disponibles nativement (plastique, métal, bois, néon, sable, herbe, etc.).
- Les proportions doivent rester cohérentes avec des avatars humanoïdes standards Roblox.
- Le jeu tourne sur un seul serveur à la fois avec un round actif — pas de contrainte de LOD/streaming
  complexe à prévoir, la map reste de taille modeste (quelques centaines de mètres).
