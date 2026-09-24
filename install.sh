#!/bin/bash
# Murmure — installation.
set -euo pipefail

MURMURE_HOME="${MURMURE_HOME:-$HOME/.local/share/murmure}"
APP_DIR="${MURMURE_APP_DIR:-/Applications}"
# Emplacement des versions ≤ 1.1.0, retiré lors d'une installation par défaut.
OLD_APP="$HOME/Applications/Murmure.app"
APP="$APP_DIR/Murmure.app"
KARABINER_DIR="${MURMURE_KARABINER_DIR:-$HOME/.config/karabiner}"
MODEL_NAME="${MURMURE_MODEL_NAME:-ggml-large-v3-turbo-q5_0.bin}"
# URL figée sur une révision précise : le hash ci-dessous reste valable même si
# le dépôt Hugging Face publie une nouvelle version du fichier.
MODEL_REV="5359861c739e955e79d9a303bcbc70fb988958b1"
MODEL_URL="${MURMURE_MODEL_URL:-https://huggingface.co/ggerganov/whisper.cpp/resolve/$MODEL_REV/$MODEL_NAME}"
if [ "$MODEL_NAME" = "ggml-large-v3-turbo-q5_0.bin" ]; then
  MODEL_SHA256="${MURMURE_MODEL_SHA256:-394221709cd5ad1f40c46e6031ca61bce88931e6e088c188294c6d5a55ffa7e2}"
  MODEL_SIZE="${MURMURE_MODEL_SIZE:-574041195}"
else
  MODEL_SHA256="${MURMURE_MODEL_SHA256:-}"
  MODEL_SIZE="${MURMURE_MODEL_SIZE:-}"
fi
SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

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

# Copie seulement si le contenu diffère, et le consigne dans le bilan.
install_if_changed() {  # mode source destination libellé
  if [ -f "$3" ] && cmp -s "$2" "$3"; then
    note "$4 : inchangé"
  else
    if [ -f "$3" ]; then note "$4 : mis à jour"; else note "$4 : installé"; fi
    install -m "$1" "$2" "$3"
  fi
}

fsize()  { stat -f %z "$1" 2>/dev/null || echo 0; }
sha256() { shasum -a 256 "$1" | cut -d' ' -f1; }

[ "$(uname -s)" = "Darwin" ] || fail "Murmure ne fonctionne que sur macOS."

step "Vérification des dépendances"
command -v brew >/dev/null || fail "Homebrew est requis : https://brew.sh"
command -v ffmpeg  >/dev/null || { step "Installation de ffmpeg";  brew install ffmpeg; }
command -v whisper-cli >/dev/null || { step "Installation de whisper.cpp"; brew install whisper-cpp; }
command -v ffmpeg >/dev/null     || fail "ffmpeg introuvable après installation."
command -v whisper-cli >/dev/null || fail "whisper-cli introuvable après installation."
ok "ffmpeg et whisper-cli présents"
command -v swiftc >/dev/null || fail "swiftc requis pour la pastille et l'app : xcode-select --install"
ok "swiftc présent"

step "Installation des fichiers dans $MURMURE_HOME"
mkdir -p "$MURMURE_HOME/models"
install_if_changed 755 "$SRC/src/murmure.sh"  "$MURMURE_HOME/murmure.sh"  "murmure.sh"
install_if_changed 755 "$SRC/src/corriger.pl" "$MURMURE_HOME/corriger.pl" "corriger.pl"
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
ok "scripts et configuration en place"

# swiftc ne produit pas deux fois le même binaire : on compare l'empreinte de la
# source et du compilateur pour savoir s'il faut recompiler.
step "Compilation de la pastille"
OVERLAY_SUM="$( { shasum -a 256 < "$SRC/src/overlay.swift"; swiftc --version 2>&1 | head -1; } | shasum -a 256 | cut -d' ' -f1)"
if [ -x "$MURMURE_HOME/overlay" ] && [ "$(cat "$MURMURE_HOME/overlay.sha256" 2>/dev/null)" = "$OVERLAY_SUM" ]; then
  ok "overlay déjà à jour"
  note "pastille : inchangée"
