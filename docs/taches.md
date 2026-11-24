# Tâches

Spécification fonctionnelle de la liste de tâches de Maxwell, version 1. Le vocabulaire est défini dans [GLOSSARY.md](../GLOSSARY.md).

**Ce qui compte avant tout** : créer une Tâche doit prendre deux secondes, depuis n'importe quelle app, sans choisir quoi que ce soit. Le rangement vient après, et il est facultatif.

La v1 ne se connecte à rien : ni Slack, ni Gmail, ni Agenda, ni serveur. Les Tâches restent dans la base locale de Maxwell. Le pont avec Claude est décrit à la fin, comme prochaine étape.

## Ce qu'est une Tâche

| Champ | Obligatoire | Rôle |
|---|---|---|
| Titre | oui | Une ligne de texte. |
| Note | non | Texte libre. Les liens sont cliquables, ce qui suffit à garder un lien vers un message Slack ou un mail. |
| Checklist | non | Une liste plate d'éléments à cocher, sans date ni sous-niveau. |
| Projet | non | Un seul Projet au plus. |
| Quand | non | Le jour où Max compte s'y mettre, ou « Un jour ». Pas d'heure en v1. |
| Échéance | non | La date limite. Distincte de Quand : on peut prévoir lundi une Tâche à rendre vendredi. |
| Drapeau | non | Marque une Tâche importante. Il n'y a pas d'autre niveau de priorité. |
| Répétition | non | Voir plus bas. |
| État | oui | Ouverte, Faite ou Annulée, avec la date du changement. |

Une Tâche Faite ou Annulée part dans l'Historique. Seule une Tâche créée par erreur se supprime, et alors pour de bon.

## Créer une Tâche

Deux entrées, et une seule règle : **taper un titre puis Entrée suffit.**

1. **Saisie rapide** : le raccourci global ⌃⌥Espace (⌥Espace est déjà pris par Claude) ouvre un champ flottant au centre de l'écran, par-dessus l'app en cours. Entrée crée la Tâche et ferme le champ, ⇧Entrée crée et garde le champ ouvert pour enchaîner, Échap annule.
2. **Barre de menus** : un champ « Nouvelle tâche pour aujourd'hui » en haut de la liste du jour.
3. **Fenêtre Maxwell**, module Tâches : un champ en haut de chaque liste (`/` pour y aller).

Un champ placé dans une liste y range la Tâche : Aujourd'hui lui donne le Quand du jour, Un jour lui donne « Un jour », un Projet lui donne ce Projet. La Saisie rapide n'impose rien.

Le texte tapé est lu pour en extraire, s'ils y sont :

| Écrit | Effet |
|---|---|
| `aujourd'hui`, `demain`, `lundi`, `le 3 déc`, `dans 3 jours`, `semaine prochaine` | Quand |
| `avant vendredi`, `avant le 15` | Échéance |
| `#Maxwell` | Projet (complété au fur et à mesure ; un nom inconnu crée le Projet) |
| `!` en fin de titre | Drapeau |

Ce que Maxwell a compris s'affiche en pastilles sous le champ pendant la frappe, et ces mots sont retirés du titre. Les dates ne sont lues qu'en fin de ligne, et jamais après « de », « du » ou « des » : « Préparer la réunion de demain » reste un titre. Une Tâche sans Projet ni Quand arrive dans la Boîte de réception.

## Les listes

| Liste | Contenu |
|---|---|
| **Boîte de réception** | Tâches Ouvertes sans Projet ni Quand : ce qui reste à ranger. |
| **Aujourd'hui** | Tâches Ouvertes dont le Quand est aujourd'hui ou passé, ou dont l'Échéance est aujourd'hui ou passée. |
| **À venir** | Tâches Ouvertes avec un Quand ou une Échéance futurs, groupées par jour. |
| **Un jour** | Tâches Ouvertes dont le Quand vaut « Un jour ». |
| **Projet** | Toutes les Tâches Ouvertes du Projet. |
| **Historique** | Tâches Faites et Annulées, de la plus récente à la plus ancienne. |

