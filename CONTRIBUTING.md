# Contribuer à Murmure

## Compiler

Il faut Xcode (ouvert une fois) et XcodeGen (`brew install xcodegen`). L'app est
décrite par `project.yml` ; `Murmure.xcodeproj` en est généré et n'est pas versionné.

```bash
script/build_and_run.sh               # Debug : génère, compile, signe et lance
script/build_and_run.sh --build-only  # sans lancer
```

Le build va dans `~/Library/Caches/Murmure/Build` (`MURMURE_BUILD_DIR` pour un autre
dossier), hors des dossiers synchronisés par iCloud. Il est signé comme le fait
`install.sh` : Developer ID, sinon Apple Development, sinon ad hoc
(`MURMURE_SIGN_IDENTITY` pour choisir, « - » pour ad hoc). Même identifiant
(`dev.croustibat.murmure`) et même certificat que l'app installée : il en partage les
autorisations Micro et Accessibilité.

Ce build lit l'installation par défaut (`~/.local/share/murmure`) ; les variables
`MURMURE_*` de l'environnement lui sont transmises. Une seule Murmure tourne par
dossier d'état : quitter l'app installée, ou lancer le build à côté :

```bash
MURMURE_STATE_DIR=/tmp/murmure-dev MURMURE_SHORTCUT=ctrl+alt+shift+cmd+f19 script/build_and_run.sh
```

Sans les scripts, `xcodegen generate && xcodebuild -scheme Murmure` produit une app
signée ad hoc, dans les DerivedData de Xcode.

Le bundle contient l'app (`src/app/`) et, dans `Contents/Helpers`, les outils lancés
par `murmure.sh` : aujourd'hui la pastille (`overlay`, `src/overlay.swift`). Il tourne
sous runtime durci, avec deux entitlements (`app/Murmure.entitlements`) :
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

## Publier une version

Les versions sont des **GitHub Releases** étiquetées `vX.Y.Z`. `Murmure.app` se met à
jour avec Sparkle : au plus une fois par jour, elle lit `appcast.xml`, asset de la
dernière release (`SUFeedURL` : `releases/latest/download/appcast.xml`, lien stable).
Sparkle compare le `sparkle:version` de l'appcast au `CFBundleVersion` de l'app : seul
un nombre plus grand propose la mise à jour. L'archive doit porter la signature EdDSA
de la clé du compte `murmure` du trousseau (`sign_update --account murmure`), dont la
clé publique est `SUPublicEDKey`, et la même signature Developer ID que l'app installée.

L'app ne voit que la release « latest » : ni un simple tag, ni un brouillon, ni une
pré-version ne la déclenchent. Une release sans `appcast.xml` n'est pas vue (le journal
note l'erreur).

1. Mettre à jour `VERSION` sur `main` (`1.2.0`, sans `v`) :
   - correctif : `1.1.0` → `1.1.1` ;
   - fonctionnalité : `1.1.0` → `1.2.0` ;
   - changement qui oblige à réinstaller ou à reconfigurer : `1.1.0` → `2.0.0`.

   Augmenter aussi de 1 `CFBundleVersion` dans `app/Info.plist`.

   Committer (« Version 1.2.0 ») et pousser.

2. Vérifier que l'installation part bien de ce commit :

   ```bash
   git pull && ./install.sh
   ```

   Le menu de Murmure affiche « Murmure 1.2.0 ».

3. Étiqueter ce commit et publier la release :

   ```bash
   v=$(tr -d '[:space:]' < VERSION)
   git tag -a "v$v" -m "Murmure $v"
   git push origin "v$v"
   gh release create "v$v" --title "Murmure $v" --notes-file notes.md
   ```

   L'étiquette doit correspondre exactement au contenu de `VERSION` : une release
   `v1.2.0` pour un `VERSION` resté à `1.1.0` signalerait la mise à jour indéfiniment,
   même après `./install.sh`.

4. Les notes de release disent quoi faire aux versions ≤ 1.1.0, qui ne se mettent
   pas à jour seules. Modèle de `notes.md` :

   ```markdown
   ## Nouveautés
   - …

   ## Mettre à jour
   Dans le dossier où vous avez cloné Murmure :

       git pull && ./install.sh

   L'installeur indique en fin d'installation si `Murmure.app` a changé
   d'identité : dans ce cas, macOS redemande les autorisations Micro et
   Accessibilité.
   ```

La mise à jour se teste sans rien publier ni toucher au trousseau, à côté de l'app
installée :

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
et le dossier.