else
  swiftc -O -o "$MURMURE_HOME/overlay.new" "$SRC/src/overlay.swift"
  pkill -f "$MURMURE_HOME/overlay" 2>/dev/null || true   # pastille encore affichée
  mv -f "$MURMURE_HOME/overlay.new" "$MURMURE_HOME/overlay"
  echo "$OVERLAY_SUM" > "$MURMURE_HOME/overlay.sha256"
  ok "overlay compilé"
  note "pastille : recompilée"
fi

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
# ne re-signe le bundle que si son contenu change. swiftc ne produisant pas deux
# fois le même binaire, Info.plist porte l'empreinte des sources de l'app et du
# compilateur : l'app n'est recompilée que si cette empreinte change. Les mises à
# jour de murmure.sh ne la touchent pas.
step "Création de Murmure.app"
STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT
VERSION="$(tr -d '[:space:]' < "$SRC/VERSION")"
APP_SUM="$( { cat "$SRC"/src/app/*.swift | shasum -a 256; swiftc --version 2>&1 | head -1; } | shasum -a 256 | cut -d' ' -f1)"
cp "$SRC/app/Info.plist" "$STAGE/Info.plist"
plutil -replace CFBundleShortVersionString -string "$VERSION" "$STAGE/Info.plist"
plutil -replace CFBundleVersion -string "$VERSION" "$STAGE/Info.plist"
plutil -replace MurmureHome -string "$MURMURE_HOME" "$STAGE/Info.plist"
plutil -replace MurmureSourceSum -string "$APP_SUM" "$STAGE/Info.plist"
if [ -d "$APP" ] \
   && cmp -s "$STAGE/Info.plist" "$APP/Contents/Info.plist" \
   && [ -x "$APP/Contents/MacOS/Murmure" ] \
   && codesign --verify "$APP" >/dev/null 2>&1; then
  ok "$APP inchangée — signature et autorisations conservées"
  note "Murmure.app : inchangée"
else
  swiftc -O -parse-as-library -o "$STAGE/Murmure" "$SRC"/src/app/*.swift \
    || fail "compilation de Murmure.app impossible"
  if [ -d "$APP" ]; then
    note "Murmure.app : recréée — autorisation Accessibilité à supprimer puis rajouter (voir plus bas)"
    RECREATED=1
  else
    note "Murmure.app : créée"
  fi
  pkill -f "$APP/Contents/MacOS/Murmure" 2>/dev/null || true   # ancienne version
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
  mkdir -p "$APP/Contents/MacOS"
  cp "$STAGE/Info.plist" "$APP/Contents/Info.plist"
  cp "$STAGE/Murmure" "$APP/Contents/MacOS/Murmure"
  chmod +x "$APP/Contents/MacOS/Murmure"
  codesign --force --sign - "$APP" >/dev/null 2>&1 || warn "signature ad-hoc impossible"
  ok "$APP ($VERSION)"
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

# Nouvelle signature : l'ancienne entrée Accessibilité reste affichée cochée
# mais ne vaut plus, et la recocher ne suffit pas.
if [ "${RECREATED:-0}" = 1 ]; then
  PERMISSIONS="\
Murmure.app a été recréée : macOS ne reconnaît plus ses autorisations.

  1. ${bold}Accessibilité${off} — Réglages > Confidentialité et sécurité > Accessibilité :
     l'entrée Murmure reste cochée mais ne vaut plus. Sélectionnez-la,
     ${bold}supprimez-la (–)${off}, puis rajoutez-la (+, ⌘⇧G et coller : $APP)
     et cochez-la.
  2. ${bold}Micro${off} — si macOS le redemande à la première dictée : Autoriser.

Tant que l'Accessibilité manque, le menu de Murmure le signale en tête."
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
