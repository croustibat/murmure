#!/bin/bash
# Construit une version distribuable de Murmure : build Release, signature
# Developer ID, DMG, notarisation Apple, agrafage et flux de mises à jour
# Sparkle (appcast.xml) ; avec un numéro de version, publie la release GitHub.
#
#   ./script/release.sh                  # DMG notarisé et appcast dans dist/, sans publier
#   ./script/release.sh --no-notarize    # DMG signé seulement, pour tester
#   ./script/release.sh 1.2.0            # versionne, notarise et publie
#   ./script/release.sh 1.2.0 --dry-run  # tout préparer, afficher la publication sans la faire
#
#   --no-notarize    DMG signé Developer ID, ni notarisé ni agrafé : Gatekeeper le
#                    refusera sur un autre Mac. Interdit pour une vraie publication.
#   --ed-key-file F  signe l'appcast avec la clé EdDSA du fichier F (format de
#                    « generate_keys -x » ; clé jetable : xcrun swift
#                    script/cle_sparkle.swift nouvelle F) au lieu du compte
#                    « murmure » du trousseau. Une vraie publication exige que sa
#                    clé publique soit SUPublicEDKey.
#   --dry-run        avec X.Y.Z : vérifie, versionne, compile, signe, prépare le
#                    DMG, l'appcast et les notes, affiche le commit, le tag, le push
#                    et la release sans les faire, puis remet VERSION et
#                    app/Info.plist en l'état. Une condition qui bloquerait la
#                    publication est signalée sans arrêter la préparation.
#
# La release vX.Y.Z porte deux fichiers aux noms fixes, Murmure.dmg et
# appcast.xml : https://github.com/croustibat/murmure/releases/latest/download/<fichier>
# reste stable, et les apps installées lisent le second pour se mettre à jour.
#
# Variables : MURMURE_SIGN_IDENTITY (empreinte SHA-1 ou nom, pour choisir parmi
# plusieurs certificats Developer ID), MURMURE_NOTARY_PROFILE (sillage-notary),
# MURMURE_SPARKLE_ACCOUNT (murmure), MURMURE_RELEASE_BUILD_DIR
# (~/Library/Caches/Murmure/ReleaseBuild).
set -euo pipefail

fail() { printf '✗ %s\n' "$1" >&2; exit 1; }
usage() {
    echo "usage : $0 [--no-notarize] [--ed-key-file <clé>] [X.Y.Z [--dry-run]]" >&2
    exit 2
}

PUBLISH_VERSION=""; NOTARIZE=1; DRY_RUN=0; ED_KEY_FILE=""
while [ $# -gt 0 ]; do
    case "$1" in
        --no-notarize) NOTARIZE=0 ;;
        --dry-run) DRY_RUN=1 ;;
        --ed-key-file) [ $# -ge 2 ] || usage; ED_KEY_FILE="$2"; shift ;;
        --ed-key-file=*) ED_KEY_FILE="${1#*=}" ;;
        [0-9]*) [ -z "$PUBLISH_VERSION" ] || usage; PUBLISH_VERSION="$1" ;;
        *) usage ;;
    esac
    shift
