# Contribuer à Murmure

## Compiler

Il faut Xcode (ouvert une fois), XcodeGen (`brew install xcodegen`) et CMake
(`brew install cmake`, ou CMake.app de cmake.org) pour `whisper-cli`. L'app est
décrite par `project.yml` ; `Murmure.xcodeproj` en est généré et n'est pas versionné.

```bash
script/build_and_run.sh               # Debug : génère, compile, signe et lance
script/build_and_run.sh --build-only  # sans lancer
```

`whisper-cli` n'est pas une cible Xcode : `scripts/build-whisper.sh` le compile depuis
whisper.cpp (version figée dans `scripts/whisper.version`) dans `build/whisper/`, et
xcodebuild le copie dans le bundle. `build_and_run.sh` et `install.sh` le lancent
d'abord (quelques secondes s'il est à jour) ; sans lui, la compilation échoue sur
« build/whisper/whisper-cli manquant ».

Le build va dans `~/Library/Caches/Murmure/Build` (`MURMURE_BUILD_DIR` pour un autre
dossier), hors des dossiers synchronisés par iCloud. Il est signé comme le fait
`install.sh` : Developer ID, sinon Apple Development, sinon ad hoc
(`MURMURE_SIGN_IDENTITY` pour choisir, « - » pour ad hoc). Même identifiant
(`dev.croustibat.murmure`) et même certificat que l'app installée : il en partage les
autorisations Micro et Accessibilité.

Ce build lit les données de l'installation par défaut (`~/.local/share/murmure`) et
tourne avec son propre moteur ; les variables `MURMURE_*` de l'environnement lui sont
transmises. Une seule Murmure tourne par dossier d'état : quitter l'app installée, ou
lancer le build à côté :

```bash
MURMURE_STATE_DIR=/tmp/murmure-dev MURMURE_SHORTCUT=ctrl+alt+shift+cmd+f19 script/build_and_run.sh
```

Sans les scripts, `scripts/build-whisper.sh && xcodegen generate && xcodebuild -scheme
Murmure` produit une app signée ad hoc, dans les DerivedData de Xcode.

Le bundle contient tout ce qui fait tourner Murmure ; une mise à jour de l'app met donc
aussi le moteur à jour :

| Dans `Murmure.app/Contents/` | Source |
|---|---|
| `MacOS/Murmure` | l'app (`src/app/`) |
| `Resources/engine/murmure.sh`, `corriger.pl` | le moteur (`src/`) |
| `Resources/defaults/` | réglages par défaut (`config/`) |
| `Resources/Licences/` | licences des composants embarqués (`app/Licences/`) |
| `Helpers/overlay`, `murmure-rec`, `whisper-cli` | la pastille, l'enregistreur, whisper.cpp |

`~/.local/share/murmure` (`MURMURE_HOME`) ne garde que les données de l'utilisateur :
`config`, `vocabulaire.txt`, `corrections.txt`, `models/`, `historique.jsonl`,
`cadence`. Au lancement, l'app y dépose les réglages par défaut qui manquent, sans
jamais écraser un fichier (un vocabulaire ou des corrections modifiés reçoivent la
nouvelle version à côté, en `.dist`).

`murmure.sh` trouve les outils à côté de lui, dans le bundle. Lancé depuis les sources
(`src/murmure.sh`), il prend ceux de l'app désignée par `MURMURE_APP`, sinon de
`/Applications/Murmure.app`, et le `corriger.pl` voisin. `MURMURE_WHISPER`,
`MURMURE_REC`, `MURMURE_OVERLAY` et `MURMURE_CORRIGER` imposent un autre outil
(`MURMURE_WHISPER` aussi depuis `config`). Il ne compte que sur le système : `PATH`
réduit à `/usr/bin:/bin:/usr/sbin:/sbin`, et `/usr/bin/perl` pour `corriger.pl`,
l'horodatage et l'historique.

