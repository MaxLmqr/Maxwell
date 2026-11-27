# Maxwell

L'assistant personnel de Max sur son Mac. Il mesure le temps que Max passe dans chaque application et sur chaque site, et en fait des récaps par jour, semaine et mois ; il garde aussi des fichiers à portée de main, le temps de les déposer ailleurs, et tient la liste de ses tâches.

## Mesure

**App**:
Une application macOS, identifiée par son identifiant de bundle. Avec le Site, c'est la seule unité suivie : pas de fenêtres ni de documents.
_Avoid_: Programme, logiciel

**Site**:
Un site web ouvert dans l'onglet actif de Chrome, identifié par son nom d'hôte sans « www. » : mail.google.com et docs.google.com sont deux Sites. Le temps passé sur chaque Site est détaillé, et compte dans la Catégorie de Chrome tant que Max ne lui en choisit pas une autre. Seul ce nom est enregistré, jamais l'adresse complète ni le titre de la page, et la navigation privée n'a pas de Site.
_Avoid_: Domaine, URL, onglet

**Session**:
Un intervalle continu pendant lequel une même App, et dans Chrome un même Site, est au premier plan et Max est actif.
_Avoid_: Activité, événement, entrée

**Temps actif**:
La somme des Sessions sur une période. Il exclut l'Inactivité et les Pauses, même si une vidéo ou une visio tourne, ainsi que la Catégorie Système quand elle est masquée.
_Avoid_: Temps d'écran, temps d'utilisation

**Inactivité**:
L'état déclenché après 3 minutes sans clavier ni souris. Il interrompt la Session en cours, qui se termine au dernier geste.
_Avoid_: Idle, absence

**Pause**:
L'interruption du suivi quand le Mac dort, que l'écran est éteint ou verrouillé.
_Avoid_: Suspension

## Catégorisation

**Catégorie**:
Le type d'usage d'une App ou d'un Site (Développement, Communication, Design…), choisi dans une liste fixe que Max peut modifier. Chaque App et chaque Site a exactement une Catégorie, qui vaut pour tout son historique. Elle ne porte aucun jugement de productivité.
_Avoid_: Tag, label, projet

**Navigation**:
La Catégorie des navigateurs web, et donc des Sites, sauf ceux que Max range ailleurs.

**Système**:
La Catégorie des dialogues et utilitaires de macOS (notifications, autorisations). Elle est masquable dans les récaps.

## Restitution

**Récap**:
Le résumé du Temps actif sur un jour, une semaine ou un mois : total, répartition et comparaison avec la période précédente.
_Avoid_: Rapport, bilan, stats

**Jour actif**:
Un jour, ou une heure dans le Récap d'un jour, qui compte au moins 1 min de Temps actif. La moyenne d'un Récap se calcule sur les seuls Jours actifs.
_Avoid_: Jour travaillé, jour utilisé

## Étagère

**Étagère**:
Une petite fenêtre flottante, au-dessus de toutes les autres, où Max pose des fichiers le temps de les déposer ailleurs. Elle ne garde qu'une référence vers eux : les fichiers restent à leur place jusqu'au dépôt. Il n'y en a qu'une à la fois, et elle disparaît quand l'app redémarre.
_Avoid_: Shelf, panier, zone de dépôt

**Secousse**:
Le geste qui fait apparaître l'Étagère : agiter vivement la souris, dans n'importe quelle direction, pendant qu'on fait glisser des fichiers.
_Avoid_: Shake, agitation

## Tâches

**Tâche**:
Une chose que Max a à faire, avec un Titre et, au besoin, une Note, une Checklist, un Projet, un Quand, une Échéance, un Drapeau et une Répétition. Elle est Ouverte, Faite ou Annulée. Une Tâche créée par erreur se supprime : elle disparaît alors pour de bon, Historique compris.
_Avoid_: Todo, rappel, item, action

**Projet**:
Un nom qui regroupe des Tâches. Une Tâche a au plus un Projet. Sans rapport avec la Catégorie, qui classe le temps passé.
_Avoid_: Liste, zone

**Dossier**:
Le dossier d'un Projet sur le Mac, souvent un dépôt de code. C'est là que Claude travaille sur les Tâches du Projet.
_Avoid_: Repo, répertoire, chemin

**Confier**:
Lancer Claude sur une Tâche, depuis Maxwell, en arrière-plan. La Tâche garde le compte rendu de Claude ; elle reste Ouverte jusqu'à ce que Max la coche.
_Avoid_: Déléguer, envoyer, assigner

**Quand**:
Le jour où Max compte s'occuper d'une Tâche, ou « Un jour » s'il ne sait pas. Il décide dans quelle liste elle apparaît.
_Avoid_: Date de début, date prévue, planifié

**Échéance**:
La date limite d'une Tâche, distincte de son Quand.
_Avoid_: Deadline, date due

**Boîte de réception**:
La liste des Tâches Ouvertes sans Quand, avec ou sans Projet : elles n'ont pas encore de jour.
_Avoid_: Inbox, entrée

**Aujourd'hui**:
La liste des Tâches Ouvertes dont le Quand ou l'Échéance est aujourd'hui ou passé. Elle est calculée, jamais remplie à la main. La fenêtre Tâches y ajoute en bas, barrées, les Tâches Faites dans la journée.
_Avoid_: Ma journée, focus

**Historique**:
La liste des Tâches Faites ou Annulées.
_Avoid_: Logbook, archive, journal

**Saisie rapide**:
Le champ flottant ouvert par un raccourci global, qui crée une Tâche depuis n'importe quelle app.
_Avoid_: Quick add, capture