done
if [ -n "$PUBLISH_VERSION" ]; then
    # Ni « v » ni suffixe : le tag est vX.Y.Z et Sparkle n'offre que la release
    # « latest », qu'une pré-version ne devient jamais.
    [[ $PUBLISH_VERSION =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || fail "version X.Y.Z attendue : $PUBLISH_VERSION"
    [ "$NOTARIZE" = 1 ] || [ "$DRY_RUN" = 1 ] || fail "--no-notarize : une publication est toujours notarisée (essai : --dry-run)."
else
    [ "$DRY_RUN" = 0 ] || fail "--dry-run accompagne un numéro de version (ex. $0 1.2.0 --dry-run)."
fi
if [ -n "$ED_KEY_FILE" ]; then
    [ -r "$ED_KEY_FILE" ] && [ -f "$ED_KEY_FILE" ] || fail "clé EdDSA illisible : $ED_KEY_FILE"
    ED_KEY_FILE="$(cd "$(dirname "$ED_KEY_FILE")" && pwd)/$(basename "$ED_KEY_FILE")"
fi

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# Comme build_and_run.sh, hors des dossiers synchronisés par iCloud, et à part
# du build d'install.sh, qui inscrit son dossier de données dans Info.plist.
BUILD_ROOT="${MURMURE_RELEASE_BUILD_DIR:-$HOME/Library/Caches/Murmure/ReleaseBuild}"
NOTARY_PROFILE="${MURMURE_NOTARY_PROFILE:-sillage-notary}"
# Compte du trousseau qui porte la clé privée EdDSA, propre à Murmure : une
# fuite ou une cession ne toucherait aucune autre app.
SPARKLE_ACCOUNT="${MURMURE_SPARKLE_ACCOUNT:-murmure}"
REPO="croustibat/murmure"
TEAM_ID="MMJD6CLKNQ"
INFO_PLIST="app/Info.plist"
DIST="$ROOT/dist"
APP="$BUILD_ROOT/Build/Products/Release/Murmure.app"
TAG="v$PUBLISH_VERSION"
cd "$ROOT"

# À blanc, une condition qui bloquerait la publication est notée et la
# préparation continue, pour tout voir en un passage ; sinon, arrêt immédiat.
BLOCKERS=()
bloquer() {
    [ "$DRY_RUN" = 1 ] || fail "$1"
    BLOCKERS+=("$1")
    printf '  ✗ %s\n' "$1" >&2
}

command -v xcodegen >/dev/null || fail "XcodeGen est requis : brew install xcodegen"

# Le certificat de l'équipe qui signe l'app installée : les autorisations Micro
# et Accessibilité suivent l'identifiant et l'équipe. L'empreinte départage deux
# certificats du même nom.
SIGN_LINE="$(security find-identity -v -p codesigning 2>/dev/null \
    | sed -n "s/^ *[0-9]*) \([0-9A-F]\{40\}\) \"\(Developer ID Application: .* ($TEAM_ID)\)\"$/\1 \2/p" \
    | grep -F -- "${MURMURE_SIGN_IDENTITY:-}" | head -1 || true)"
[ -n "$SIGN_LINE" ] || fail "Aucun certificat « Developer ID Application » de l'équipe $TEAM_ID dans le trousseau${MURMURE_SIGN_IDENTITY:+ pour « $MURMURE_SIGN_IDENTITY »}."
SIGN_HASH="${SIGN_LINE%% *}"; SIGN_NAME="${SIGN_LINE#* }"

# Identifiants de notarisation vérifiés avant de compiler, pour échouer vite.
if [ "$NOTARIZE" = 1 ] && ! xcrun notarytool history --keychain-profile "$NOTARY_PROFILE" >/dev/null 2>&1; then
    cat >&2 <<EOF
✗ Identifiants de notarisation introuvables (profil « $NOTARY_PROFILE » du trousseau).
Créer un mot de passe pour app sur https://account.apple.com, puis lancer une fois :

  xcrun notarytool store-credentials $NOTARY_PROFILE --apple-id <apple-id> --team-id $TEAM_ID

Ou relancer avec --no-notarize pour un DMG signé mais non notarisé.
EOF
    exit 1
fi

CURRENT_VERSION="$(tr -d '[:space:]' < VERSION)"
# Lu et réécrit sur place : PlistBuddy réécrirait tout le fichier et perdrait
# ses commentaires.
lire_build() { perl -0ne 'print $1 if m{<key>CFBundleVersion</key>\s*<string>(\d+)</string>}' "$INFO_PLIST"; }
CURRENT_BUILD="$(lire_build)"
[[ $CURRENT_BUILD =~ ^[0-9]+$ ]] || fail "CFBundleVersion illisible dans $INFO_PLIST (entier attendu)."
NEW_BUILD=$((CURRENT_BUILD + 1))

