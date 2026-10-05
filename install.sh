#!/bin/bash
# Murmure — installation.
set -euo pipefail

MURMURE_HOME="${MURMURE_HOME:-$HOME/.local/share/murmure}"
APP_DIR="${MURMURE_APP_DIR:-/Applications}"
# Emplacement des versions ≤ 1.1.0, retiré lors d'une installation par défaut.
OLD_APP="$HOME/Applications/Murmure.app"
APP="$APP_DIR/Murmure.app"
KARABINER_DIR="${MURMURE_KARABINER_DIR:-$HOME/.config/karabiner}"
SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# Nom, révision, empreinte et taille du modèle : app/modele.conf, que
# Murmure.app lit aussi pour le télécharger elle-même.
modele() { sed -n "s/^$1=//p" "$SRC/app/modele.conf" | tail -1 | tr -d '[:space:]'; }
MODEL_NAME="${MURMURE_MODEL_NAME:-$(modele MODEL_NAME)}"
MODEL_URL="${MURMURE_MODEL_URL:-$(modele MODEL_REPO)/$(modele MODEL_REV)/$MODEL_NAME}"
if [ "$MODEL_NAME" = "$(modele MODEL_NAME)" ]; then
  MODEL_SHA256="${MURMURE_MODEL_SHA256:-$(modele MODEL_SHA256)}"
  MODEL_SIZE="${MURMURE_MODEL_SIZE:-$(modele MODEL_SIZE)}"
else
  MODEL_SHA256="${MURMURE_MODEL_SHA256:-}"
  MODEL_SIZE="${MURMURE_MODEL_SIZE:-}"
fi

VERIFY=0
for arg in "$@"; do
  case "$arg" in
    --verify) VERIFY=1 ;;   # recalcule le SHA-256 d'un modèle déjà présent
    *) echo "usage : $0 [--verify]" >&2; exit 2 ;;
  esac
done

bold=$'\033[1m'; green=$'\033[32m'; yellow=$'\033[33m'; red=$'\033[31m'; off=$'\033[0m'
step() { printf '%s==>%s %s\n' "$bold" "$off" "$1"; }
ok()   { printf '    %s✓%s %s\n' "$green" "$off" "$1"; }
warn() { printf '    %s!%s %s\n' "$yellow" "$off" "$1"; }
fail() { printf '%s✗%s %s\n' "$red" "$off" "$1" >&2; exit 1; }

# Bilan affiché en fin d'installation : ce qui a été remplacé, ce qui est intact.
CHANGES=()
note() { CHANGES+=("$1"); }

fsize()  { stat -f %z "$1" 2>/dev/null || echo 0; }
sha256() { shasum -a 256 "$1" | cut -d' ' -f1; }

[ "$(uname -s)" = "Darwin" ] || fail "Murmure ne fonctionne que sur macOS."

step "Vérification des dépendances"
command -v brew >/dev/null || fail "Homebrew est requis : https://brew.sh"
# whisper-cli est compilé depuis whisper.cpp (scripts/build-whisper.sh) et
# embarqué dans Murmure.app : il ne faut que CMake, trouvé comme le fait le script.
if [ -z "${CMAKE:-}" ] && ! command -v cmake >/dev/null && [ ! -x /Applications/CMake.app/Contents/bin/cmake ]; then
  step "Installation de CMake"; brew install cmake
fi
ok "CMake présent"
# Murmure.app se compile avec Xcode, à partir du projet que XcodeGen génère
# depuis project.yml.
xcodebuild -version >/dev/null 2>&1 \
  || fail "Xcode est requis pour compiler Murmure.app : installez-le (App Store), ouvrez-le une fois, puis sudo xcode-select -s /Applications/Xcode.app"
command -v xcodegen >/dev/null || { step "Installation de XcodeGen"; brew install xcodegen; }
command -v xcodegen >/dev/null || fail "xcodegen introuvable après installation."
ok "Xcode et XcodeGen présents"

