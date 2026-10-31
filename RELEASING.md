# Publier une nouvelle version

Maxwell se partage par les [releases GitHub](https://github.com/MaxLmqr/Maxwell/releases). Les apps installées vérifient chaque jour s'il y a une nouvelle version grâce à [Sparkle](https://sparkle-project.org) et la proposent en un clic.

## À chaque version

1. Commiter tous les changements : le script refuse de tourner sinon.
2. Choisir le numéro de version : `0.2.1` pour une correction, `0.3.0` pour une nouveauté.
3. Lancer :

   ```bash
   ./release.sh 0.3.0 "Ce qui change dans cette version"
   ```

   Les notes s'affichent dans la fenêtre de mise à jour chez les amis, et sur la page de la release. L'appcast ne contient que la dernière version : un ami qui n'a pas installé la précédente ne verra que ces notes. Elles doivent donc aussi reprendre ce qui compte dans les versions qu'il a pu manquer, surtout ce qui lui demandera quelque chose, comme l'accès à Chrome.

4. Vérifier que l'appcast annonce la bonne version :

   ```bash
   curl -sL https://github.com/MaxLmqr/Maxwell/releases/latest/download/appcast.xml
   ```

Le script fait tout le reste :

1. Il augmente `CFBundleShortVersionString` (la version affichée) et `CFBundleVersion` (le numéro que Sparkle compare, +1 à chaque fois) dans `Resources/Info.plist`.
2. Il compile l'app avec `build.sh`, qui la signe avec le certificat « Maxwell Self-Signed », et la zippe dans `build/Maxwell-<version>.zip`.
3. Il signe le zip avec la clé Sparkle du Trousseau et écrit `build/appcast.xml`.
4. Il commite la nouvelle version, crée le tag `v<version>` et pousse `main` et le tag.
5. Il crée la release GitHub avec le zip et l'appcast.

## Prérequis

- **La clé Sparkle** dans le Trousseau, compte « Maxwell ». Une copie de secours est dans le gestionnaire de mots de passe. Pour la restaurer sur un autre Mac :

  ```bash
  .build/artifacts/sparkle/Sparkle/bin/generate_keys --account Maxwell -f maxwell-sparkle-key.txt
  ```

  Sans cette clé, les apps déjà installées refusent toute mise à jour. Il faudrait alors que chaque ami réinstalle l'app à la main.

- **Le certificat « Maxwell Self-Signed »** dans le Trousseau. Le script refuse de publier sans lui. macOS rattache à ce certificat les autorisations données à Maxwell, comme la lecture de l'onglet actif de Chrome. Une version signée autrement ferait redemander ces autorisations à tous les amis.

  Pour le sauvegarder : dans Trousseaux d'accès, onglet « Mes certificats », sélectionner « Maxwell Self-Signed », puis Fichier → Exporter des éléments, au format .p12 avec un mot de passe. Ranger le fichier et le mot de passe dans le gestionnaire de mots de passe. Pour le restaurer sur un autre Mac, ouvrir le .p12. À la première signature, choisir « Toujours autoriser » quand codesign demande à utiliser la clé.

- **`gh`** connecté au compte GitHub qui possède le dépôt (`gh auth status`).
- **Les outils Sparkle**, téléchargés par Swift Package Manager au premier `swift build`.
- **Le dépôt public**, pour que les amis et Sparkle puissent télécharger les fichiers.

## Si quelque chose se passe mal

- **Le script s'arrête avant la release GitHub** : `Info.plist` a peut-être déjà changé, ou le commit et le tag ont peut-être déjà été créés. Regarder `git status` et `git log` avant de relancer. Un tag déjà présent bloque une nouvelle tentative avec le même numéro : le supprimer avec `git tag -d v<version>`, et aussi sur GitHub s'il y a été poussé.
- **Une version publiée est cassée** : publier tout de suite une version corrigée avec un numéro plus grand. Supprimer la release fautive ne suffit pas : les amis qui l'ont déjà installée ne reviennent pas en arrière.

## Ce qui ne doit pas changer

- **`CFBundleIdentifier`** (`com.max.Maxwell`) : en le changeant, les amis perdraient leurs réglages et leurs données.
- **`SUFeedURL`** et **`SUPublicEDKey`** dans `Info.plist` : les apps installées ne trouveraient plus les mises à jour ou les refuseraient.
- **Le certificat de signature** : avec un autre, macOS redemanderait aux amis l'accès à Chrome. Sparkle accepterait quand même la mise à jour, tant que la clé EdDSA ne change pas en même temps.

## Installation

Première installation :

1. Télécharger `Maxwell-<version>.zip` depuis la [dernière release](https://github.com/MaxLmqr/Maxwell/releases/latest).
2. Glisser Maxwell dans Applications et l'ouvrir.
3. macOS la bloque, parce qu'elle n'est pas signée par un compte Apple Developer : aller dans Réglages système → Confidentialité et sécurité → « Ouvrir quand même ».

Il faut macOS 26. Les mises à jour suivantes s'installent depuis la fenêtre de Sparkle, ou depuis ⚙︎ → « Rechercher les mises à jour… ».

La première fois que Chrome passe au premier plan, macOS demande si Maxwell peut « contrôler Google Chrome » : c'est pour lire le site de l'onglet actif. En cas de refus, Chrome compte comme une seule app. Pour changer d'avis : Réglages système → Confidentialité et sécurité → Automatisation.