# Une release publiée correspond exactement à un commit de main poussé.
if [ -n "$PUBLISH_VERSION" ]; then
    echo "▸ Vérifications avant de publier $TAG$([ "$DRY_RUN" = 1 ] && echo ' (à blanc)')"
    if ! command -v gh >/dev/null; then
        bloquer "le CLI GitHub est requis : brew install gh"
    elif ! gh auth status >/dev/null 2>&1; then
        bloquer "gh n'est pas connecté à GitHub : gh auth login"
    fi
    BRANCH="$(git branch --show-current)"
    [ "$BRANCH" = main ] || bloquer "publier depuis main (branche actuelle : ${BRANCH:-HEAD détachée})"
    [ -z "$(git status --porcelain)" ] || bloquer "le dépôt a des changements non commités"
    [[ $(git remote get-url origin 2>/dev/null) =~ [:/]$REPO(\.git)?$ ]] \
        || bloquer "origin n'est pas $REPO : le tag et la release doivent viser le même dépôt"
    if git fetch -q origin main --tags; then
        [ "$(git rev-parse HEAD)" = "$(git rev-parse -q --verify origin/main)" ] \
            || bloquer "HEAD n'est pas origin/main : main doit être à jour et poussée"
    else
        bloquer "git fetch origin impossible"
    fi
    git rev-parse -q --verify "refs/tags/$TAG" >/dev/null && bloquer "le tag $TAG existe déjà"
    if command -v gh >/dev/null && gh release view "$TAG" --repo "$REPO" >/dev/null 2>&1; then
        bloquer "la release $TAG existe déjà sur $REPO"
    fi
    LOWEST="$(printf '%s\n%s\n' "$CURRENT_VERSION" "$PUBLISH_VERSION" | sort -V | head -1)"
    [ "$LOWEST" = "$CURRENT_VERSION" ] || bloquer "$PUBLISH_VERSION est inférieure à la version actuelle $CURRENT_VERSION"
    # Sparkle ne compare que CFBundleVersion : un numéro déjà publié ne serait
    # jamais proposé.
    PUBLISHED_BUILD="$(curl -fsSL "https://github.com/$REPO/releases/latest/download/appcast.xml" 2>/dev/null \
        | sed -n 's:.*<sparkle\:version>\([0-9]*\)</sparkle\:version>.*:\1:p' | sort -n | tail -1)" || true
    if [ -n "$PUBLISHED_BUILD" ] && [ "$NEW_BUILD" -le "$PUBLISHED_BUILD" ]; then
        bloquer "build $NEW_BUILD ≤ build publié $PUBLISHED_BUILD : corriger CFBundleVersion dans $INFO_PLIST"
    fi
    echo "  version $CURRENT_VERSION ($CURRENT_BUILD) → $PUBLISH_VERSION ($NEW_BUILD), dernier build publié : ${PUBLISHED_BUILD:-aucun appcast}"
    grep -Eq "^## ${PUBLISH_VERSION//./\\.}( |$)" CHANGELOG.md 2>/dev/null \
        || echo "  ! pas de section « ## $PUBLISH_VERSION » dans CHANGELOG.md : les notes reprendront les sujets des commits" >&2
fi

# Paquets résolus avant de compiler : les outils de Sparkle (même version que
# le framework embarqué) servent à vérifier la clé avant le long build.
echo "▸ Projet et paquets…"
xcodegen generate --quiet
mkdir -p "$BUILD_ROOT" "$DIST"
xcodebuild -resolvePackageDependencies -project Murmure.xcodeproj -scheme Murmure \
    -derivedDataPath "$BUILD_ROOT" >"$BUILD_ROOT/paquets.log" 2>&1 \
    || { tail -20 "$BUILD_ROOT/paquets.log" >&2; fail "résolution des paquets impossible — journal : $BUILD_ROOT/paquets.log"; }
SPARKLE_BIN="$BUILD_ROOT/SourcePackages/artifacts/sparkle/Sparkle/bin"
[ -x "$SPARKLE_BIN/generate_appcast" ] || fail "outils de Sparkle introuvables dans $SPARKLE_BIN"