step "Installation des fichiers dans $MURMURE_HOME"
# Données seulement : le moteur (murmure.sh, corriger.pl) est dans Murmure.app.
mkdir -p "$MURMURE_HOME/models"
for f in vocabulaire corrections; do
  if [ -f "$MURMURE_HOME/$f.txt" ]; then
    warn "$f.txt existe déjà — conservé (nouvelle version dans $f.txt.dist)"
    install -m 644 "$SRC/config/$f.txt" "$MURMURE_HOME/$f.txt.dist"
  else
    install -m 644 "$SRC/config/$f.txt" "$MURMURE_HOME/$f.txt"
  fi
done
# Réglages : déposés une seule fois, jamais écrasés (édités à la main ou par
# l'app). Toutes les clés y figurent en commentaire, valeurs par défaut.
if [ -f "$MURMURE_HOME/config" ]; then
  note "config : conservé"
else
  install -m 644 "$SRC/config/config.exemple" "$MURMURE_HOME/config"
  note "config : installé"
fi
ok "configuration en place"

# Téléchargement vers .part avec reprise (curl -C -), vérification SHA-256, puis
# mv atomique : un fichier tronqué ne peut plus passer pour un modèle valide.
step "Modèle Whisper ($MODEL_NAME)"
MODEL="$MURMURE_HOME/models/$MODEL_NAME"
PART="$MODEL.part"
if [ -f "$MODEL" ]; then
  if [ -n "$MODEL_SIZE" ] && [ "$(fsize "$MODEL")" != "$MODEL_SIZE" ]; then
    warn "taille inattendue ($(fsize "$MODEL") octets au lieu de $MODEL_SIZE) — nouveau téléchargement"
    if [ "$(fsize "$MODEL")" -lt "$MODEL_SIZE" ] && [ ! -f "$PART" ]; then
      mv "$MODEL" "$PART"   # tronqué : on reprend là où il s'est arrêté
    else
      rm -f "$MODEL"
    fi
  elif [ ! -s "$MODEL" ]; then
    rm -f "$MODEL"
  elif [ "$VERIFY" = 1 ] && [ -n "$MODEL_SHA256" ]; then
    echo "    vérification du SHA-256…"
    if [ "$(sha256 "$MODEL")" = "$MODEL_SHA256" ]; then
      ok "empreinte vérifiée"
    else
      warn "empreinte incorrecte — modèle corrompu, nouveau téléchargement"
      rm -f "$MODEL"
    fi
  fi
fi
if [ -f "$MODEL" ]; then
  ok "déjà présent"
  note "modèle : inchangé"
else
  for attempt in 1 2; do
    if [ -n "$MODEL_SIZE" ] && [ "$(fsize "$PART")" -ge "$MODEL_SIZE" ]; then
      :   # déjà complet : curl -C - échouerait sur une plage vide
    elif [ -s "$PART" ]; then
      echo "    reprise du téléchargement ($(( $(fsize "$PART") / 1048576 )) Mo déjà reçus)…"
      curl -L --fail --progress-bar -C - -o "$PART" "$MODEL_URL" \
        || fail "téléchargement interrompu — relancez ./install.sh pour reprendre"
    else
      echo "    téléchargement (~550 Mo, une seule fois)…"
      curl -L --fail --progress-bar -o "$PART" "$MODEL_URL" \
        || fail "téléchargement interrompu — relancez ./install.sh pour reprendre"
    fi
    if [ -z "$MODEL_SHA256" ]; then
      warn "aucune empreinte connue pour $MODEL_NAME — intégrité non vérifiée"
      break
    fi
    [ "$(sha256 "$PART")" = "$MODEL_SHA256" ] && break
    rm -f "$PART"
    [ "$attempt" = 2 ] && fail "empreinte SHA-256 incorrecte après téléchargement — réessayez plus tard"
    warn "empreinte SHA-256 incorrecte — nouveau téléchargement complet"
  done
  mv -f "$PART" "$MODEL"
  ok "modèle téléchargé"
  note "modèle : téléchargé"
fi

