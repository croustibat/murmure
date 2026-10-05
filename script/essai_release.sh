#!/bin/bash
# Essai de mise à jour Sparkle avec le DMG et l'appcast que produit
# script/release.sh, sans rien publier. Une build plus ancienne, tirée du même
# DMG, est installée sous /private/tmp et lit l'appcast servi en local ;
# Sparkle télécharge le DMG et l'installe à la fermeture de l'app. Le script
# vérifie ensuite que l'app installée est exactement celle du DMG.
#
#   xcrun swift script/cle_sparkle.swift nouvelle /private/tmp/cle.txt
#   ./script/release.sh 1.2.0 --dry-run --no-notarize --ed-key-file /private/tmp/cle.txt
#   ./script/essai_release.sh /private/tmp/<dossier> /private/tmp/cle.txt
#
# La clé est celle qui a signé dist/appcast.xml. La build d'essai porte le
# flux local, la clé publique de test, la mise à jour automatique (téléchargée
# en arrière-plan, installée à la fermeture : aucun clic) et, par
# LSEnvironment, un MURMURE_HOME et un dossier d'état à part, avec le raccourci
# ⌃⌥⇧⌘F19. L'app du DMG n'est jamais lancée : sans LSEnvironment, elle lirait
# les données de l'installation réelle. D'où l'installation à la fermeture,
# qui ne relance pas l'app, plutôt que « Installer et relancer ».
#
# Partagé avec l'app réelle (même identifiant, même signature) : le domaine de
# réglages dev.croustibat.murmure. SULastCheckTime en est retiré pour que
# l'essai vérifie dès le lancement ; toutes les clés SU* retrouvent ensuite
# leur valeur d'avant. ESSAI_PORT (8745) : port du serveur local.
set -euo pipefail

DOSSIER="${1:-}"
CLE="${2:-}"
case "$DOSSIER" in
    /private/tmp/?*) ;;
    *) echo "usage : $0 /private/tmp/<dossier> <clé de test>" >&2; exit 2 ;;
esac
[ -r "$CLE" ] || { echo "usage : $0 /private/tmp/<dossier> <clé de test>" >&2; exit 2; }
fail() { printf '✗ %s\n' "$1" >&2; exit 1; }
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DMG="$ROOT/dist/Murmure.dmg"
APPCAST="$ROOT/dist/appcast.xml"
PORT="${ESSAI_PORT:-8745}"
DOMAINE=dev.croustibat.murmure
APP="$DOSSIER/Applications/Murmure.app"
LSREGISTER=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister
cd "$ROOT"
[ -f "$DMG" ] && [ -f "$APPCAST" ] || fail "dist/Murmure.dmg ou dist/appcast.xml manquant : lancer d'abord script/release.sh"

attribut() { perl -0ne 'print $1 if /<enclosure\b[^>]*\b'"$1"'="([^"]*)"/' "$APPCAST"; }
element() { perl -0ne 'print $1 if m{<'"$1"'>([^<]*)</'"$1"'>}' "$APPCAST"; }
VERSION="$(element sparkle:shortVersionString)"
BUILD="$(element sparkle:version)"
[[ $BUILD =~ ^[0-9]+$ ]] && [ "$BUILD" -ge 2 ] \
    || fail "build $BUILD : il en faut un ≥ 2 pour installer un build plus ancien (release.sh X.Y.Z --dry-run)"
PUB="$(xcrun swift script/cle_sparkle.swift publique "$CLE")"
xcrun swift script/cle_sparkle.swift verifier "$PUB" "$(attribut sparkle:edSignature)" "$DMG" >/dev/null \
    || fail "dist/appcast.xml n'est pas signé par $CLE : relancer release.sh avec --ed-key-file $CLE"

# Même équipe que l'app du DMG : Sparkle n'accepte une autre clé EdDSA que si
# la nouvelle app satisfait l'exigence de signature de l'ancienne.
IDENTITE="$(security find-identity -v -p codesigning 2>/dev/null \
    | sed -n 's/^ *[0-9]*) \([0-9A-F]\{40\}\) "Developer ID Application: .* (MMJD6CLKNQ)"$/\1/p' | head -1 || true)"
[ -n "$IDENTITE" ] || fail "aucun certificat Developer ID de l'équipe MMJD6CLKNQ"