# Une clé publique qui ne correspond pas à la clé privée rendrait toute mise à
# jour refusée par les apps installées : vérifié avant de signer.
EXPECTED_KEY="$(/usr/libexec/PlistBuddy -c 'Print :SUPublicEDKey' "$INFO_PLIST")"
if [ -n "$ED_KEY_FILE" ]; then
    KEY_PUB="$(xcrun swift script/cle_sparkle.swift publique "$ED_KEY_FILE")" || fail "clé EdDSA illisible : $ED_KEY_FILE"
    SIGNING=(--ed-key-file "$ED_KEY_FILE")
else
    KEY_PUB="$("$SPARKLE_BIN/generate_keys" --account "$SPARKLE_ACCOUNT" -p 2>/dev/null)" \
        || fail "Clé privée Sparkle absente du trousseau (compte « $SPARKLE_ACCOUNT ») : voir CONTRIBUTING.md, « Publier une version »."
    SIGNING=(--account "$SPARKLE_ACCOUNT")
fi
if [ "$KEY_PUB" != "$EXPECTED_KEY" ]; then
    if [ -z "$ED_KEY_FILE" ] || { [ -n "$PUBLISH_VERSION" ] && [ "$DRY_RUN" = 0 ]; }; then
        fail "SUPublicEDKey ($EXPECTED_KEY) ne correspond pas à la clé de signature ($KEY_PUB) : les apps installées refuseraient la mise à jour."
    fi
    echo "  ! clé de test : seule une app dont SUPublicEDKey vaut $KEY_PUB acceptera cet appcast" >&2
fi

STAGING="$(mktemp -d)"
RESTORE=0
cleanup() {
    # Échec, ou essai à blanc : VERSION et Info.plist reviennent à leur état
    # d'avant, octet pour octet.
    if [ "$RESTORE" = 1 ]; then
        cp "$STAGING/VERSION" VERSION
        cp "$STAGING/Info.plist" "$INFO_PLIST"
    fi
    rm -rf "$STAGING"
}
trap cleanup EXIT

# Chaque publication incrémente le build, même si la version affichée ne
# change pas : c'est lui qui déclenche la mise à jour chez les utilisateurs.
if [ -n "$PUBLISH_VERSION" ]; then
    cp VERSION "$STAGING/VERSION"
    cp "$INFO_PLIST" "$STAGING/Info.plist"
    RESTORE=1
    printf '%s\n' "$PUBLISH_VERSION" > VERSION
    perl -0pi -e 's{(<key>CFBundleVersion</key>\s*<string>)\d+(</string>)}{${1}'"$NEW_BUILD"'${2}}' "$INFO_PLIST"
    [ "$(lire_build)" = "$NEW_BUILD" ] && plutil -lint -s "$INFO_PLIST" \
        || fail "CFBundleVersion non mis à jour dans $INFO_PLIST"
fi

echo "▸ Compilation Release…"
scripts/build-whisper.sh
# Bundle refait de zéro : un fichier d'une compilation précédente (un outil
# retiré du projet) ne doit pas partir dans le DMG.
rm -rf "$APP"
if ! xcodebuild -project Murmure.xcodeproj -scheme Murmure -configuration Release \
    -derivedDataPath "$BUILD_ROOT" -destination 'platform=macOS,arch=arm64' \
    CODE_SIGNING_ALLOWED=NO build >"$BUILD_ROOT/release.log" 2>&1; then
    tail -50 "$BUILD_ROOT/release.log" >&2
    fail "compilation impossible — journal : $BUILD_ROOT/release.log"
fi

info() { /usr/libexec/PlistBuddy -c "Print :$1" "$APP/Contents/Info.plist" 2>/dev/null || true; }
VERSION="$(info CFBundleShortVersionString)"
BUILD="$(info CFBundleVersion)"
DMG="$DIST/Murmure-$VERSION.dmg"
if [ -n "$PUBLISH_VERSION" ] && { [ "$VERSION" != "$PUBLISH_VERSION" ] || [ "$BUILD" != "$NEW_BUILD" ]; }; then
    fail "l'app compilée est $VERSION ($BUILD), pas $PUBLISH_VERSION ($NEW_BUILD)"
