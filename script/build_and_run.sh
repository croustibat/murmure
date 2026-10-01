#!/bin/bash
# Compile Murmure.app en Debug, la signe et la lance.
#
#   ./script/build_and_run.sh               # compile, signe et lance
#   ./script/build_and_run.sh --build-only  # compile et signe seulement
#
# Signature : MURMURE_SIGN_IDENTITY (nom ou empreinte SHA-1, « - » pour ad hoc),
# sinon Developer ID, puis Apple Development, sinon ad hoc — comme install.sh.
# Même identifiant et même certificat que l'app installée : ce build en
# partage les autorisations Micro et Accessibilité.
# Les variables MURMURE_* de l'environnement sont transmises à l'app
# (MURMURE_HOME, MURMURE_STATE_DIR, MURMURE_SHORTCUT…), ce que open ne fait
# pas de lui-même.
set -euo pipefail

MODE="${1:-run}"
case "$MODE" in run|--build-only) ;; *) echo "usage : $0 [--build-only]" >&2; exit 2 ;; esac
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# Comme Sillage : compiler hors des dossiers synchronisés par iCloud, qui
# ajoutent des attributs au bundle entre la compilation et la signature.
BUILD_DIR="${MURMURE_BUILD_DIR:-$HOME/Library/Caches/Murmure/Build}"
APP="$BUILD_DIR/Build/Products/Debug/Murmure.app"
cd "$ROOT"

# Une seule instance par dossier d'état : ce build s'arrêterait aussitôt
# devant une Murmure déjà lancée. On remplace un build précédent, jamais une
# autre installation.
if [ "$MODE" = run ]; then
    pkill -f "$APP/Contents/MacOS/Murmure" 2>/dev/null || true
    for _ in $(seq 1 20); do pgrep -f "$APP/Contents/MacOS/Murmure" >/dev/null || break; sleep 0.1; done
    if [ -z "${MURMURE_STATE_DIR:-}" ] && pgrep -x Murmure >/dev/null; then
        echo "Murmure tourne déjà : quittez-la depuis son menu, ou lancez ce build à côté avec" >&2
        echo "MURMURE_STATE_DIR=<dossier> et un autre MURMURE_SHORTCUT." >&2
        exit 1
    fi
fi

command -v xcodegen >/dev/null || { echo "XcodeGen est requis : brew install xcodegen" >&2; exit 1; }
xcodegen generate --quiet
mkdir -p "$BUILD_DIR"
echo "▸ Compilation de Murmure…"
if ! xcodebuild -project Murmure.xcodeproj -scheme Murmure -configuration Debug \
    -derivedDataPath "$BUILD_DIR" -destination 'platform=macOS,arch=arm64' \
    CODE_SIGNING_ALLOWED=NO build >"$BUILD_DIR/build.log" 2>&1; then
    tail -50 "$BUILD_DIR/build.log"
    exit 1
fi

# « empreinte nom » de la première identité valide dont le nom commence par $1 ;
# l'empreinte départage deux certificats du même nom.
identite() {
    security find-identity -v -p codesigning 2>/dev/null \
        | sed -n "s/^ *[0-9]*) \([0-9A-F]\{40\}\) \"\($1.*\)\"$/\1 \2/p" | head -1 || true
}
if [ -n "${MURMURE_SIGN_IDENTITY:-}" ]; then
    LIGNE="$MURMURE_SIGN_IDENTITY $MURMURE_SIGN_IDENTITY"
else
    LIGNE="$(identite 'Developer ID Application: ')"
    [ -n "$LIGNE" ] || LIGNE="$(identite 'Apple Development: ')"
    [ -n "$LIGNE" ] || LIGNE="- ad hoc"
fi
script/sign_app.sh "${LIGNE%% *}" "$APP" --timestamp=none
echo "✓ $APP (${LIGNE#* })"

[ "$MODE" = run ] || exit 0
ENV_ARGS=()
for cle in $(compgen -e | grep '^MURMURE_' || true); do ENV_ARGS+=(--env "$cle=${!cle}"); done
open -n ${ENV_ARGS[@]+"${ENV_ARGS[@]}"} "$APP"
