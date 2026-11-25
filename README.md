# Maxwell

L'assistant personnel de Max sur son Mac, façon Jarvis. Son nom vient d'un vrai nom de majordome, avec un clin d'œil au « démon de Maxwell », qui trie sans relâche.

C'est une app de barre de menus qui fait trois choses :

- **Suivi d'activité** : le temps passé dans chaque application, et sur chaque site dans Chrome, rangé par catégorie, avec un récap jour / semaine / mois.
- **Tâches** : une liste de tâches, qu'on remplit en deux secondes depuis n'importe quelle app avec ⌃⌥Espace.
- **Étagère** : on secoue la souris en faisant glisser des fichiers, une petite fenêtre flottante les garde le temps d'aller les déposer ailleurs, façon Dropover.

## Lancer

```bash
./build.sh --install
```

Compile, installe dans `/Applications` et lance l'app (monogramme M dans la barre de menus). L'app est signée avec le certificat auto-signé « Maxwell Self-Signed » du Trousseau, pour que macOS garde ses autorisations d'une compilation à l'autre. Sans lui, elle est signée ad hoc et macOS redemande l'accès à Chrome à chaque fois.

## Partager avec des amis

```bash
./release.sh 0.2.0 "Ce qui change dans cette version"
```

Publie une release GitHub avec l'app zippée et l'`appcast.xml`. La procédure complète est dans [RELEASING.md](RELEASING.md). Les apps déjà installées la proposent d'elles-mêmes grâce à [Sparkle](https://sparkle-project.org), ou via ⚙︎ → « Rechercher les mises à jour… ». Les mises à jour sont signées avec une clé EdDSA rangée dans le Trousseau (compte « Maxwell ») : sans elle, plus de mise à jour possible pour les copies installées.

L'app n'est pas signée par un compte Apple Developer. Au premier lancement, macOS la bloque : il faut aller dans Réglages système → Confidentialité et sécurité → « Ouvrir quand même ». Il faut aussi macOS 26.

## Fonctionnement

Le vocabulaire (session, temps actif, catégorie, récap…) est défini dans [GLOSSARY.md](GLOSSARY.md).

- Une **session** = une app au premier plan entre deux instants. Elle est sauvegardée toutes les 5 s.
- Dans **Chrome**, Maxwell lit l'onglet actif toutes les 2 s : changer de site démarre une nouvelle session, et le récap détaille le temps passé sur `github.com` ou `mail.google.com` : les sites de moins de 10 min n'y apparaissent qu'avec « Tout afficher ». Les sites restent dans la catégorie de Chrome, sauf ceux qu'on range ailleurs d'un clic droit. Seul le nom du site est gardé, et la navigation privée n'est pas suivie. La première fois, macOS demande l'autorisation de « contrôler Google Chrome » ; sans elle, Chrome compte comme une seule app.
- Le suivi s'arrête après **3 min sans clavier ni souris**, ou quand le Mac dort ou que l'écran est verrouillé.
- Chaque app a une **catégorie**. Les nouvelles apps sont classées par le modèle d'Apple Intelligence, sur le Mac (macOS 26 ou plus). Sans Apple Intelligence, elles restent « À classer ».
- Clic droit sur une app ou un site pour changer sa catégorie ; la fenêtre **Catégories** gère la liste. La catégorie Système est masquée par défaut, et son temps n'est pas compté.
- Une notification résume la semaine le lundi à 9 h, et le mois le 1er à 9 h.
- Données en local, dans `~/Library/Application Support/Maxwell/activity.sqlite`. Rien ne quitte le Mac de lui-même : la seule connexion automatique est la recherche de mises à jour sur GitHub, qui n'envoie aucune donnée.

## Code

