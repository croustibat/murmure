#!/bin/bash
# Compile whisper-cli depuis whisper.cpp, pour l'embarquer dans Murmure.app
# (Contents/Helpers/whisper-cli) : l'app distribuée ne peut pas compter sur
# Homebrew.
#
#   scripts/build-whisper.sh
#
# Version figée dans scripts/whisper.version. Binaire arm64 pour macOS 14 et
# plus, ggml lié statiquement, shader Metal intégré (aucun fichier .metal à
# livrer) : il ne dépend que de bibliothèques du système. Sortie :
# build/whisper/whisper-cli, recompilé seulement si la version, les options
# ou le compilateur changent. rm -rf build/whisper repart de zéro.
#
# Prérequis : outils Xcode (xcode-select --install) et CMake. Sans Homebrew,
# CMake s'obtient sur https://cmake.org/download/ (CMake.app, trouvé tel quel
# dans /Applications) ou par « python3 -m pip install --user cmake ».
# CMAKE=/chemin/vers/cmake impose un exécutable précis.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
VERSION_FILE="$ROOT/scripts/whisper.version"
LICENCE="$ROOT/app/Licences/whisper.cpp.txt"
OUT="$ROOT/build/whisper"
SRC="$OUT/src"
BUILD="$OUT/cmake"
LOG="$OUT/compilation.log"
BIN="$OUT/whisper-cli"
STAMP="$BIN.empreinte"
REPO_URL="https://github.com/ggml-org/whisper.cpp.git"
DEPLOYMENT_TARGET="14.0"

bold=$'\033[1m'; green=$'\033[32m'; red=$'\033[31m'; off=$'\033[0m'
step() { printf '%s==>%s %s\n' "$bold" "$off" "$1"; }
ok()   { printf '    %s✓%s %s\n' "$green" "$off" "$1"; }
fail() { printf '%s✗%s %s\n' "$red" "$off" "$1" >&2; exit 1; }

[ "$(uname -s)" = "Darwin" ] || fail "whisper-cli se compile sur macOS."

# CMake est cherché dans le PATH de l'appelant, puis le PATH est réduit au
# système : Homebrew ne doit rien fournir à la compilation, même installé.
CMAKE="${CMAKE:-$(command -v cmake || true)}"
if [ -z "$CMAKE" ] && [ -x /Applications/CMake.app/Contents/bin/cmake ]; then
  CMAKE=/Applications/CMake.app/Contents/bin/cmake
fi
[ -n "$CMAKE" ] && [ -x "$CMAKE" ] || fail "CMake introuvable. Installez CMake.app depuis https://cmake.org/download/ (dans /Applications), ou : python3 -m pip install --user cmake — puis relancez, au besoin avec CMAKE=/chemin/vers/cmake."
export PATH="/usr/bin:/bin:/usr/sbin:/sbin"
xcrun --find clang >/dev/null 2>&1 || fail "outils Xcode requis : xcode-select --install"

version_key() { sed -n "s/^$1=//p" "$VERSION_FILE" | tail -1 | tr -d '[:space:]'; }
TAG="$(version_key WHISPER_TAG)"
COMMIT="$(version_key WHISPER_COMMIT)"
[[ $TAG =~ ^v[0-9][0-9.]*$ ]] && [[ $COMMIT =~ ^[0-9a-f]{40}$ ]] \
  || fail "scripts/whisper.version illisible (WHISPER_TAG=vX.Y.Z, WHISPER_COMMIT=<40 caractères hexadécimaux>)"

# Compilateur d'Xcode imposé : un clang de Homebrew dans le PATH ne doit pas
# le remplacer. CMAKE_IGNORE_PREFIX_PATH écarte les préfixes de Homebrew et
# MacPorts, où CMake chercherait sinon (libomp de Homebrew, ou make).
# GGML_NATIVE=OFF : le socle Apple M1 plutôt que le processeur de la machine
# qui compile, pour tourner sur tous les Mac Apple Silicon. Sans OpenMP :
# le clang d'Xcode n'en fournit pas. Les exemples sont configurés parce que
# whisper-cli en fait partie, mais seule sa cible est compilée.
OPTIONS=(
  -DCMAKE_BUILD_TYPE=Release
  -DCMAKE_OSX_ARCHITECTURES=arm64
  "-DCMAKE_OSX_DEPLOYMENT_TARGET=$DEPLOYMENT_TARGET"
  "-DCMAKE_C_COMPILER=$(xcrun --find clang)"
  "-DCMAKE_CXX_COMPILER=$(xcrun --find clang++)"
  "-DCMAKE_IGNORE_PREFIX_PATH=/opt/homebrew;/usr/local;/opt/local"
  -DBUILD_SHARED_LIBS=OFF
  -DGGML_METAL=ON
  -DGGML_METAL_EMBED_LIBRARY=ON
  -DGGML_NATIVE=OFF
  -DGGML_OPENMP=OFF
  -DGGML_CCACHE=OFF
  -DWHISPER_BUILD_EXAMPLES=ON
  -DWHISPER_BUILD_TESTS=OFF
  -DWHISPER_BUILD_SERVER=OFF
  -DWHISPER_CURL=OFF
  -DWHISPER_SDL2=OFF
)
FINGERPRINT="$( { printf '%s\n' "$TAG" "$COMMIT" "${OPTIONS[@]}"; xcrun clang --version | head -1; xcrun --show-sdk-version; } | shasum -a 256 | cut -d' ' -f1)"