fi
[ "$(info SUPublicEDKey)" = "$EXPECTED_KEY" ] || fail "SUPublicEDKey de l'app compilée différent de $INFO_PLIST"
# Sans dossier inscrit, l'app prend ~/.local/share/murmure de qui l'ouvre ;
# seul install.sh en inscrit un.
[ -z "$(info MurmureHome)" ] || fail "MurmureHome inscrit dans l'app compilée : $(info MurmureHome)"
for outil in overlay murmure-rec whisper-cli; do
    [ -x "$APP/Contents/Helpers/$outil" ] || fail "Contents/Helpers/$outil manquant dans l'app compilée"
done
SPARKLE_FW="$APP/Contents/Frameworks/Sparkle.framework"
[ -d "$SPARKLE_FW" ] || fail "Sparkle.framework manquant dans l'app compilée"

echo "▸ Signature Developer ID ($SIGN_NAME)…"
xattr -cr "$APP"
script/sign_app.sh "$SIGN_HASH" "$APP" --timestamp

# La notarisation exige, pour chaque exécutable : Developer ID, runtime durci,
# horodatage. Le vérifier ici évite d'attendre un refus d'Apple. Tout fichier
# Mach-O du bundle est contrôlé, pas une liste : un outil ajouté plus tard
# l'est aussi. disable-library-validation n'est permis qu'aux builds ad hoc,
# get-task-allow qu'au débogage.
verifier_signature() {  # fichier Mach-O
    local nom="${1#"$APP/"}" details ents
    details="$(codesign -dvv "$1" 2>&1)" || fail "$nom n'est pas signé"
    grep -q "^Authority=Developer ID Application: .*($TEAM_ID)$" <<<"$details" \
        && grep -q '^Timestamp=' <<<"$details" \
        && grep -q '^CodeDirectory .*flags=.*runtime' <<<"$details" \
        || fail "Signature incomplète pour $nom (Developer ID $TEAM_ID, horodatage et runtime attendus) :
$details"
    ents="$(codesign -d --entitlements - --xml "$1" 2>/dev/null || true)"
    if grep -q -e disable-library-validation -e get-task-allow <<<"$ents"; then
        fail "entitlement interdit dans une version publiée pour $nom : $ents"
    fi
}
COMPONENTS=0
while IFS= read -r -d '' f; do
    [[ $(file -b "$f") == Mach-O* ]] || continue
    verifier_signature "$f"
    COMPONENTS=$((COMPONENTS + 1))
done < <(find "$APP" -type f -print0)
[ ! -e "$SPARKLE_FW/Versions/B/XPCServices" ] || fail "services XPC de Sparkle encore présents"
ENTITLEMENTS="$(codesign -d --entitlements - --xml "$APP" 2>/dev/null)"
for e in com.apple.security.device.audio-input com.apple.security.automation.apple-events; do
    grep -q "$e" <<<"$ENTITLEMENTS" || fail "entitlement $e absent de Murmure.app"
done
codesign --verify --deep --strict "$APP" || fail "codesign --verify --deep --strict refuse Murmure.app"
echo "  ✓ $COMPONENTS exécutables : Developer ID $TEAM_ID, horodatage, runtime durci"

echo "▸ Création du DMG…"
mkdir "$STAGING/dmg"
ditto "$APP" "$STAGING/dmg/Murmure.app"
ln -s /Applications "$STAGING/dmg/Applications"
rm -f "$DMG"
hdiutil create -volname Murmure -srcfolder "$STAGING/dmg" -fs HFS+ -format UDZO -quiet "$DMG"
codesign --force --sign "$SIGN_HASH" --timestamp --identifier dev.croustibat.murmure.dmg "$DMG"
codesign --verify --strict "$DMG"