# Le bundle .app est indispensable : un script nu n'a pas d'identité TCC, macOS ne
# propose jamais l'autorisation micro et livre un flux muet à la place.
# Les autorisations Micro et Accessibilité suivent la signature : on ne recrée ni
# ne re-signe le bundle que si son contenu ou l'identité de signature change.
# Info.plist porte l'empreinte de tout ce qui entre dans le bundle et de la
# version de Xcode : l'app n'est recompilée que si cette empreinte change.
# Le moteur en fait partie : modifier murmure.sh recompile l'app.
step "Création de Murmure.app"
VERSION="$(tr -d '[:space:]' < "$SRC/VERSION")"
# Ce que project.yml compile, copie ou signe dans le bundle : un nouvel outil
# de Contents/Helpers y ajoute ses sources.
APP_SOURCES=(project.yml VERSION app src/app src/overlay.swift src/rec script/sign_app.sh src/murmure.sh src/corriger.pl config scripts/build-whisper.sh scripts/whisper.version)
APP_SUM="$( { (cd "$SRC" && find "${APP_SOURCES[@]}" -type f ! -name .DS_Store -print0 \
  | LC_ALL=C sort -z | xargs -0 shasum -a 256); xcodebuild -version; } | shasum -a 256 | cut -d' ' -f1)"
# Hors des dossiers synchronisés par iCloud, comme script/build_and_run.sh.
BUILD_DIR="${MURMURE_BUILD_DIR:-$HOME/Library/Caches/Murmure/Build}"
info_of() {  # app clé → valeur dans Info.plist, vide si absente
  /usr/libexec/PlistBuddy -c "Print :$2" "$1/Contents/Info.plist" 2>/dev/null || true
}

# Identité de signature. Signée par un certificat, l'app est reconnue par macOS
# à son identifiant et à son équipe : les autorisations survivent aux
# recompilations. Signée ad hoc (sans certificat), elle l'est à l'empreinte de
# son binaire : chaque recompilation fait perdre l'Accessibilité.
# MURMURE_SIGN_IDENTITY choisit le certificat (nom ou empreinte SHA-1) ;
# « - » force la signature ad hoc. Par défaut : Developer ID, puis Apple
# Development, sinon ad hoc.
IDENTITIES="$(security find-identity -v -p codesigning 2>/dev/null || true)"
identity_line() {  # motif → « empreinte nom » de la première identité valide
  printf '%s\n' "$IDENTITIES" | grep -F -- "$1" \
    | sed -n 's/^ *[0-9]*) \([0-9A-F]\{40\}\) "\(.*\)"$/\1 \2/p' | head -1 || true
}
if [ "${MURMURE_SIGN_IDENTITY:-}" = "-" ]; then
  SIGN_LINE=""
elif [ -n "${MURMURE_SIGN_IDENTITY:-}" ]; then
  SIGN_LINE="$(identity_line "$MURMURE_SIGN_IDENTITY")"
  [ -n "$SIGN_LINE" ] || fail "identité de signature introuvable : $MURMURE_SIGN_IDENTITY"
else
  SIGN_LINE="$(identity_line '"Developer ID Application: ')"
  [ -n "$SIGN_LINE" ] || SIGN_LINE="$(identity_line '"Apple Development: ')"
fi
# Empreinte pour codesign (deux certificats peuvent porter le même nom), nom
# pour comparer avec celui de l'app installée ; « - » : ad hoc.
SIGN_HASH="${SIGN_LINE%% *}"; SIGN_NAME="${SIGN_LINE#* }"
[ -n "$SIGN_LINE" ] || { SIGN_HASH="-"; SIGN_NAME="-"; }

