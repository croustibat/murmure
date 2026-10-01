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

Les versions sont des **GitHub Releases** étiquetées `vX.Y.Z`. `Murmure.app` lit la
dernière (`/repos/croustibat/murmure/releases/latest`) au plus une fois par jour et
la compare à son propre numéro, tiré du fichier `VERSION` à la compilation
(`CFBundleShortVersionString`). Une release plus récente fait apparaître « Version
X.Y.Z disponible » dans le menu, qui ouvre sa page.

L'app ne voit que les releases publiées : ni un simple tag, ni un brouillon, ni une
pré-version ne la déclenchent. La comparaison est numérique (`1.10.0` > `1.9.2`), le
`v` initial est retiré.

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

4. Les notes de release disent quoi faire, puisque rien n'est installé
   automatiquement. Modèle de `notes.md` :

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

La vérification se teste sans rien publier, avec un faux JSON servi en local
(`MURMURE_RELEASES_URL` remplace l'adresse de l'API). Quitter d'abord Murmure : une
seule instance tourne à la fois.

```bash
mkdir -p /tmp/rel && echo '{"tag_name":"v9.9.9","html_url":"https://github.com/croustibat/murmure/releases"}' > /tmp/rel/latest
(cd /tmp/rel && python3 -m http.server 8765) &
rm -f ~/.local/share/murmure/.mises-a-jour   # oublie la vérification du jour
MURMURE_RELEASES_URL=http://127.0.0.1:8765/latest /Applications/Murmure.app/Contents/MacOS/Murmure
```

`$MURMURE_HOME/.mises-a-jour` garde la date de la dernière requête et la version
trouvée ; le supprimer autorise une nouvelle vérification immédiate.