if [ "$NOTARIZE" = 1 ]; then
    echo "▸ Notarisation Apple (quelques minutes)…"
    xcrun notarytool submit "$DMG" --keychain-profile "$NOTARY_PROFILE" --wait 2>&1 \
        | tee "$STAGING/notarisation.log" || true
    SUBMISSION="$(cat "$STAGING/notarisation.log")"
    if ! grep -q "status: Accepted" <<<"$SUBMISSION"; then
        SUBMISSION_ID="$(sed -n 's/^ *id: \([0-9a-f-]*\)$/\1/p' <<<"$SUBMISSION" | head -1)"
        [ -n "$SUBMISSION_ID" ] && xcrun notarytool log "$SUBMISSION_ID" --keychain-profile "$NOTARY_PROFILE" >&2
        fail "Notarisation refusée."
    fi
    # L'agrafage modifie le DMG : la signature EdDSA de l'appcast vient après.
    xcrun stapler staple "$DMG"
    xcrun stapler validate "$DMG"
    spctl --assess --type open --context context:primary-signature --verbose "$DMG" \
        || fail "Gatekeeper refuse le DMG notarisé"
else
    # Sans notarisation, Gatekeeper doit refuser l'app pour cette seule raison.
    spctl --assess --type execute --verbose "$APP" 2>&1 | sed 's/^/  Gatekeeper : /' || true
fi
# Xcode inscrit l'app compilée (et Updater.app de Sparkle) auprès de
# LaunchServices : plus récente que l'app installée, elle pourrait être
# choisie à sa place pour l'identifiant. Le DMG est fait, elle sort du registre.
find "$APP" -name '*.app' -type d -exec \
    /System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -u {} \; 2>/dev/null || true

# Nouveautés : la section « ## X.Y.Z » de CHANGELOG.md, rédigée pour les
# utilisateurs ; à défaut, les sujets des commits depuis la version précédente.
# Reprises dans la release GitHub et dans la fenêtre de Sparkle.
PREVIOUS_TAG="$(git describe --tags --abbrev=0 --match 'v*' 2>/dev/null || true)"
awk -v version="$VERSION" '/^## / { if (inside) exit; inside = ($2 == version); next } inside' CHANGELOG.md 2>/dev/null \
    | perl -0777 -pe 's/\A\s+|\s+\z//g; $_ .= "\n" if length' > "$STAGING/changes.md" || true
if [ -s "$STAGING/changes.md" ]; then
    echo "▸ Nouveautés reprises de CHANGELOG.md ($VERSION)"
elif [ -n "$PREVIOUS_TAG" ]; then
    echo "▸ Nouveautés : sujets des commits depuis $PREVIOUS_TAG"
    git log --no-merges --format='- %s' "$PREVIOUS_TAG..HEAD" | grep -v '^- release:' > "$STAGING/changes.md" || true
else
    echo "Nouvelle version de Murmure." > "$STAGING/changes.md"
fi

# Appcast à une seule entrée : Sparkle ne regarde que la version la plus
# récente. generate_appcast lit dans le DMG version, build, macOS minimum et
# architecture, et signe l'archive.
echo "▸ appcast.xml…"
UPDATES="$STAGING/updates"
mkdir "$UPDATES"
cp "$DMG" "$UPDATES/Murmure.dmg"
{ echo "## Murmure $VERSION"; echo; cat "$STAGING/changes.md"; } > "$UPDATES/Murmure.md"
DOWNLOAD_URL="https://github.com/$REPO/releases/download/v$VERSION/Murmure.dmg"
rm -f "$DIST/appcast.xml"
"$SPARKLE_BIN/generate_appcast" "${SIGNING[@]}" \
    --download-url-prefix "${DOWNLOAD_URL%Murmure.dmg}" \
    --embed-release-notes --link "https://github.com/$REPO" --maximum-deltas 0 \
    -o "$DIST/appcast.xml" "$UPDATES" >"$STAGING/appcast.log" 2>&1 \
    || { cat "$STAGING/appcast.log" >&2; fail "generate_appcast a échoué"; }
