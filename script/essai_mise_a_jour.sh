#!/bin/bash
# Essai de bout en bout d'une mise à jour Sparkle, sans rien publier : deux
# builds de test (même binaire, versions différentes), la seconde en DMG
# décrite par un appcast signé avec une clé EdDSA jetable et servie en local,
# la première installée et lancée. Tout vit dans un dossier sous /private/tmp.
#
#   ./script/essai_mise_a_jour.sh /private/tmp/murmure-essai             # prépare
#   ./script/essai_mise_a_jour.sh /private/tmp/murmure-essai --nettoyer  # après l'essai
#
# Ni la clé du trousseau, ni l'installation réelle (~/.local/share/murmure,
# /Applications/Murmure.app) ne sont utilisées : les builds de test portent
# leur propre flux, leur propre clé publique, et (LSEnvironment, qui survit à
# la relance par Sparkle) leurs propres MURMURE_HOME et dossier d'état. Même
# identifiant et même signature que l'app réelle : elles en partagent les
# autorisations, que la mise à jour doit conserver.
#
# Variables : MURMURE_SIGN_IDENTITY (comme build_and_run.sh), ESSAI_PORT
# (8744), ESSAI_V1/ESSAI_B1 et ESSAI_V2/ESSAI_B2 (versions affichées et
# CFBundleVersion, 1.2.0/2 et 1.2.1/3).
set -euo pipefail

DOSSIER="${1:-}"
case "$DOSSIER" in
    /private/tmp/?*) ;;
    *) echo "usage : $0 /private/tmp/<dossier>" >&2; exit 2 ;;
esac
ROOT="$(cd "$(dirname "$0")/.." && pwd)"

# Sparkle range ses réglages (dernière vérification…) dans le domaine de
# l'identifiant, partagé avec l'app réelle : seules ses clés SU* sont retirées
# (celles de l'app réelle aussi, si elle a déjà Sparkle).
if [ "${2:-}" = --nettoyer ]; then
    defaults read dev.croustibat.murmure 2>/dev/null \
        | sed -n 's/^ *"\{0,1\}\(SU[A-Za-z]*\)"\{0,1\} = .*/\1/p' \
        | while read -r cle; do defaults delete dev.croustibat.murmure "$cle"; done
    rm -rf "$HOME/Library/Caches/dev.croustibat.murmure/org.sparkle-project.Sparkle" "$DOSSIER"
    echo "✓ Réglages et caches de Sparkle retirés, $DOSSIER supprimé."
    exit 0
fi
PORT="${ESSAI_PORT:-8744}"
V1="${ESSAI_V1:-1.2.0}"; B1="${ESSAI_B1:-2}"
V2="${ESSAI_V2:-1.2.1}"; B2="${ESSAI_B2:-3}"
FLUX="http://127.0.0.1:$PORT/appcast.xml"
APP="$DOSSIER/Applications/Murmure.app"
mkdir -p "$DOSSIER"/{cle,home,etat,serveur,Applications}
cd "$ROOT"

echo "▸ Compilation (Release)…"
xcodegen generate --quiet
xcodebuild -project Murmure.xcodeproj -scheme Murmure -configuration Release \
    -derivedDataPath "$DOSSIER/build" -destination 'platform=macOS,arch=arm64' \
    CODE_SIGNING_ALLOWED=NO build >"$DOSSIER/build.log" 2>&1 \
    || { tail -30 "$DOSSIER/build.log" >&2; exit 1; }
PRODUIT="$DOSSIER/build/Build/Products/Release/Murmure.app"
OUTILS="$DOSSIER/build/SourcePackages/artifacts/sparkle/Sparkle/bin"

# Clé jetable, en fichier : graine Ed25519 en base64, le format que lisent
# sign_update et generate_appcast avec --ed-key-file.
if [ ! -s "$DOSSIER/cle/privee.txt" ]; then
    cat >"$DOSSIER/cle/cle.swift" <<'SWIFT'