signer_of() {  # app → nom du certificat, ou « - » si ad hoc
  local who
  who="$(codesign -dvv "$1" 2>&1 | sed -n 's/^Authority=//p' | head -1)"
  echo "${who:--}"
}
# Signe l'app et ses outils (runtime durci, entitlements) ; un certificat
# inutilisable (trousseau verrouillé, en SSH par exemple) laisse une signature
# ad hoc plutôt qu'une app non signée.
sign_app() {
  if [ "$SIGN_HASH" != "-" ] \
     && "$SRC/script/sign_app.sh" "$SIGN_HASH" "$APP" --timestamp=none >/dev/null 2>&1; then
    return
  fi
  if [ "$SIGN_HASH" != "-" ]; then
    warn "signature avec « $SIGN_NAME » impossible — signature ad hoc"
    SIGN_HASH="-"; SIGN_NAME="-"
  fi
  "$SRC/script/sign_app.sh" - "$APP" >/dev/null 2>&1 || warn "signature ad hoc impossible"
}
# Autorisations à redonner : l'identité de l'app a changé, ou elle est ad hoc
# (nouveau binaire, nouvelle empreinte).
PREV_SIGNER=""
[ -d "$APP" ] && PREV_SIGNER="$(signer_of "$APP")"
identity_changed() { [ -n "$PREV_SIGNER" ] && { [ "$SIGN_NAME" = "-" ] || [ "$PREV_SIGNER" != "$SIGN_NAME" ]; }; }
signed_as() { if [ "$SIGN_NAME" = "-" ]; then echo "ad hoc"; else echo "$SIGN_NAME"; fi; }

# Même contenu : mêmes sources, compilées pour le même dossier d'installation.
same_content() {
  [ -d "$APP" ] && [ -x "$APP/Contents/MacOS/Murmure" ] \
    && [ "$(info_of "$APP" MurmureSourceSum)" = "$APP_SUM" ] \
    && [ "$(info_of "$APP" MurmureHome)" = "$MURMURE_HOME" ]
}

if same_content \
   && codesign --verify "$APP" >/dev/null 2>&1 \
   && [ "$PREV_SIGNER" = "$SIGN_NAME" ]; then
  ok "$APP inchangée — signature et autorisations conservées"
  note "Murmure.app : inchangée"
elif same_content; then
  # Même contenu, autre identité : re-signer suffit.
  pkill -f "$APP/Contents/MacOS/Murmure" 2>/dev/null || true
  sign_app
  if identity_changed; then
    note "Murmure.app : re-signée ($(signed_as)) — autorisation Accessibilité à supprimer puis rajouter (voir plus bas)"
    RECREATED=1
  else
    note "Murmure.app : re-signée ($(signed_as))"
  fi
  ok "$APP signée ($(signed_as))"
else
  # Compilée sans signer : sign_app signe ensuite l'app installée, outils compris.
  mkdir -p "$BUILD_DIR"
  BUILD_LOG="$BUILD_DIR/install.log"
  (cd "$SRC" && xcodegen generate --quiet) || fail "génération du projet Xcode impossible (project.yml)"
  # whisper-cli, compilé à part (CMake), est copié dans le bundle par
  # xcodebuild : quelques secondes s'il est déjà à jour.
  "$SRC/scripts/build-whisper.sh" || fail "compilation de whisper-cli impossible — journal : $SRC/build/whisper/compilation.log"
  xcodebuild -project "$SRC/Murmure.xcodeproj" -scheme Murmure -configuration Release \
      -derivedDataPath "$BUILD_DIR" -destination 'platform=macOS,arch=arm64' \
      CODE_SIGNING_ALLOWED=NO MURMURE_INFO_HOME="$MURMURE_HOME" MURMURE_INFO_SOURCE_SUM="$APP_SUM" \
      build >"$BUILD_LOG" 2>&1 \
    || { tail -20 "$BUILD_LOG" >&2; fail "compilation de Murmure.app impossible — journal : $BUILD_LOG"; }
  pkill -f "$APP/Contents/MacOS/Murmure" 2>/dev/null || true   # ancienne version
  pkill -f "$APP/Contents/Helpers/overlay" 2>/dev/null || true   # sa pastille
  # Migration : l'app vivait dans ~/Applications. Seulement pour une
  # installation par défaut — jamais quand MURMURE_APP_DIR vise un autre dossier.
  if [ -z "${MURMURE_APP_DIR:-}" ] && [ "$OLD_APP" != "$APP" ] && [ -d "$OLD_APP" ]; then
    "$OLD_APP/Contents/MacOS/Murmure" --demarrage non >/dev/null 2>&1 || true
    pkill -f "$OLD_APP/Contents/MacOS/Murmure" 2>/dev/null || true
    rm -rf "$OLD_APP"
    note "ancienne copie $OLD_APP : retirée (Murmure est maintenant dans $APP_DIR)"
  fi
  mkdir -p "$APP_DIR"
  rm -rf "$APP"
  ditto "$BUILD_DIR/Build/Products/Release/Murmure.app" "$APP"
  sign_app
  if [ -z "$PREV_SIGNER" ]; then
    note "Murmure.app : créée ($(signed_as))"
  elif identity_changed; then
    note "Murmure.app : recréée ($(signed_as)) — autorisation Accessibilité à supprimer puis rajouter (voir plus bas)"
    RECREATED=1
  else
    note "Murmure.app : recréée ($(signed_as)) — autorisations conservées"
  fi
  ok "$APP ($VERSION, $(signed_as))"