# generate_appcast ne signe qu'avec la clé de l'app (sinon il avertit et laisse
# l'entrée sans signature) : une clé de test signe le même DMG à part.
if [ "$KEY_PUB" != "$EXPECTED_KEY" ]; then
    SIGNATURE="$("$SPARKLE_BIN/sign_update" --ed-key-file "$ED_KEY_FILE" -p "$DMG")" \
        || fail "sign_update n'a pas pu signer le DMG avec $ED_KEY_FILE"
    SIGNATURE="$SIGNATURE" perl -0pi -e \
        's{(<enclosure\b[^>]*?)\s*/>}{$1 sparkle:edSignature="$ENV{SIGNATURE}"/>}' "$DIST/appcast.xml"
fi

# Contrôle de ce que liront les apps installées. La signature est vérifiée à
# part, comme le fera Sparkle, avec la clé publique et le DMG final.
attribut() { perl -0ne 'print $1 if /<enclosure\b[^>]*\b'"$1"'="([^"]*)"/' "$DIST/appcast.xml"; }
element() { perl -0ne 'print $1 if m{<'"$1"'>([^<]*)</'"$1"'>}' "$DIST/appcast.xml"; }
[ "$(grep -c '<item>' "$DIST/appcast.xml")" = 1 ] || fail "appcast.xml doit avoir une seule entrée"
[ "$(element sparkle:version)" = "$BUILD" ] || fail "appcast.xml : sparkle:version $(element sparkle:version), $BUILD attendu"
[ "$(element sparkle:shortVersionString)" = "$VERSION" ] || fail "appcast.xml : sparkle:shortVersionString $(element sparkle:shortVersionString), $VERSION attendu"
[ "$(element sparkle:minimumSystemVersion)" = 14.0 ] || fail "appcast.xml : macOS minimum $(element sparkle:minimumSystemVersion), 14.0 attendu"
[ "$(attribut url)" = "$DOWNLOAD_URL" ] || fail "appcast.xml : adresse $(attribut url), $DOWNLOAD_URL attendue"
[ "$(attribut length)" = "$(stat -f %z "$DMG")" ] || fail "appcast.xml : taille $(attribut length) ≠ $(stat -f %z "$DMG") octets"
SIGNATURE="$(attribut sparkle:edSignature)"
[ -n "$SIGNATURE" ] || fail "appcast.xml n'est pas signé"
xcrun swift script/cle_sparkle.swift verifier "$KEY_PUB" "$SIGNATURE" "$DMG" >/dev/null \
    || fail "la signature EdDSA de appcast.xml ne correspond pas au DMG"
echo "  ✓ $VERSION ($BUILD), macOS $(element sparkle:minimumSystemVersion)+ $(element sparkle:hardwareRequirements), signature EdDSA vérifiée ($KEY_PUB)"

# Noms fixes des fichiers de la release : liens « latest » stables.
cp "$DMG" "$DIST/Murmure.dmg"
{
    echo "## Nouveautés"
    echo
    cat "$STAGING/changes.md"
    echo
    echo "## Installation"
    echo
    echo "Ouvrez \`Murmure.dmg\` et glissez Murmure dans Applications. Au premier lancement, Murmure télécharge son modèle de transcription (550 Mo, une seule fois) s'il n'est pas déjà sur le Mac."
    echo
    echo "Mac avec puce Apple, macOS 14 ou ultérieur. App signée et notarisée par Apple : elle s'ouvre sans avertissement. Elle se met ensuite à jour d'elle-même (menu « Rechercher les mises à jour… »)."
    echo
    echo "Pour la compiler vous-même : \`git clone https://github.com/$REPO.git && cd murmure && ./install.sh\` (Xcode requis)."
} > "$DIST/notes.md"

if [ -z "$PUBLISH_VERSION" ]; then
    if [ "$NOTARIZE" = 1 ]; then
        echo "✓ $DMG et dist/appcast.xml ($VERSION, build $BUILD) — notarisés, prêts à publier."
    else
        echo "✓ $DMG et dist/appcast.xml ($VERSION, build $BUILD) — non notarisés : Gatekeeper les bloquera sur un autre Mac."
    fi
    exit 0