Aujourd'hui est calculée, pas choisie à la main : il n'y a rien à vider chaque nuit. Une Tâche non faite reste dans Aujourd'hui le lendemain, avec la mention discrète « depuis 3 j ». Une Échéance dépassée s'affiche en rouge.

Une Tâche qui vient d'être créée arrive en tête de sa liste. Tant que le curseur reste dans le champ de création, aucune Tâche n'est en surbrillance. Dans chaque liste, sauf À venir et l'Historique, l'ordre se change avec ⌥↑ et ⌥↓.

## Interface

Les Tâches sont un des deux modules de la fenêtre Maxwell, à côté du Temps (le Récap). La fenêtre suit la direction « Console » :

- **Sombre et dense**, avec des repères en chasse fixe : `ventes`, `J-2` pour l'Échéance (en rouge à J-1), `+2j` pour un retard (en orange), `↻ sem`, `☐ 1/2`, `¶` pour une note.
- **Deux onglets en haut**, Temps (⌘1) et Tâches (⌘2), posés à côté des boutons de la fenêtre.
- **À gauche, les listes**, puis les Projets avec un cercle qui se remplit à mesure qu'ils avancent.
- **À droite, la liste choisie** : son nom en capitales, le champ de création « › » en haut, les Tâches sur une ligne chacune, les jours d'À venir en en-têtes (`LUN 23 demain`).
- **Les flèches vont d'une colonne à l'autre** : ← passe aux listes, où ↑↓ changent de liste (Projets compris) ; → ou ↩ reviennent aux Tâches. La liste choisie est cerclée de vert quand les flèches y sont. Une liste vide envoie d'elle-même les flèches aux listes, et à l'ouverture la première Tâche est déjà choisie.
- **Tout au clavier, d'une touche** dans la liste : ↑↓ choisir, ⌥↑↓ déplacer, ↩ ouvrir, `x` faite, `t` aujourd'hui, `d` demain, `s` un jour, `f` drapeau, `o` ouvrir le lien, ⌫ supprimer, `u` annuler la dernière action, `/` nouvelle tâche, `1` à `5` changer de liste, Échap replier. La fenêtre s'ouvre sur Aujourd'hui, le curseur dans le champ de création : ouvrir et taper suffit à noter une Tâche. ↓ descend du champ sur la première Tâche, et ↑ depuis la première Tâche remonte dans le champ ; Échap quitte aussi le champ, en gardant choisie la Tâche qui vient d'être créée. Elles se lisent sur la touche physique pour les chiffres, ce qui marche aussi en AZERTY. Une barre en bas rappelle les touches du moment.
- **Les liens** du Titre et de la Note sont cliquables et raccourcis : « Relire https://github.com/… » s'affiche « Relire github ↗ ». Un lien de la Note apparaît en bout de ligne, et tous les liens dans la Tâche dépliée. Au survol, le lien se souligne et le curseur devient une main.
- **⌃⌥T** ouvre la fenêtre sur les Tâches depuis n'importe quelle app, et la referme.

## Agir sur une Tâche