import CryptoKit
import Foundation
let cle = Curve25519.Signing.PrivateKey()
let dossier = CommandLine.arguments[1]
try (cle.rawRepresentation.base64EncodedString() + "\n").write(toFile: dossier + "/privee.txt", atomically: true, encoding: .utf8)
try (cle.publicKey.rawRepresentation.base64EncodedString() + "\n").write(toFile: dossier + "/publique.txt", atomically: true, encoding: .utf8)
SWIFT
    swift "$DOSSIER/cle/cle.swift" "$DOSSIER/cle"
    chmod 600 "$DOSSIER/cle/privee.txt"
fi
CLE_PUBLIQUE="$(tr -d '[:space:]' <"$DOSSIER/cle/publique.txt")"

identite() {
    security find-identity -v -p codesigning 2>/dev/null \
        | sed -n "s/^ *[0-9]*) \([0-9A-F]\{40\}\) \"$1.*\"$/\1/p" | head -1 || true
}
IDENTITE="${MURMURE_SIGN_IDENTITY:-$(identite 'Developer ID Application: ')}"
[ -n "$IDENTITE" ] || IDENTITE="$(identite 'Apple Development: ')"
[ -n "$IDENTITE" ] || IDENTITE=-

# Une build de test : versions, flux et clé de l'essai, environnement isolé.
preparer() {  # destination version build
    rm -rf "$1"
    ditto "$PRODUIT" "$1"
    local p="$1/Contents/Info.plist"
    /usr/libexec/PlistBuddy \
        -c "Set :CFBundleShortVersionString $2" -c "Set :CFBundleVersion $3" \
        -c "Set :SUFeedURL $FLUX" -c "Set :SUPublicEDKey $CLE_PUBLIQUE" \
        -c "Add :LSEnvironment dict" \
        -c "Add :LSEnvironment:MURMURE_HOME string $DOSSIER/home" \
        -c "Add :LSEnvironment:MURMURE_STATE_DIR string $DOSSIER/etat" \
        -c "Add :LSEnvironment:MURMURE_AX_NO_PROMPT string 1" "$p"
    script/sign_app.sh "$IDENTITE" "$1" --timestamp=none >"$DOSSIER/signature.log" 2>&1 \
        || { cat "$DOSSIER/signature.log" >&2; exit 1; }
}

echo "▸ Builds $V1 ($B1) et $V2 ($B2), signées par ${IDENTITE}…"
preparer "$DOSSIER/v2/Murmure.app" "$V2" "$B2"
rm -rf "$DOSSIER/dmg" && mkdir -p "$DOSSIER/dmg"
ditto "$DOSSIER/v2/Murmure.app" "$DOSSIER/dmg/Murmure.app"
ln -s /Applications "$DOSSIER/dmg/Applications"
rm -rf "$DOSSIER/serveur" && mkdir -p "$DOSSIER/serveur"
hdiutil create -volname Murmure -srcfolder "$DOSSIER/dmg" -fs HFS+ -format UDZO -quiet "$DOSSIER/serveur/Murmure.dmg"
"$OUTILS/generate_appcast" --ed-key-file "$DOSSIER/cle/privee.txt" \
    --download-url-prefix "http://127.0.0.1:$PORT/" --maximum-deltas 0 \
    -o "$DOSSIER/serveur/appcast.xml" "$DOSSIER/serveur" >"$DOSSIER/appcast.log" 2>&1 \
    || { cat "$DOSSIER/appcast.log" >&2; exit 1; }
grep -q 'sparkle:edSignature=' "$DOSSIER/serveur/appcast.xml" || { echo "appcast non signé" >&2; exit 1; }

# Raccourci de test, jamais celui de l'app réelle.
[ -f "$DOSSIER/home/config" ] || echo "MURMURE_SHORTCUT=ctrl+alt+shift+cmd+f19" >"$DOSSIER/home/config"
preparer "$APP" "$V1" "$B1"

cat <<FIN
✓ Prêt.
  Serveur  : (cd $DOSSIER/serveur && python3 -m http.server $PORT --bind 127.0.0.1)
  Lancer   : open $APP
  Journal  : $DOSSIER/etat/murmure.log
  Vérifier : /usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' $APP/Contents/Info.plist   # $B2 après la mise à jour
  Ensuite  : quitter l'app de test, arrêter le serveur, puis $0 $DOSSIER --nettoyer
FIN