| Fichier | Rôle |
|---|---|
| `AppModel.swift` | Objets de l'app et fenêtres (Maxwell, catégories) |
| `Console.swift` | Fenêtre Maxwell : style Console, onglets Temps et Tâches |
| `Tracker.swift` | Branchement du suivi sur le Mac : app active, inactivité, veille, Chrome |
| `SessionRecorder.swift` | Règles des Sessions : Inactivité, Pause, changement d'App ou de Site |
| `ChromeTab.swift` | Site de l'onglet actif de Chrome, lu par Apple Events |
| `Database.swift` | Stockage SQLite : sessions, catégories des apps et des sites |
| `Recap.swift` | Le Récap d'une période : total, comparaison, Catégories classées, répartition |
| `RecapSource.swift` | Récaps tenus à jour pour les vues, à chaque tick et changement de Catégorie |
| `Categorizer.swift` | Catégorisation : choix de Max, origine de chaque Catégorie, classement par Apple Intelligence |
| `DefaultCategories.swift` | Catégories créées d'office : nom, pictogramme, teinte, précision pour le modèle |
| `RecapNotifier.swift` | Notifications du Récap de la semaine et du mois |
| `Updater.swift` | Mises à jour par Sparkle |
| `MenuBarView.swift` | Récap du jour dans la barre de menus |
| `RecapView.swift` | Module Temps : le Récap par catégorie, avec graphique |
| `CategoriesView.swift` | Gestion des catégories et de la catégorie de chaque app |
| `Theme.swift` | Couleurs, teinte de chaque catégorie et composants partagés |
| `Period.swift` | Découpage jour / semaine / mois |
| `Snapshot.swift`, `DemoData.swift` | Captures de l'interface avec des données de démo |
| `Tasks/TaskItem.swift` | Tâche, Quand, Répétition, et l'appartenance de chaque Tâche aux listes |
| `Tasks/TaskDatabase.swift` | Stockage des Tâches et des Projets |
| `Tasks/TaskStore.swift` | Les Tâches telles que les vues les montrent et les changent |
| `Tasks/TaskKeyboard.swift` | Touches du module Tâches, et ce que montre le module (liste, Tâche choisie, dépliée) |
| `Tasks/TaskLinks.swift` | Liens d'une Tâche : repérés, raccourcis, cliquables |
| `Tasks/ClaudeRunner.swift` | Confier une Tâche à Claude : session Claude Code d'arrière-plan, suivi par `claude agents`, reprise |
| `MCP/MCPServer.swift`, `MCP/MCPTools.swift` | `Maxwell --mcp` : serveur MCP, outils sur les Tâches et le Récap |
| `Tasks/QuickEntry.swift` | Lecture d'une ligne tapée : dates en français, `#projet`, `!` |
| `Tasks/QuickEntryPanel.swift` | Saisie rapide : raccourci global et champ flottant |
| `Tasks/TasksView.swift` | Module Tâches : listes, Projets et raccourcis à une touche |
| `Tasks/TaskViews.swift`, `Tasks/TaskEditor.swift` | Ligne de Tâche, champ de création, Tâche dépliée |
| `Tasks/MenuBarTasks.swift` | Tâches du jour dans la barre de menus |
| `Shelf/ShakeDetector.swift` | Reconnaissance de la Secousse, à partir des positions de la souris |
| `Shelf/DragShakeMonitor.swift` | Suivi de la souris pendant un glisser de fichiers, dans toutes les apps |
| `Shelf/Shelf.swift` | Contenu de l'Étagère : références vers les fichiers déposés |
| `Shelf/ShelfController.swift` | L'Étagère au complet : réglage, Secousse, fenêtre flottante |
| `Shelf/ShelfView.swift` | Carte de l'Étagère : zone de dépôt, pile de fichiers, liste dépliée |
| `Shelf/FileDragSource.swift` | Glisser des fichiers hors de l'Étagère, avec le comportement du Finder |
| `Shelf/Thumbnails.swift` | Aperçus Quick Look des fichiers, gardés en mémoire |
| `Shelf/ShelfActions.swift` | Afficher dans le Finder, ouvrir, copier |

## Design

Le vert de l'app marque l'app elle-même : l'app en cours, les liens, les interrupteurs. Chaque catégorie a sa propre teinte, la même d'une période à l'autre ; dans un Récap, seules les quatre principales sont en couleur, les autres restent en gris. Les captures de référence sont dans `docs/design/`.

Pour redessiner chaque écran en PNG, en clair et en sombre, avec des données de démo et sans toucher aux tiennes :

```bash
./build.sh && build/Maxwell.app/Contents/MacOS/Maxwell --snapshot captures
```

`MAXWELL_SNAPSHOT_NOW` (secondes depuis 1970) fige l'heure des données de démo : deux séries faites à la même heure figée montrent les mêmes chiffres, ce qui permet de vérifier qu'un changement de code ne les a pas modifiés.