- **Cocher** (clic sur la case, ou `x`) la rend Faite. Elle reste visible et barrée jusqu'à la fermeture de la liste, pour pouvoir se rattraper, puis part dans l'Historique.
- **Reporter**, d'un clic droit ou d'un raccourci : Demain, Ce week-end, Semaine prochaine, Un jour, ou une date.
- **Annuler** : la Tâche quitte les listes sans compter comme faite, et reste dans l'Historique.
- **Supprimer** : pour une Tâche créée par erreur. Clic droit → Supprimer, ⌫ sur la Tâche choisie, ou la corbeille de la Tâche dépliée. Un bandeau « Annuler » s'affiche 6 secondes. Une Tâche supprimée quitte aussi l'Historique.
- **Annuler** la dernière action : `u`. Cela défait une suppression, une coche (et retire la Tâche suivante d'une Répétition), un report, un drapeau, un déplacement, une modification ou une création. `u` plusieurs fois remonte action par action, jusqu'à 50, tant que Maxwell reste ouvert ; un message « Annulé : … » dit ce qui a été défait, et la Tâche revenue est choisie.
- **Ranger** : clic droit → Projet.
- **Ouvrir** : ↩ ou un double-clic déplie la Tâche sur place pour modifier le Titre, la Note, la Checklist, le Quand, l'Échéance, le Projet, la Répétition et le Drapeau. Entrée ou Échap la replie.

## Projets

Un Projet est un nom, et rien d'autre en v1 : ni sous-projet, ni date, ni dossier. On le crée depuis la barre latérale ou en tapant un `#nom` inconnu, on le renomme ou l'archive d'un clic droit. Archivé, il quitte la barre latérale et ses Tâches encore Ouvertes perdent leur Projet : sans Quand, elles reviennent dans la Boîte de réception.

Un Projet n'est pas une Catégorie : la Catégorie classe le temps passé dans les Apps et les Sites, le Projet regroupe des Tâches.

## Répétition

Une Tâche peut se répéter de deux façons :

- **À date fixe** : tous les lundis, le 1er de chaque mois. La Tâche suivante a lieu à la date prévue, même si la précédente a été faite en retard.
- **Après avoir été faite** : 2 semaines après la dernière fois.

Quand une Tâche répétée est Faite ou Annulée, elle part dans l'Historique et Maxwell crée la suivante, avec le même Titre, la même Note, la Checklist décochée et le Quand suivant. Jamais de Tâche dans le passé : à date fixe, la suivante est la première date future.

## Où les voir

- **Barre de menus** : « Tâches du jour » en haut, avec son champ et les sept premières Tâches d'Aujourd'hui, au-dessus du Récap du jour. Un lien « N à ranger » ouvre la Boîte de réception.
- **Fenêtre Maxwell**, module Tâches (⌃⌥T de partout, ou depuis le menu) : les listes à gauche, les Projets en dessous.

Les captures de référence sont dans `docs/design/` (`taches-*`, `temps-*`, `saisie-rapide-*`, `menu-*`).

## Hors v1

Notées pour plus tard, sans engagement :

- Heures et rappels (notifications à une heure donnée).
- Choisir un autre raccourci pour la Saisie rapide.
- Ranger une Tâche en la glissant sur une liste de la barre latérale.
- Connexion à Slack et Gmail (capture par emoji ou libellé), et à Google Agenda (réserver un créneau).
- Temps mesuré par Tâche : pendant qu'une Tâche est en cours, lui compter le Temps actif ; bilan du soir prérempli à partir du Récap.
- Tags, sous-tâches imbriquées, partage, application iPhone.

## Décisions prises

- **Stockage** : les Tâches sont dans la base de Maxwell (`activity.sqlite`, tables `tasks` et `projects`), pas dans Rappels d'Apple. Pas d'iPhone pour l'instant.
- **Barre de menus** : les Tâches du jour passent au-dessus du Récap.

## Pont avec Claude

Il marche dans les deux sens, sans serveur en ligne et sans passer par Claude Desktop.

### Le dossier d'un Projet

Un Projet peut avoir un **Dossier**, souvent un dépôt de code : clic droit sur le Projet → « Choisir le dossier… ». Il s'affiche sous le nom du Projet. C'est là que Claude travaille sur les Tâches du Projet ; ranger une Tâche dans un Projet (`#Projet` à la saisie, ou `p` sur la Tâche choisie) suffit donc à dire où travailler. Une Tâche sans Projet, ou dont le Projet n'a pas de Dossier, est confiée à Claude dans un dossier neutre : cela convient à ce qui n'est pas du code.

`p` ouvre un sélecteur : on tape pour filtrer, ↑↓ choisissent, ↩ range. Il propose aussi de créer le Projet tapé, ou de retirer la Tâche de son Projet.

### Confier une Tâche à Claude

`c` sur la Tâche choisie ouvre une confirmation : le Dossier, ce que Claude a le droit de faire, le modèle, et une précision facultative. Tab passe d'un modèle à l'autre (opus par défaut, puis fable, sonnet, haiku, ou le réglage de Claude Code) ; Maxwell retient le dernier choisi. ↩ lance, Échap renonce.

Maxwell démarre alors lui-même une session Claude Code d'arrière-plan (`claude --bg`), dans le Dossier, avec comme demande la Tâche telle qu'elle est écrite : Titre, Projet, Échéance, Note, Checklist, précision. Pendant le travail, la ligne de la Tâche montre « ◆ » et l'étape en cours (« Edit Recap.swift », « Bash swift test »). À la fin, « ◆ compte rendu » : la Tâche dépliée affiche ce que Claude a fait, ce qui reste et ce qu'il faut vérifier. Claude ne coche pas la Tâche : c'est à Max, après relecture.

La session apparaît aussi dans `claude agents`, sous le titre de la Tâche et rangée sous son Dossier : Max peut l'y suivre en direct, lui répondre ou valider une action. Maxwell lit son état dans `claude agents --json` toutes les 3 secondes et le compte rendu dans la conversation que Claude Code enregistre. Si Max poursuit la conversation dans `claude agents`, la Tâche repasse en cours, puis reprend le nouveau compte rendu. `claude --bg` refuse un dossier que Claude Code ne connaît pas encore : il faut y lancer `claude` une fois et accepter de lui faire confiance ; la Tâche le dit.

Dans la Tâche dépliée : « arrêter » pendant le travail ; ensuite « reprendre dans le terminal », qui ouvre la session dans Ghostty s'il est installé, sinon dans Terminal (`claude attach`, la commande est aussi copiée), « ouvrir dans Claude Desktop », qui arrête la session dans `claude agents` puis l'ajoute à la liste de Claude Desktop pour la poursuivre là-bas (`claude --desktop --resume`, seulement si Claude Desktop est installé), et « relancer ».

**Ce que Claude peut faire seul** se règle dans ⚙︎ → « Claude peut… », car Max ne regarde pas forcément la session pendant qu'elle travaille :

| Réglage | Effet |
|---|---|
| agir en autonomie (par défaut) | Claude lit, modifie et lance des commandes, et s'arrête devant ce qui lui paraît risqué (mode `auto` de Claude Code). |
| modifier des fichiers, sans commande | Il ne peut ni lancer les tests ni utiliser git. |
| proposer un plan, sans rien changer | Lecture seule. |

Une session continue quand Maxwell se ferme ; il la retrouve au lancement suivant.

### Claude lit et modifie les Tâches et le Récap

`Maxwell --mcp` est un serveur MCP local : Claude le lance lui-même et il lit la même base que l'app. Une session lancée par Maxwell l'a d'office. Pour l'avoir dans toutes tes sessions :

- Claude Code : `claude mcp add --scope user maxwell -- /Applications/Maxwell.app/Contents/MacOS/Maxwell --mcp`
- Claude Desktop : dans `~/Library/Application Support/Claude/claude_desktop_config.json`, sous `mcpServers`, `"maxwell": {"command": "/Applications/Maxwell.app/Contents/MacOS/Maxwell", "args": ["--mcp"]}`, puis redémarrer Claude Desktop.

| Outil | Rôle |
|---|---|
| `list_tasks` | Une liste (Aujourd'hui par défaut) ou les Tâches d'un Projet |
| `add_task` | Créer une Tâche : titre, note, projet, quand, échéance, drapeau |
| `update_task` | Changer ces champs |
| `complete_task` | Rendre une Tâche Faite ou Annulée |
| `annotate_task` | Ajouter un compte rendu daté à la fin de la Note |
| `list_projects` | Les Projets, leur Dossier, leur nombre de Tâches Ouvertes |
| `get_time_recap` | Le Récap d'un jour, d'une semaine ou d'un mois : total, comparaison, Catégories, Apps et Sites |

La fenêtre Maxwell voit ce que Claude change, à deux secondes près. Ces changements ne passent pas par `u`.

**Ce qui quitte le Mac** : ce que Claude lit par ces outils, ou reçoit dans une Tâche confiée (titres, notes, temps par App et par Site), part chez Anthropic comme le reste d'une conversation avec Claude. Rien ne part tant que Max ne confie pas une Tâche ou ne pose pas la question à Claude.

### Pas encore fait

- Un Dossier propre à une Tâche, différent de celui de son Projet.
- Une extension `.mcpb` pour brancher Claude Desktop d'un double-clic.
