#!/bin/bash
# Met le cask Homebrew de Murmure (Casks/murmure.rb de croustibat/homebrew-tap)
# à une version publiée : version et empreinte SHA-256 du DMG de la release
# GitHub, puis commit et push dans le tap. release.sh le propose à la fin
# d'une publication.
#
#   ./script/update-cask.sh          # version de VERSION
#   ./script/update-cask.sh 1.2.1
#
# L'empreinte est celle du DMG téléchargé à l'adresse même du cask : celle que
# Homebrew vérifiera chez l'utilisateur. TAP_SLUG désigne un autre tap.
set -euo pipefail

fail() { printf '✗ %s\n' "$1" >&2; exit 1; }
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
REPO="croustibat/murmure"
TAP_SLUG="${TAP_SLUG:-croustibat/homebrew-tap}"
VERSION="${1:-$(tr -d '[:space:]' < "$ROOT/VERSION")}"
[[ $VERSION =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo "usage : $0 [X.Y.Z]" >&2; exit 2; }
URL="https://github.com/$REPO/releases/download/v$VERSION/Murmure.dmg"

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

echo "▸ DMG publié : $URL"
curl -fsSL --retry 3 -o "$WORK/Murmure.dmg" "$URL" \
    || fail "DMG introuvable : la release v$VERSION est-elle publiée ?"
SHA="$(shasum -a 256 "$WORK/Murmure.dmg" | cut -d' ' -f1)"
echo "  sha256 $SHA"

git clone -q --depth 1 "https://github.com/$TAP_SLUG.git" "$WORK/tap" || fail "clonage de $TAP_SLUG impossible"
CASK="$WORK/tap/Casks/murmure.rb"
[ -f "$CASK" ] || fail "Casks/murmure.rb absent de $TAP_SLUG"
# Jamais en arrière : relancé avec une version plus ancienne, le script
# retirerait aux utilisateurs de Homebrew la dernière version.
CASK_VERSION="$(sed -n 's/^  version "\(.*\)"$/\1/p' "$CASK")"
[ "$(printf '%s\n%s\n' "$CASK_VERSION" "$VERSION" | sort -V | head -1)" = "$CASK_VERSION" ] \
    || fail "le cask est en $CASK_VERSION, plus récente que $VERSION"

sed -i '' -E "s/^  version \"[^\"]+\"$/  version \"$VERSION\"/; s/^  sha256 \"[^\"]+\"$/  sha256 \"$SHA\"/" "$CASK"
grep -q "^  version \"$VERSION\"$" "$CASK" && grep -q "^  sha256 \"$SHA\"$" "$CASK" \
    || fail "version ou sha256 non mis à jour dans Casks/murmure.rb"

if git -C "$WORK/tap" diff --quiet; then
    echo "✓ Cask déjà à jour : murmure $VERSION"
    exit 0
fi
git -C "$WORK/tap" commit -q -am "murmure $VERSION"
git -C "$WORK/tap" push -q origin HEAD || fail "push refusé vers $TAP_SLUG"
echo "✓ Cask poussé : $TAP_SLUG → murmure $VERSION"