fi

# Le moteur et la pastille sont dans Murmure.app : les copies des versions
# ≤ 1.1.0 restent dans $MURMURE_HOME jusqu'à la première dictée réussie, qui
# les retire (revenir à l'ancienne app marche encore d'ici là).
if [ -e "$MURMURE_HOME/murmure.sh" ] || [ -e "$MURMURE_HOME/overlay" ]; then
  note "ancien moteur de $MURMURE_HOME : retiré à la première dictée (il est dans Murmure.app)"
fi

# Règles actives de karabiner.json qui lancent Murmure (« murmure|profil|règle|
# commande ») ou qui prennent ⌘⇧E pour autre chose (« conflit|… »), une par ligne.
# Lecture seule : karabiner.json n'est jamais modifié.
karabiner_rules() {  # karabiner.json
  osascript -l JavaScript -e '
    function run(argv) {
      const raw = $.NSString.stringWithContentsOfFileEncodingError(argv[0], $.NSUTF8StringEncoding, null);
      if (!raw || raw.isNil()) return "";
      let cfg;
      try { cfg = JSON.parse(raw.js); } catch (e) { return ""; }
      const has = (mods, k) => mods.some(m => m === k || m === "left_" + k || m === "right_" + k);
      const out = [];
      for (const p of cfg.profiles || []) {
        for (const r of (p.complex_modifications || {}).rules || []) {
          if (r.enabled === false) continue;
          // Une ligne par règle (⌘⇧E et Échap de la règle Murmure : une seule)
          let kind = "", cmd = "";
          for (const m of r.manipulators || []) {
            const f = m.from || {};
            const mods = (f.modifiers || {}).mandatory || [];
            const cmds = (m.to || []).map(t => t.shell_command).filter(Boolean);
            if (cmds.some(c => c.includes("Murmure.app"))) {
              kind = "murmure"; cmd = cmds.join(" ; "); break;
            }
            if (f.key_code === "e" && has(mods, "command") && has(mods, "shift")) {
              kind = "conflit"; cmd = cmds.join(" ; ") || JSON.stringify(m.to || []);
            }
          }
          if (kind) out.push([kind, p.name || "?", r.description || "(sans description)", cmd].join("|"));
        }
      }
      return out.join("\n");
    }' "$1" 2>/dev/null || true
}

# L'app gère elle-même le raccourci : Karabiner n'est plus nécessaire. Une règle
# Murmure encore active ferait double emploi — un appui démarrerait puis
# arrêterait aussitôt la dictée.
step "Raccourci clavier"
SHORTCUT="$(sed -n 's/^[[:space:]]*MURMURE_SHORTCUT[[:space:]]*=[[:space:]]*//p' "$MURMURE_HOME/config" 2>/dev/null | tail -1 | tr -d "\"'")"
SHORTCUT="${SHORTCUT:-cmd+shift+e}"
ok "géré par Murmure.app : $SHORTCUT"
KB_FILE="$KARABINER_DIR/assets/complex_modifications/murmure.json"
if [ -f "$KB_FILE" ]; then
  rm -f "$KB_FILE"
  ok "ancienne règle Karabiner retirée de la liste « Add rule »"
