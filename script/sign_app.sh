#!/bin/bash
# Signe Murmure.app de l'intérieur vers l'extérieur : chaque outil de
# Contents/Helpers, puis l'app avec ses entitlements.
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

codesign --force --sign "$IDENTITY" --options runtime ${@+"$@"} \
    --entitlements "$ROOT/app/Murmure.entitlements" "$APP"
codesign --verify --deep --strict "$APP"