# Réglages SU* d'avant l'essai, « clé<TAB>type<TAB>valeur », remis à la fin.
cles_su() { defaults read "$DOMAINE" 2>/dev/null | sed -n 's/^ *"\{0,1\}\(SU[A-Za-z]*\)"\{0,1\} = .*/\1/p'; }
CAPTURE="$DOSSIER/reglages-avant"
# Caches de Sparkle et d'URLSession, partagés aussi : retirés à la fin s'ils
# n'existaient pas.
CACHE_SPARKLE="$HOME/Library/Caches/$DOMAINE/org.sparkle-project.Sparkle"
CACHE_HTTP="$HOME/Library/Caches/$DOMAINE/fsCachedData"
CACHE_NEUF=0; HTTP_NEUF=0
[ -e "$CACHE_SPARKLE" ] || CACHE_NEUF=1
[ -e "$CACHE_HTTP" ] || HTTP_NEUF=1
# Xcode et LaunchServices inscrivent aussi les apps imbriquées (Updater.app).
desinscrire() { [ ! -e "$1" ] || find "$1" -name '*.app' -type d -exec "$LSREGISTER" -u {} \; 2>/dev/null || true; }
SERVEUR=""
PID=""
restaurer() {
    [ -z "$SERVEUR" ] || { kill "$SERVEUR"; wait "$SERVEUR"; } 2>/dev/null || true
    [ -z "$PID" ] || ! kill -0 "$PID" 2>/dev/null || kill "$PID" 2>/dev/null || true
    hdiutil detach "$DOSSIER/montage" -quiet 2>/dev/null || true
    # Toute app de l'essai sort de LaunchServices : plus récente que l'app
    # réelle, elle pourrait être choisie à sa place pour l'identifiant.
    desinscrire "$DOSSIER"
    if [ "$CACHE_NEUF" = 1 ] && [ -e "$CACHE_SPARKLE" ]; then
        desinscrire "$CACHE_SPARKLE"
        rm -rf "$CACHE_SPARKLE"
    fi
    [ "$HTTP_NEUF" = 0 ] || rmdir "$CACHE_HTTP" 2>/dev/null || true
    [ -f "$CAPTURE" ] || return 0
    local cle type valeur
    for cle in $(cles_su); do
        grep -q "^$cle	" "$CAPTURE" || defaults delete "$DOMAINE" "$cle" || true
    done
    while IFS=$'\t' read -r cle type valeur; do
        case "$type" in
            date) defaults write "$DOMAINE" "$cle" -date "$valeur" ;;
            boolean) defaults write "$DOMAINE" "$cle" -bool "$([ "$valeur" = 1 ] && echo true || echo false)" ;;
            integer) defaults write "$DOMAINE" "$cle" -int "$valeur" ;;
            float) defaults write "$DOMAINE" "$cle" -float "$valeur" ;;
            string) defaults write "$DOMAINE" "$cle" -string "$valeur" ;;
            *) echo "! $cle ($type) non restaurée : $valeur" >&2 ;;
        esac
    done <"$CAPTURE"
    rm -f "$CAPTURE"
    echo "  réglages SU* de $DOMAINE remis en l'état"
}
trap restaurer EXIT

desinscrire "$DOSSIER"
rm -rf "$DOSSIER"
mkdir -p "$DOSSIER"/{Applications,home/models,etat,serveur,montage}

echo "▸ Build d'essai : le DMG $VERSION ($BUILD), ramené au build $((BUILD - 1))…"
hdiutil attach -readonly -nobrowse -noautoopen -mountpoint "$DOSSIER/montage" "$DMG" -quiet
[ "$(readlink "$DOSSIER/montage/Applications")" = /Applications ] || fail "le DMG n'a pas de lien vers /Applications"
ditto "$DOSSIER/montage/Murmure.app" "$APP"
CDHASH_DMG="$(codesign -dvvv "$DOSSIER/montage/Murmure.app" 2>&1 | sed -n 's/^CDHash=//p')"
hdiutil detach "$DOSSIER/montage" -quiet
/usr/libexec/PlistBuddy \
    -c "Set :CFBundleVersion $((BUILD - 1))" -c "Set :CFBundleShortVersionString $VERSION-essai" \
    -c "Set :SUFeedURL http://127.0.0.1:$PORT/appcast.xml" -c "Set :SUPublicEDKey $PUB" \
    -c "Add :SUAutomaticallyUpdate bool true" \
    -c "Add :LSEnvironment dict" \
    -c "Add :LSEnvironment:MURMURE_HOME string $DOSSIER/home" \
    -c "Add :LSEnvironment:MURMURE_STATE_DIR string $DOSSIER/etat" \
    -c "Add :LSEnvironment:MURMURE_AX_NO_PROMPT string 1" \
    -c "Add :LSEnvironment:MURMURE_MODEL string $DOSSIER/home/models/faux.bin" \
    "$APP/Contents/Info.plist"
script/sign_app.sh "$IDENTITE" "$APP" --timestamp=none >"$DOSSIER/signature.log" 2>&1 \
    || { cat "$DOSSIER/signature.log" >&2; fail "signature de la build d'essai impossible"; }