fi
if [ -f "$KARABINER_DIR/karabiner.json" ]; then
  KB_MINE=0; KB_CONFLICT=0
  while IFS='|' read -r kind profile desc cmd; do
    [ -n "$kind" ] || continue
    [ "$kind" = murmure ] && KB_MINE=1 || KB_CONFLICT=1
    warn "règle Karabiner active à supprimer :"
    echo "      profil   : $profile"
    echo "      règle    : $desc"
    echo "      commande : $cmd"
  done < <(karabiner_rules "$KARABINER_DIR/karabiner.json")
  if [ "$KB_MINE" = 1 ]; then
    echo "      Cette règle lance Murmure en plus du raccourci de l'app : un appui"
    echo "      démarrerait puis arrêterait aussitôt la dictée."
  fi
  if [ "$KB_CONFLICT" = 1 ]; then
    echo "      Une règle ⌘⇧E qui ne lance pas Murmure intercepte le raccourci."
  fi
  if [ "$KB_MINE" = 1 ] || [ "$KB_CONFLICT" = 1 ]; then
    echo "      Supprimez-la dans Karabiner > Complex Modifications (Remove)."
    echo "      $KARABINER_DIR/karabiner.json n'est pas modifié automatiquement."
    note "raccourci : règle Karabiner à supprimer (voir plus haut)"
  fi
fi

# Relance : l'app relit le raccourci et prend la nouvelle version.
step "Lancement de Murmure"
pkill -f "$APP/Contents/MacOS/Murmure" 2>/dev/null || true
for _ in $(seq 1 20); do pgrep -f "$APP/Contents/MacOS/Murmure" >/dev/null || break; sleep 0.1; done
# Variables de test transmises à l'app (dossier d'état, autorisations sans invite).
if open ${MURMURE_STATE_DIR:+--env "MURMURE_STATE_DIR=$MURMURE_STATE_DIR"} \
        ${MURMURE_AX_NO_PROMPT:+--env "MURMURE_AX_NO_PROMPT=$MURMURE_AX_NO_PROMPT"} "$APP"; then
  ok "Murmure est dans la barre des menus"
else
  warn "lancement impossible — ouvrez $APP"
fi

# Nouvelle identité : l'ancienne entrée Accessibilité reste affichée cochée
# mais ne vaut plus, et la recocher ne suffit pas.
if [ "$SIGN_NAME" = "-" ]; then
  SIGN_HINT="
Signature ad hoc (aucun certificat de développeur) : chaque recompilation de
Murmure.app obligera à refaire cette manipulation."
else
  SIGN_HINT="
Murmure.app est désormais signée par « $SIGN_NAME » : les prochaines
mises à jour conserveront les autorisations."
fi
if [ "${RECREATED:-0}" = 1 ]; then
  PERMISSIONS="\
Murmure.app a changé d'identité : macOS ne reconnaît plus ses autorisations.

  1. ${bold}Accessibilité${off} — Réglages > Confidentialité et sécurité > Accessibilité :
     l'entrée Murmure reste cochée mais ne vaut plus. Sélectionnez-la,
     ${bold}supprimez-la (–)${off}, puis rajoutez-la (+, ⌘⇧G et coller : $APP)
     et cochez-la.
  2. ${bold}Micro${off} — si macOS le redemande à la première dictée : Autoriser.

Tant que l'Accessibilité manque, le menu de Murmure le signale en tête.
$SIGN_HINT"
else
  PERMISSIONS="\
Il reste deux autorisations à accorder, au ${bold}premier usage${off} :

  1. ${bold}Micro${off} — un dialogue « Murmure » apparaîtra : Autoriser.
  2. ${bold}Accessibilité${off} — pour que le texte se colle tout seul.
     Réglages > Confidentialité et sécurité > Accessibilité > +
     puis ⌘⇧G et coller : $APP"
fi

cat <<FIN

${bold}Installation terminée.${off}

$(printf '  - %s\n' "${CHANGES[@]}")

$PERMISSIONS

Sans l'Accessibilité, le texte va dans le presse-papiers et vous faites ⌘V.

Essai : $SHORTCUT, parlez, puis à nouveau — ou gardez la combinaison
enfoncée le temps de parler. Échap pendant l'écoute annule.
L'icône de Murmure dans la barre des menus donne l'état, le journal et le
lancement au démarrage.
Journal : /tmp/murmure-$(id -u)/murmure.log
FIN
