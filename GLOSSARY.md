# Maxwell

L'assistant personnel de Max sur son Mac. Il mesure le temps que Max passe dans chaque application et sur chaque site, et en fait des récaps par jour, semaine et mois ; il garde aussi des fichiers à portée de main, le temps de les déposer ailleurs.

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

## Étagère

**Étagère**:
Une petite fenêtre flottante, au-dessus de toutes les autres, où Max pose des fichiers le temps de les déposer ailleurs. Elle ne garde qu'une référence vers eux : les fichiers restent à leur place jusqu'au dépôt. Il n'y en a qu'une à la fois, et elle disparaît quand l'app redémarre.
_Avoid_: Shelf, panier, zone de dépôt

**Secousse**:
Le geste qui fait apparaître l'Étagère : agiter vivement la souris, dans n'importe quelle direction, pendant qu'on fait glisser des fichiers.
_Avoid_: Shake, agitation