# Raccourci de test, jamais celui de l'app réelle ; faux modèle et faux
# whisper-cli : ni fenêtre de téléchargement, ni préchauffage de 30 s.
printf 'MURMURE_SHORTCUT=ctrl+alt+shift+cmd+f19\nMURMURE_WHISPER=/usr/bin/true\n' >"$DOSSIER/home/config"
: >"$DOSSIER/home/models/faux.bin"

# Appcast de release.sh tel quel, sauf l'adresse du DMG.
cp "$DMG" "$DOSSIER/serveur/Murmure.dmg"
sed "s#url=\"[^\"]*/Murmure.dmg\"#url=\"http://127.0.0.1:$PORT/Murmure.dmg\"#" "$APPCAST" >"$DOSSIER/serveur/appcast.xml"
(cd "$DOSSIER/serveur" && exec python3 -m http.server "$PORT" --bind 127.0.0.1) 2>"$DOSSIER/serveur.log" &
SERVEUR=$!

for cle in $(cles_su); do
    printf '%s\t%s\t%s\n' "$cle" "$(defaults read-type "$DOMAINE" "$cle" | sed 's/^Type is //')" \
        "$(defaults read "$DOMAINE" "$cle")"
done >"$CAPTURE"
defaults delete "$DOMAINE" SULastCheckTime 2>/dev/null || true

echo "▸ Lancement de la build d'essai ($VERSION-essai, build $((BUILD - 1)))…"
open -n "$APP"
for _ in $(seq 1 50); do PID="$(pgrep -f "^$APP/Contents/MacOS/Murmure" | head -1 || true)"; [ -z "$PID" ] || break; sleep 0.2; done
[ -n "$PID" ] || fail "la build d'essai ne démarre pas"

attendre() {  # secondes commande… : vrai dès que la commande réussit
    local limite=$(( $(date +%s) + $1 )); shift
    until "$@"; do [ "$(date +%s)" -lt "$limite" ] || return 1; sleep 1; done
}
attendre 60 grep -q 'GET /Murmure.dmg HTTP/1.1" 200' "$DOSSIER/serveur.log" \
    || { cat "$DOSSIER/etat/murmure.log" "$DOSSIER/serveur.log" >&2; fail "Sparkle n'a pas téléchargé le DMG"; }
echo "  ✓ appcast lu et DMG téléchargé"
# Prêt à installer quand l'installateur de Sparkle a extrait la nouvelle app.
extraite() {
    find "$CACHE_SPARKLE" -path '*/Murmure.app/Contents/Info.plist' 2>/dev/null \
        | while read -r p; do /usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$p" 2>/dev/null; done | grep -qx "$BUILD"
}
attendre 60 extraite || fail "l'installateur de Sparkle n'a pas extrait la mise à jour"
sleep 3
echo "▸ Fermeture de la build d'essai (pid $PID) : Sparkle installe à la fermeture"
xcrun swift - "$PID" <<'SWIFT'
import AppKit
guard let pid = Int32(CommandLine.arguments[1]), let app = NSRunningApplication(processIdentifier: pid) else { exit(1) }
exit(app.terminate() ? 0 : 1)
SWIFT
attendre 30 eval '! kill -0 "$PID" 2>/dev/null' || fail "la build d'essai ne se ferme pas"
PID=""
installee() { [ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$APP/Contents/Info.plist" 2>/dev/null)" = "$BUILD" ]; }
attendre 60 installee || fail "$APP est restée au build $((BUILD - 1))"
sleep 2
RELANCEE="$(pgrep -f "^$APP/Contents/MacOS/Murmure" || true)"
if [ -n "$RELANCEE" ]; then
    PID="${RELANCEE%%[!0-9]*}"   # arrêtée par restaurer, c'est l'app de l'essai
    fail "l'app installée a été relancée (pid $PID) : elle lirait les données réelles"
fi

CDHASH="$(codesign -dvvv "$APP" 2>&1 | sed -n 's/^CDHash=//p')"
codesign --verify --deep --strict "$APP" || fail "codesign refuse l'app installée"
[ "$CDHASH" = "$CDHASH_DMG" ] || fail "l'app installée ($CDHASH) n'est pas celle du DMG ($CDHASH_DMG)"
echo "  ✓ $APP : $VERSION ($BUILD), signature valide, CDHash $CDHASH identique à l'app du DMG"
echo "  journal de l'essai :"
grep 'mises à jour' "$DOSSIER/etat/murmure.log" | sed 's/^/    /'
echo "  serveur :"
sed -n 's/^.*"\(GET [^ ]*\) HTTP[^"]*" \([0-9]*\).*/    \1 \2/p' "$DOSSIER/serveur.log"
