#!/bin/bash
# Signe Murmure.app de l'intérieur vers l'extérieur : chaque outil de
# Contents/Helpers, Sparkle.framework, puis l'app avec ses entitlements.
#
#   ./script/sign_app.sh <identité|-> <Murmure.app> [options codesign…]
#
# install.sh et build_and_run.sh compilent sans signer (CODE_SIGNING_ALLOWED=NO).
# Sous runtime durci, la notarisation rejette tout exécutable qui n'est pas
# signé par le même certificat : chaque outil l'est à part, sans --deep (qui
# donnerait à tous les entitlements de l'app). Un outil qui a besoin des siens
# les trouve dans app/<outil>.entitlements.
# ${@+"$@"} : bash 3.2 de macOS juge "$@" vide non défini sous set -u.
set -euo pipefail

IDENTITY="$1"
APP="$2"
shift 2
ROOT="$(cd "$(dirname "$0")/.." && pwd)"

for outil in "$APP"/Contents/Helpers/*; do
    [ -f "$outil" ] || continue
    nom="$(basename "$outil")"
    ent=()
    [ -f "$ROOT/app/$nom.entitlements" ] && ent=(--entitlements "$ROOT/app/$nom.entitlements")
    codesign --force --sign "$IDENTITY" --options runtime --identifier "dev.croustibat.murmure.$nom" \
        ${ent[@]+"${ent[@]}"} ${@+"$@"} "$outil"
done

# Sparkle arrive signé par ses auteurs : sous runtime durci, l'app refuse de
# charger un framework d'une autre équipe. Ses services XPC ne servent qu'aux
# apps sandboxées, ce que Murmure n'est pas : retirés plutôt que signés et
# notarisés pour rien.
SPARKLE="$APP/Contents/Frameworks/Sparkle.framework"
if [ -d "$SPARKLE" ]; then
    rm -rf "$SPARKLE/Versions/B/XPCServices" "$SPARKLE/XPCServices"
    for composant in "$SPARKLE/Versions/B/Autoupdate" "$SPARKLE/Versions/B/Updater.app" "$SPARKLE"; do
        codesign --force --sign "$IDENTITY" --options runtime ${@+"$@"} "$composant"
    done
fi

# Ad hoc, l'app n'a pas d'équipe : sans Murmure-adhoc.entitlements, le runtime
# durci refuserait de charger Sparkle.
ENTITLEMENTS="$ROOT/app/Murmure.entitlements"
[ "$IDENTITY" = - ] && ENTITLEMENTS="$ROOT/app/Murmure-adhoc.entitlements"
codesign --force --sign "$IDENTITY" --options runtime ${@+"$@"} \
    --entitlements "$ENTITLEMENTS" "$APP"
codesign --verify --deep --strict "$APP"