# Seules /usr/lib et /System sont présentes sur tous les Mac : toute autre
# bibliothèque liée ferait échouer whisper-cli chez l'utilisateur.
check_libraries() {
  local foreign
  foreign="$(otool -L "$1" | tail -n +2 | awk '{ print $1 }' | grep -Ev '^/(usr/lib|System)/' | tr '\n' ' ' || true)"
  [ -z "$foreign" ] || fail "$1 dépend de bibliothèques hors du système : $foreign"
  [ "$(lipo -archs "$1")" = "arm64" ] || fail "$1 n'est pas un binaire arm64 seul ($(lipo -archs "$1"))"
}

if [ -x "$BIN" ] && [ "$(cat "$STAMP" 2>/dev/null)" = "$FINGERPRINT" ]; then
  check_libraries "$BIN"
  ok "build/whisper/whisper-cli déjà à jour ($TAG)"
  exit 0
fi

mkdir -p "$OUT"
if [ "$(git -C "$SRC" rev-parse HEAD 2>/dev/null)" != "$COMMIT" ]; then
  step "Téléchargement de whisper.cpp $TAG"
  rm -rf "$SRC" "$SRC.part"
  # fetch plutôt que clone --branch, qui avertit sur une étiquette annotée.
  { git init --quiet "$SRC.part" \
      && git -C "$SRC.part" fetch --quiet --depth 1 "$REPO_URL" "refs/tags/$TAG" \
      && git -C "$SRC.part" -c advice.detachedHead=false checkout --quiet FETCH_HEAD; } \
    || fail "téléchargement de whisper.cpp $TAG impossible"
  got="$(git -C "$SRC.part" rev-parse HEAD)"
  [ "$got" = "$COMMIT" ] \
    || { rm -rf "$SRC.part"; fail "l'étiquette $TAG pointe sur $got, pas sur $COMMIT (scripts/whisper.version) — vérifiez le dépôt avant de changer le commit"; }
  mv "$SRC.part" "$SRC"
  ok "sources au commit ${COMMIT:0:12}"
fi

# La licence livrée dans l'app doit être celle de la version compilée.
perl -e 'local $/; open my $l, "<", $ARGV[0] or exit 2; open my $f, "<", $ARGV[1] or exit 2;
           exit(index(<$f>, <$l>) < 0)' "$SRC/LICENSE" "$LICENCE" \
  || fail "app/Licences/whisper.cpp.txt ne contient pas la licence de whisper.cpp $TAG : mettez-le à jour"

# Arbre de compilation repris de zéro : un CMakeCache d'une autre version ou
# d'autres options pourrait survivre à la reconfiguration.
step "Compilation de whisper-cli $TAG (journal : build/whisper/compilation.log)"
rm -rf "$BUILD"
{ "$CMAKE" -S "$SRC" -B "$BUILD" "${OPTIONS[@]}" \
    && "$CMAKE" --build "$BUILD" --target whisper-cli --parallel "$(sysctl -n hw.ncpu)"; } >"$LOG" 2>&1 \
  || { tail -20 "$LOG" >&2; fail "compilation impossible — détail dans build/whisper/compilation.log"; }
check_libraries "$BUILD/bin/whisper-cli"

cp "$BUILD/bin/whisper-cli" "$BIN.new"
mv -f "$BIN.new" "$BIN"
echo "$FINGERPRINT" >"$STAMP"
ok "build/whisper/whisper-cli ($TAG, arm64, macOS $DEPLOYMENT_TARGET+, bibliothèques système uniquement)"
