# Maxwell

L'assistant personnel de Max sur son Mac, façon Jarvis. Son nom vient d'un vrai nom de majordome, avec un clin d'œil au « démon de Maxwell », qui trie sans relâche.

C'est une app de barre de menus qui fait deux choses :

- **Suivi d'activité** : le temps passé dans chaque application, rangé par catégorie, avec un récap jour / semaine / mois.
- **Étagère** : on secoue la souris en faisant glisser des fichiers, une petite fenêtre flottante les garde le temps d'aller les déposer ailleurs, façon Dropover.

## Lancer

```bash
./build.sh --install
```

Compile, installe dans `/Applications` et lance l'app (monogramme M dans la barre de menus).

## Partager avec des amis

```bash
./release.sh 0.2.0 "Ce qui change dans cette version"
```

Publie une release GitHub avec l'app zippée et l'`appcast.xml`. La procédure complète est dans [RELEASING.md](RELEASING.md). Les apps déjà installées la proposent d'elles-mêmes grâce à [Sparkle](https://sparkle-project.org), ou via ⚙︎ → « Rechercher les mises à jour… ». Les mises à jour sont signées avec une clé EdDSA rangée dans le Trousseau (compte « Maxwell ») : sans elle, plus de mise à jour possible pour les copies installées.

L'app n'est pas signée par un compte Apple Developer. Au premier lancement, macOS la bloque : il faut aller dans Réglages système → Confidentialité et sécurité → « Ouvrir quand même ». Il faut aussi macOS 26.

## Fonctionnement

Le vocabulaire (session, temps actif, catégorie, récap…) est défini dans [GLOSSARY.md](GLOSSARY.md).

- Une **session** = une app au premier plan entre deux instants. Elle est sauvegardée toutes les 5 s.
- Le suivi s'arrête après **3 min sans clavier ni souris**, ou quand le Mac dort ou que l'écran est verrouillé.
- Chaque app a une **catégorie**. Les nouvelles apps sont classées par le modèle d'Apple Intelligence, sur le Mac (macOS 26 ou plus). Sans Apple Intelligence, elles restent « À classer ».
- Clic droit sur une app pour changer sa catégorie ; la fenêtre **Catégories** gère la liste. La catégorie Système est masquée par défaut, et son temps n'est pas compté.
- Une notification résume la semaine le lundi à 9 h, et le mois le 1er à 9 h.
- Données en local, dans `~/Library/Application Support/Maxwell/activity.sqlite`. Rien ne quitte le Mac : la seule connexion est la recherche de mises à jour sur GitHub, qui n'envoie aucune donnée.

## Code

| Fichier | Rôle |
|---|---|
| `AppModel.swift` | Objets de l'app et fenêtres (récap, catégories) |
| `Tracker.swift` | Détection de l'app active, de l'inactivité et de la veille |
| `Database.swift` | Stockage SQLite : sessions, catégories, agrégats |
| `Categorizer.swift` | Classement automatique des apps par Apple Intelligence |
| `RecapNotifier.swift` | Notifications de récap hebdo et mensuel |
| `Updater.swift` | Mises à jour par Sparkle |
| `MenuBarView.swift` | Résumé du jour dans la barre de menus |
| `RecapView.swift` | Fenêtre de récap par catégorie, avec graphique |
| `CategoriesView.swift` | Gestion des catégories et de la catégorie de chaque app |
| `Theme.swift` | Couleurs, rang des catégories et composants partagés |
| `Period.swift` | Découpage jour / semaine / mois |
| `Snapshot.swift`, `DemoData.swift` | Captures de l'interface avec des données de démo |
| `Shelf/ShakeDetector.swift` | Reconnaissance de la Secousse, à partir des positions de la souris |
| `Shelf/DragShakeMonitor.swift` | Suivi de la souris pendant un glisser de fichiers, dans toutes les apps |
| `Shelf/Shelf.swift` | Contenu de l'Étagère : références vers les fichiers déposés |
| `Shelf/ShelfController.swift` | L'Étagère au complet : réglage, Secousse, fenêtre flottante |
| `Shelf/ShelfView.swift` | Carte de l'Étagère : zone de dépôt, pile de fichiers, liste dépliée |
| `Shelf/FileDragSource.swift` | Glisser des fichiers hors de l'Étagère, avec le comportement du Finder |
| `Shelf/Thumbnails.swift` | Aperçus Quick Look des fichiers, gardés en mémoire |
| `Shelf/ShelfActions.swift` | Afficher dans le Finder, ouvrir, copier |

## Design

Le vert de l'app marque ce qui compte : l'app en cours et les quatre catégories les plus utilisées de la période, de la plus foncée à la plus claire. Les autres restent en gris. Les captures de référence sont dans `docs/design/`.

Pour redessiner chaque écran en PNG, en clair et en sombre, avec des données de démo et sans toucher aux tiennes :

```bash
./build.sh && build/Maxwell.app/Contents/MacOS/Maxwell --snapshot captures
```

Les effets Liquid Glass (segment sélectionné, sélection de la barre latérale, fond des boutons de la barre d'outils) sont dessinés par macOS à l'écran et n'apparaissent pas sur ces captures.

## Étagère

Une [Étagère](GLOSSARY.md) façon Dropover, en références seulement : les fichiers restent à leur place jusqu'au dépôt, et l'Étagère disparaît quand l'app redémarre.

- **Faire apparaître** : en faisant glisser des fichiers, une Secousse (dans n'importe quelle direction) fait glisser l'Étagère depuis le bord droit de l'écran, à la hauteur du curseur. Elle reste au-dessus des fenêtres, sur tous les bureaux, et disparaît seule si on n'y dépose rien.
- **Reprendre** : on fait glisser la pile pour tout déposer ailleurs. Comme depuis le Finder, les fichiers sont déplacés sur le même disque, copiés vers un autre disque ou avec ⌥. Les fichiers déplacés quittent l'Étagère, qui se ferme une fois vide.
- **Un par un** : un clic sur la pile la déplie en liste, pour faire glisser un seul fichier ; double-clic pour l'ouvrir, clic droit pour l'afficher dans le Finder ou le retirer.
- **Aperçus** : la pile et la liste montrent les fichiers comme le Finder (première page d'un PDF, image réduite), grâce à Quick Look.
- **Actions** : le bouton « … » et le clic droit proposent Afficher dans le Finder, Copier (⌘V dans le Finder en colle une copie), Partager (AirDrop, Mail, Messages…) et Vider l'Étagère.
- **Fermer** : le × vide l'Étagère.
- **Réglages** (roue dentée du menu) : « Ouvrir l'Étagère » sans secouer, et « Secouer pour ouvrir l'Étagère » pour activer ou couper la Secousse. Coupée, Maxwell n'écoute plus du tout la souris.

Une Secousse, c'est trois changements de sens francs (plus de 120°) de 30 pt minimum en moins de 0,75 s, dans n'importe quelle direction (réglable dans `ShakeDetector.swift`). Chaque glisser de fichiers laisse une trace dans le journal :

```bash
/usr/bin/log show --last 10m --predicate 'subsystem == "com.max.Maxwell"'
```

## Tests

```bash
swift test
```

## Pistes

- Suivre les sites visités dans les navigateurs (permission Automatisation), pour découper « Navigation ».
- Export CSV.

## Icône

L'icône (monogramme M en barres) est dessinée par `Scripts/make-icon.swift`, qui produit `Resources/AppIcon.icns`. Après une modification du dessin, relance :

```bash
swift Scripts/make-icon.swift
```

La version de la barre de menus est dessinée dans `MenuBarIcon.swift`.