fi

# Publication : commit de version, tag, push atomique, puis la release sur ce
# tag. Le tag est poussé avant la release : créée d'abord, elle poserait le
# tag sur le commit d'avant, et le push du nôtre serait refusé.
publier() {
    if [ "$DRY_RUN" = 1 ]; then
        printf '  [à blanc]'; printf ' %q' "$@"; echo
    else
        "$@"
    fi
}
echo "▸ Publication de $TAG sur $REPO$([ "$DRY_RUN" = 1 ] && echo ' (à blanc : rien ne sera fait)')"
if [ "$DRY_RUN" = 1 ]; then
    echo "  Commit « release: $TAG » :"
    git --no-pager diff --no-color -- VERSION "$INFO_PLIST" | sed 's/^/    /'
fi
publier git commit -q -m "release: $TAG" -- VERSION "$INFO_PLIST"
[ "$DRY_RUN" = 1 ] || RESTORE=0
publier git tag -a "$TAG" -m "Murmure $VERSION"
if ! publier git push -q --atomic origin main "$TAG"; then
    fail "push refusé : rien n'est publié. Pour annuler localement : git tag -d $TAG && git reset --hard origin/main"
fi
RELEASE=(gh release create "$TAG" "$DIST/Murmure.dmg" "$DIST/appcast.xml" --repo "$REPO"
    --title "Murmure $VERSION" --notes-file "$DIST/notes.md" --latest --verify-tag)
if ! publier "${RELEASE[@]}"; then
    fail "$TAG est poussé, mais la release n'a pas été créée. Les fichiers sont dans dist/ ; relancer :
  $(printf '%q ' "${RELEASE[@]}")"
fi

if [ "$DRY_RUN" = 1 ]; then
    echo "  [à blanc] contrôle : https://github.com/$REPO/releases/latest/download/appcast.xml annonce le build $BUILD"
    echo "  [à blanc] cask Homebrew proposé : ./script/update-cask.sh $VERSION"
    if [ ${#BLOCKERS[@]} -gt 0 ]; then
        echo "✗ La vraie publication serait refusée :" >&2
        printf '  - %s\n' "${BLOCKERS[@]}" >&2
        exit 1
    fi
    echo "✓ À blanc : rien n'a été publié ; VERSION et $INFO_PLIST sont remis en l'état. DMG et appcast dans dist/."
    exit 0
fi

# Le lien stable que lisent les apps installées doit déjà annoncer ce build.
if curl -fsSL "https://github.com/$REPO/releases/latest/download/appcast.xml" 2>/dev/null \
    | grep -q "<sparkle:version>$BUILD</sparkle:version>"; then
    echo "  ✓ releases/latest/download/appcast.xml annonce le build $BUILD"
else
    echo "  ! releases/latest/download/appcast.xml n'annonce pas encore le build $BUILD : vérifier la release" >&2
fi
echo "✓ Murmure $VERSION publiée : https://github.com/$REPO/releases/tag/$TAG"
echo "  Lien stable  : https://github.com/$REPO/releases/latest/download/Murmure.dmg"
echo "  Flux Sparkle : https://github.com/$REPO/releases/latest/download/appcast.xml"

# Cask Homebrew : proposé une fois la release en ligne. Un échec ne touche pas
# la publication, déjà faite : la commande affichée se lance à part.
CASK_CMD="./script/update-cask.sh $VERSION"
if [ -t 0 ]; then
    printf 'Mettre à jour le cask Homebrew (croustibat/homebrew-tap) ? [O/n] '
    read -r REPONSE || REPONSE=n
    case "$REPONSE" in
        [nN]*) echo "  Plus tard : $CASK_CMD" ;;
        *) script/update-cask.sh "$VERSION" || echo "  ! cask non mis à jour ; relancer : $CASK_CMD" >&2 ;;
    esac
else
    echo "  Cask Homebrew : $CASK_CMD"
fi