L'app tourne sous runtime durci, avec deux entitlements (`app/Murmure.entitlements`) :
`com.apple.security.device.audio-input` (sans lui, le micro rend un flux muet) et
`com.apple.security.automation.apple-events` (le ⌘V passe par System Events).
`Contents/Frameworks/Sparkle.framework` (mises à jour) est re-signé par
`script/sign_app.sh` avec la même identité, ses services XPC (inutiles hors bac à
sable) retirés. Signée ad hoc (sans certificat, ou par Xcode seul), l'app reçoit en plus
`com.apple.security.cs.disable-library-validation` (`app/Murmure-adhoc.entitlements`) :
sans équipe, le runtime durci refuserait de charger Sparkle. Jamais avec un certificat,
où toute bibliothèque chargée hériterait des autorisations de Murmure.

```bash
codesign -d --entitlements - Murmure.app   # les deux entitlements
codesign -dv Murmure.app                   # flags=0x10000(runtime)
```

Ajouter un outil dans `Contents/Helpers` : une cible `type: tool` dans `project.yml`,
un bloc dans les `dependencies` de la cible `Murmure` (sur le modèle d'`overlay`), et
ses sources dans `APP_SOURCES` d'`install.sh`, pour qu'une modification recompile
l'app. `script/sign_app.sh` le signe sans autre changement ; s'il lui faut des
entitlements, les mettre dans `app/<outil>.entitlements`.

Numéros de version : `CFBundleShortVersionString` est lu dans `VERSION` à la
compilation (phase « Version » de `project.yml`) ; `CFBundleVersion`, dans
`app/Info.plist`, est un entier augmenté de 1 à chaque release, que Sparkle compare.
`script/release.sh` met à jour les deux en publiant (voir « Publier une version »).

## Tester le téléchargement du modèle

Sans modèle, l'app le télécharge elle-même (`src/app/Modele.swift`). Son nom, sa
révision, son empreinte et sa taille sont dans `app/modele.conf`, seule source, lue
aussi par `install.sh`. Pour essayer sans tirer 550 Mo ni toucher à l'installation :
un faux modèle, servi par `scripts/serveur-modele.py` (reprise, débit limité, coupure
simulée), et un build lancé à côté avec un dossier vide.

```bash
head -c 8388608 /dev/urandom > /tmp/faux.bin
scripts/serveur-modele.py /tmp/faux.bin --debit 1000000 --couper 3000000 &
MURMURE_HOME=/tmp/murmure-essai MURMURE_STATE_DIR=/tmp/murmure-essai-etat \
  MURMURE_SHORTCUT=ctrl+alt+shift+cmd+f19 \
  MURMURE_MODEL_URL=http://127.0.0.1:8770/redirection MURMURE_MODEL_SIZE=8388608 \
  MURMURE_MODEL_SHA256="$(shasum -a 256 /tmp/faux.bin | cut -d' ' -f1)" \
  script/build_and_run.sh
```

La première connexion est coupée à 3 Mo : « Réessayer » reprend là où elle s'est
arrêtée, le serveur journalise chaque plage demandée. Un octet modifié dans le `.part`
avant de reprendre (`printf '\xff' | dd of=<fichier>.part bs=1 seek=1000 conv=notrunc`)
fait refuser le fichier reçu, puis le retélécharger en entier.

L'app retient dans `$MURMURE_HOME/.modele-verifie` l'empreinte déjà vérifiée d'un
modèle présent, et dans `.prechauffage` la version de whisper-cli déjà préchauffée :
supprimer ce fichier relance le préchauffage au prochain lancement. Le cache Metal de
macOS ne vaut que pour une même version de whisper-cli lancée de la même façon ; pour
mesurer un premier lancement à froid, il faut une whisper-cli dont la source Metal
embarquée diffère.

## Publier une version

Une version est une **GitHub Release** `vX.Y.Z` qui porte deux fichiers aux noms fixes,
`Murmure.dmg` et `appcast.xml` : les liens `releases/latest/download/…` restent
stables. `Murmure.app` se met à jour avec Sparkle : au plus une fois par jour, elle lit
`appcast.xml` de la dernière release (`SUFeedURL`). Sparkle compare le
`sparkle:version` de l'appcast au `CFBundleVersion` de l'app : seul un nombre plus
grand propose la mise à jour. Le DMG doit porter la signature EdDSA de la clé du
compte `murmure` du trousseau (clé publique : `SUPublicEDKey`) et la même signature
Developer ID que l'app installée. L'app ne voit que la release « latest » : ni un tag
seul, ni un brouillon, ni une pré-version. Une release sans `appcast.xml` n'est pas vue
(le journal de l'app note l'erreur).

`script/release.sh` fait tout, sur le modèle de Sillage :

```bash
./script/release.sh                  # DMG notarisé et appcast dans dist/, sans publier
./script/release.sh --no-notarize    # DMG signé seulement, pour tester
./script/release.sh 1.2.0 --dry-run  # tout préparer, afficher la publication sans la faire
./script/release.sh 1.2.0            # versionne, notarise et publie
```

### Prérequis, une fois par Mac

- Les outils de « Compiler » (Xcode, XcodeGen, CMake), et `gh` connecté à un compte
  qui peut publier sur `croustibat/murmure` (`gh auth login`).
- Le certificat **Developer ID Application: Baptiste Bouillot (MMJD6CLKNQ)** et sa clé
  privée dans le trousseau : `security find-identity -v -p codesigning` le liste.
  `MURMURE_SIGN_IDENTITY` (empreinte SHA-1 ou nom) choisit parmi plusieurs.
- Le **profil notarytool `sillage-notary`**, déjà dans le trousseau : Murmure le partage
  avec Sillage (même équipe). `xcrun notarytool history --keychain-profile sillage-notary`
  doit répondre. Pour le recréer, un mot de passe pour app sur
  <https://account.apple.com>, puis
  `xcrun notarytool store-credentials sillage-notary --apple-id <apple-id> --team-id MMJD6CLKNQ`.
  `MURMURE_NOTARY_PROFILE` désigne un autre profil.
- La **clé EdDSA de Sparkle**, compte `murmure` du trousseau (élément « Private key for
  signing Sparkle updates »), déjà générée, et dont la clé publique est `SUPublicEDKey`
  dans `app/Info.plist`. Elle est propre à Murmure et ne vit jamais dans le dépôt. Elle
  est **indispensable** : perdue, plus aucune mise à jour ne pourrait être signée pour
  les apps installées. Elle est sauvegardée dans le gestionnaire de mots de passe.
  Les outils de Sparkle sont dans le dossier de build de `release.sh`
  (`xcodegen generate && xcodebuild -resolvePackageDependencies -project Murmure.xcodeproj -derivedDataPath ~/Library/Caches/Murmure/ReleaseBuild`
  les télécharge sans compiler) :

  ```bash
  BIN=~/Library/Caches/Murmure/ReleaseBuild/SourcePackages/artifacts/sparkle/Sparkle/bin
  $BIN/generate_keys --account murmure -p                       # doit afficher SUPublicEDKey
  $BIN/generate_keys --account murmure -x murmure-sparkle.key   # exporter, ranger, supprimer le fichier
  $BIN/generate_keys --account murmure -f murmure-sparkle.key   # réimporter sur un autre Mac
  ```

  `MURMURE_SPARKLE_ACCOUNT` désigne un autre compte.

### Publier

1. Écrire la section `## X.Y.Z` de `CHANGELOG.md`, pour les utilisateurs : elle devient
   les notes de la release GitHub et de la fenêtre de Sparkle (sans section, ce sont les
   sujets des commits depuis le tag précédent). Committer et pousser sur `main`.

   Numéro : correctif `1.2.0` → `1.2.1` ; fonctionnalité → `1.3.0` ; changement qui
   oblige à réinstaller ou à reconfigurer → `2.0.0`. Ne toucher ni à `VERSION` ni à
   `CFBundleVersion` : le script s'en charge.

2. Vérifier sans rien publier, depuis `main` :

   ```bash
   ./script/release.sh 1.2.0 --dry-run --no-notarize
   ```

   Le script fait tout le travail, puis affiche le diff du commit de version, le tag, le
   push et la commande `gh release create`, sans les lancer. Toute condition qui
   bloquerait la vraie publication est listée à la fin (code de sortie 1). `VERSION` et
   `app/Info.plist` reviennent à leur état ; le DMG et l'appcast restent dans `dist/`.

3. Publier, depuis `main` propre et à jour :

   ```bash
   ./script/release.sh 1.2.0
   ```

   Dans l'ordre :
   - vérifications, avant toute compilation : XcodeGen, certificat, profil de
     notarisation, `gh` connecté, branche `main` sans changement et égale à
     `origin/main`, `origin` = `croustibat/murmure`, tag et release absents, version
     supérieure ou égale à `VERSION`, build supérieur au `sparkle:version` publié, clé
     du trousseau égale à `SUPublicEDKey` ;
   - `VERSION` ← `1.2.0`, `CFBundleVersion` + 1 dans `app/Info.plist` (remis en l'état
     si la suite échoue) ;
   - `scripts/build-whisper.sh`, `xcodegen generate`, `xcodebuild` Release arm64 dans
     `~/Library/Caches/Murmure/ReleaseBuild` (`MURMURE_RELEASE_BUILD_DIR`), hors des
     dossiers iCloud et à part du build d'`install.sh` ;
   - signature par `script/sign_app.sh` avec horodatage : outils de
     `Contents/Helpers`, `Autoupdate`, `Updater.app` et `Sparkle.framework`, puis l'app
     avec ses entitlements. Chaque fichier Mach-O du bundle est ensuite contrôlé :
     Developer ID de l'équipe MMJD6CLKNQ, horodatage, runtime durci, ni
     `disable-library-validation` ni `get-task-allow` ;
   - `dist/Murmure-1.2.0.dmg` (l'app et un lien vers Applications), signé,
     **notarisé** (`notarytool submit --wait`, journal d'Apple affiché en cas de
     refus), agrafé, accepté par `spctl` ;
   - `dist/appcast.xml` par `generate_appcast --account murmure`, une seule entrée,
     contrôlée : versions, macOS 14.0, adresse et taille du DMG, et signature EdDSA
     vérifiée contre `SUPublicEDKey` ;
   - commit « release: v1.2.0 », tag annoté `v1.2.0`, push atomique de `main` et du
     tag, puis `gh release create v1.2.0 Murmure.dmg appcast.xml --latest`. Le tag est
     poussé avant la release : créée d'abord, elle poserait le tag sur le commit
     d'avant. Si la création échoue après le push, le script affiche la commande à
     relancer ; les fichiers sont dans `dist/` ;
   - contrôle : `releases/latest/download/appcast.xml` annonce le nouveau build ;
   - proposition de mettre à jour le cask Homebrew (`[O/n]`) : `script/update-cask.sh`
     télécharge le DMG publié, en calcule l'empreinte et pousse `version` et `sha256`
     dans `Casks/murmure.rb` de
     [`croustibat/homebrew-tap`](https://github.com/croustibat/homebrew-tap). Refusé,
     ou en cas d'échec, `./script/update-cask.sh 1.2.0` se lance à part ; il refuse de
     faire reculer le cask.

4. Vérifier la page de la release et le lien
   <https://github.com/croustibat/murmure/releases/latest/download/Murmure.dmg>. Une
   Murmure de la version précédente propose la nouvelle par « Rechercher les mises à
   jour… ». `brew update && brew info --cask croustibat/tap/murmure` annonce la
   nouvelle version ; `brew upgrade` laisse l'app à Sparkle (`auto_updates`).

La 1.1.0 n'a pas Sparkle : ses utilisateurs passent une fois au DMG (section « Vous avez
la 1.1.0 ? » de `CHANGELOG.md`), les versions suivantes arrivent d'elles-mêmes.

### Essayer sans publier, sans trousseau ni notarisation

Une clé EdDSA jetable, en fichier, remplace la clé du trousseau (`--ed-key-file`). Le DMG
reste celui d'une vraie publication : seul l'appcast est signé par la clé de test.

```bash
xcrun swift script/cle_sparkle.swift nouvelle /private/tmp/murmure-cle.txt
./script/release.sh 1.2.0 --dry-run --no-notarize --ed-key-file /private/tmp/murmure-cle.txt
./script/essai_release.sh /private/tmp/murmure-essai-release /private/tmp/murmure-cle.txt
```

`essai_release.sh` installe sous `/private/tmp` une copie de l'app du DMG ramenée au
build précédent, qui lit l'appcast de `dist/` servi sur `127.0.0.1`. Elle porte la clé
publique de test, la mise à jour automatique et son propre `MURMURE_HOME`. Sparkle
télécharge le DMG ; le script ferme l'app (Sparkle installe à la fermeture, sans
relancer), puis vérifie que l'app installée a le build et le CDHash de celle du DMG. Les
réglages `SU*` de `dev.croustibat.murmure`, partagés avec l'app réelle, retrouvent leur
valeur, et les apps de l'essai sortent de LaunchServices.

Pour vérifier le DMG à la main : `hdiutil attach -nobrowse -readonly` puis
`codesign --verify --deep --strict` et `spctl --assess --type execute -vv` sur une copie
de l'app. Sans notarisation, Gatekeeper refuse avec `source=Unnotarized Developer ID`,
et pour cette seule raison.

La mise à jour se teste aussi avec deux builds compilées depuis les sources, sans
`release.sh`, à côté de l'app installée :

```bash
script/essai_mise_a_jour.sh /private/tmp/murmure-essai
```

Le script compile deux builds de test (1.2.0, build 2 ; 1.2.1, build 3), met la seconde
en DMG dans un appcast signé par une clé EdDSA jetable, et installe la première dans
`/private/tmp/murmure-essai/Applications`. Leur Info.plist porte le flux local, la clé
de test et (`LSEnvironment`, qui survit à la relance par Sparkle) un `MURMURE_HOME` et un
dossier d'état à part. Servir l'appcast et ouvrir l'app (commandes affichées) : Sparkle
propose la 1.2.1, l'installe et relance l'app, ce que dit le journal de l'essai. Pour
vérifier qu'une dictée diffère l'installation, simuler une transcription avant
« Installer et relancer », puis la terminer :

```bash
printf 'transcribing 30' > /tmp/s && mv /tmp/s /private/tmp/murmure-essai/etat/status
rm /private/tmp/murmure-essai/etat/status
```

Sparkle range la date de sa dernière vérification dans les réglages de
`dev.croustibat.murmure` : `defaults delete dev.croustibat.murmure SULastCheckTime`
autorise une nouvelle vérification au lancement. Après l'essai,
`script/essai_mise_a_jour.sh /private/tmp/murmure-essai --nettoyer` retire ces réglages
(ceux de l'app réelle aussi) et le dossier.

### Gatekeeper sur un autre Mac

Avant une première publication, un DMG notarisé passe par un vrai téléchargement :

```bash
./script/release.sh            # notarisé, non publié : dist/Murmure.dmg
gh release create v1.2.0-rc1 dist/Murmure.dmg --repo croustibat/murmure --draft --prerelease --title "Murmure 1.2.0-rc1"
```

Sur un autre Mac Apple Silicon, connecté à GitHub dans le navigateur, télécharger
`Murmure.dmg` depuis le brouillon, l'ouvrir, glisser Murmure dans Applications et
l'ouvrir par un double-clic : aucun avertissement, sans clic droit > Ouvrir. Puis
`gh release delete v1.2.0-rc1 --repo croustibat/murmure --yes`. Un brouillon n'est
jamais vu par Sparkle.