Les effets Liquid Glass (segment sélectionné, sélection de la barre latérale, fond des boutons de la barre d'outils) sont dessinés par macOS à l'écran et n'apparaissent pas sur ces captures.

## Fenêtre Maxwell

Une seule fenêtre, sombre, en style Console, réunit les deux modules : **Temps** (le Récap, ⌘1) et **Tâches** (⌘2), en onglets en haut. ⌃⌥T l'ouvre sur les Tâches depuis n'importe quelle app, et la referme ; « Récap » dans le menu l'ouvre sur le Temps. Tant qu'une fenêtre de Maxwell est ouverte, l'app est dans le Dock et dans ⌘Tab ; fenêtres fermées, elle redevient une simple icône de barre de menus. Dans le Temps : `j` `s` `m` pour jour, semaine, mois, ← → pour remonter le temps, `t` pour revenir à aujourd'hui.

## Tâches

La spécification complète est dans [docs/taches.md](docs/taches.md).

- **Ouvrir** : ⌃⌥T ouvre la fenêtre Tâches depuis n'importe quelle app, et la referme.
- **Créer** : ⌃⌥Espace ouvre la Saisie rapide par-dessus l'app en cours ; on tape un titre, Entrée. ⇧Entrée crée et garde le champ ouvert, Échap ferme. Le menu de la barre de menus et la fenêtre Tâches ont aussi leur champ.
- **Au clavier, dans la liste** : ← passe à la colonne des listes (↑↓ y changent de liste, projets compris, → ou ↩ reviennent aux tâches), ↑↓ choisir, ⌥↑↓ déplacer, ↩ ouvrir, `x` faite, `t` aujourd'hui, `d` demain, `s` un jour, `f` drapeau, `p` projet, `c` confier à Claude, `o` ouvrir le lien, ⌫ supprimer une tâche créée par erreur, `u` annuler la dernière action (suppression, coche, report, drapeau, déplacement, création ; plusieurs fois de suite pour remonter), `/` nouvelle tâche, `1` à `5` changer de liste (aussi en AZERTY), Échap replier. La fenêtre s'ouvre sur Aujourd'hui, le curseur dans « Nouvelle tâche » ; ↓ descend sur la première tâche, ↑ depuis la première tâche remonte dans le champ, Échap le quitte. La barre du bas les rappelle.
- **Liens** : une adresse web dans le titre ou la note devient cliquable et s'affiche en court (« github ↗ », « slack ↗ », « gmail ↗ »).
- **Écrire vite** : `demain`, `vendredi`, `le 3 déc`, `dans 2 semaines`, `un jour` en fin de ligne donnent le Quand ; `avant vendredi` l'Échéance ; `#Projet` le Projet ; `!` le Drapeau. Ce qui est compris s'affiche sous le champ.
- **Listes** : Boîte de réception, Aujourd'hui, À venir, Un jour, un par Projet, Historique. Aujourd'hui se calcule seule ; une tâche en retard y reste avec « depuis N j ».
- **Modifier** : double-clic ou ↩ déplie la tâche ; les réglages choisis (Quand, Échéance, Projet, Répétition) y sont des pastilles, les autres des icônes à droite. Clic droit pour la reporter, la ranger ou l'annuler.
- Données dans la même base que le suivi. Rien ne quitte le Mac tant qu'on ne confie pas une tâche à Claude.

## Claude

Détail dans [docs/taches.md](docs/taches.md#pont-avec-claude).

- **Dossier d'un projet** : clic droit sur un projet → « Choisir le dossier… ». C'est le dépôt où Claude travaille sur ses tâches. `p` range la tâche choisie dans un projet.
- **Confier une tâche** : `c` sur la tâche choisie, puis ↩. Maxwell lance lui-même une session Claude Code d'arrière-plan (`claude --bg`) dans le dossier du projet : elle apparaît dans `claude agents`, où on peut la suivre et lui répondre. La ligne montre l'étape en cours, puis la tâche dépliée affiche le compte rendu. Tab y change de modèle. « reprendre dans le terminal » ouvre la session dans Ghostty s'il est installé, sinon dans Terminal ; « ouvrir dans Claude Desktop » l'ajoute à la liste des sessions de Claude Desktop. L'icône lien relie à la tâche une session déjà ouverte à la main.
- **Ce que Claude peut faire seul** : ⚙︎ → « Claude peut… » (autonomie par défaut, fichiers seulement, ou plan seul).
- **Serveur MCP** : `Maxwell --mcp` donne à Claude les tâches et le récap de temps. Pour toutes tes sessions Claude Code :

```bash
claude mcp add --scope user maxwell -- /Applications/Maxwell.app/Contents/MacOS/Maxwell --mcp
```

- Ce que Claude lit ou reçoit ainsi part chez Anthropic, comme toute conversation avec Claude.

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

- Suivre les sites dans les autres navigateurs (Safari, Arc…), comme dans Chrome.
- Export CSV.

## Icône

L'icône (monogramme M en barres) est dessinée par `Scripts/make-icon.swift`, qui produit `Resources/AppIcon.icns`. Après une modification du dessin, relance :

```bash
swift Scripts/make-icon.swift
```

La version de la barre de menus est dessinée dans `MenuBarIcon.swift`.
