#!/bin/bash
# Murmure — installation.
set -euo pipefail

MURMURE_HOME="${MURMURE_HOME:-$HOME/.local/share/murmure}"
APP_DIR="${MURMURE_APP_DIR:-$HOME/Applications}"
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
command -v swiftc >/dev/null || fail "swiftc requis pour la pastille : xcode-select --install"
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
# ne re-signe le bundle que si son contenu change. Son exécutable n'est qu'un
# lanceur de murmure.sh, les mises à jour du script ne le touchent donc pas.
step "Création de Murmure.app"
STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT
cat > "$STAGE/Murmure" <<EXE
#!/bin/bash
exec "$MURMURE_HOME/murmure.sh" "\$@"
EXE
if [ -d "$APP" ] \
   && cmp -s "$SRC/app/Info.plist" "$APP/Contents/Info.plist" \
   && cmp -s "$STAGE/Murmure" "$APP/Contents/MacOS/Murmure" \
   && codesign --verify "$APP" >/dev/null 2>&1; then
  ok "$APP inchangée — signature et autorisations conservées"
  note "Murmure.app : inchangée"
else
  if [ -d "$APP" ]; then
    note "Murmure.app : recréée — autorisations Micro et Accessibilité à redonner"
  else
    note "Murmure.app : créée"
  fi
  mkdir -p "$APP_DIR"
  rm -rf "$APP"
  mkdir -p "$APP/Contents/MacOS"
  cp "$SRC/app/Info.plist" "$APP/Contents/Info.plist"
  cp "$STAGE/Murmure" "$APP/Contents/MacOS/Murmure"
  chmod +x "$APP/Contents/MacOS/Murmure"
  codesign --force --sign - "$APP" >/dev/null 2>&1 || warn "signature ad-hoc impossible"
  ok "$APP"
fi

# Règles actives de karabiner.json sur ⌘⇧E, une par ligne :
# « ok|profil|règle|commande » si elle lance $APP, « conflit|… » sinon.
# Lecture seule : karabiner.json n'est jamais modifié.
karabiner_rules() {  # karabiner.json app
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
          for (const m of r.manipulators || []) {
            const f = m.from || {};
            const mods = (f.modifiers || {}).mandatory || [];
            if (f.key_code !== "e" || !has(mods, "command") || !has(mods, "shift")) continue;
            const cmds = (m.to || []).map(t => t.shell_command).filter(Boolean);
            const mine = cmds.some(c => c.includes(argv[1]));
            const cmd = cmds.join(" ; ") || JSON.stringify(m.to || []);
            const kind = !mine ? "conflit" : cmds.some(c => c.includes("--args press")) ? "ok" : "ancienne";
            out.push([kind, p.name || "?", r.description || "(sans description)", cmd].join("|"));
          }
        }
      }
      return out.join("\n");
    }' "$1" "$2" 2>/dev/null || true
}

step "Raccourci clavier"
KB_DIR="$KARABINER_DIR/assets/complex_modifications"
if [ -d "$KARABINER_DIR" ]; then
  mkdir -p "$KB_DIR"
  cat > "$KB_DIR/murmure.json" <<KB
{
    "title": "Murmure",
    "rules": [
        {
            "description": "Murmure : ⌘⇧E dictée (appui bref : bascule, maintenu : parler), Échap annule",
            "manipulators": [
                {
                    "type": "basic",
                    "from": { "key_code": "e", "modifiers": { "mandatory": ["command", "shift"] } },
                    "to": [{ "shell_command": "/usr/bin/open -n -a '$APP' --args press" }],
                    "to_after_key_up": [{ "shell_command": "/usr/bin/open -n -a '$APP' --args release" }]
                },
                {
                    "type": "basic",
                    "from": { "key_code": "escape" },
                    "conditions": [{ "type": "variable_if", "name": "murmure_ecoute", "value": 1 }],
                    "to": [{ "shell_command": "/usr/bin/open -n -a '$APP' --args cancel" }]
                }
            ]
        }
    ]
}
KB
  KB_ACTIVE=0; KB_CONFLICT=0; KB_OLD=0
  if [ -f "$KARABINER_DIR/karabiner.json" ]; then
    while IFS='|' read -r kind profile desc cmd; do
      case "$kind" in
        ok) KB_ACTIVE=1 ;;
        ancienne) KB_OLD=1 ;;
        conflit)
          KB_CONFLICT=1
          warn "conflit : une règle ⌘⇧E active ne lance pas $APP"
          echo "      profil   : $profile"
          echo "      règle    : $desc"
          echo "      commande : $cmd"
          ;;
      esac
    done < <(karabiner_rules "$KARABINER_DIR/karabiner.json" "$APP")
  fi
  if [ "$KB_CONFLICT" = 1 ]; then
    echo "      Cette règle l'emporte et ⌘⇧E lance autre chose que Murmure."
    echo "      Corrigez dans Karabiner > Complex Modifications : Remove sur l'ancienne"
    echo "      règle, puis Add rule > Murmure. $KARABINER_DIR/karabiner.json n'est"
    echo "      pas modifié automatiquement."
    note "raccourci : CONFLIT avec une autre règle ⌘⇧E (voir plus haut)"
  elif [ "$KB_OLD" = 1 ] && [ "$KB_ACTIVE" = 0 ]; then
    warn "la règle ⌘⇧E active est une ancienne version (bascule seule)"
    echo "      Pour maintenir-pour-parler et Échap : Remove sur l'ancienne règle,"
    echo "      puis Add rule > Murmure dans Karabiner > Complex Modifications."
    note "raccourci : ancienne règle active (à remplacer)"
  elif [ "$KB_ACTIVE" = 1 ]; then
    ok "règle déposée — déjà active dans Karabiner"
    note "raccourci : actif"
  else
    ok "règle déposée — active-la dans Karabiner > Complex Modifications > Add rule"
    note "raccourci : règle à activer dans Karabiner"
  fi
else
  warn "Karabiner-Elements non détecté."
  echo "    Associe ce raccourci à la commande :"
  echo "      /usr/bin/open -n -a '$APP'"
fi

cat <<FIN

${bold}Installation terminée.${off}

$(printf '  - %s\n' "${CHANGES[@]}")

Il reste deux autorisations à accorder, au ${bold}premier usage${off} :

  1. ${bold}Micro${off} — un dialogue « Murmure » apparaîtra : Autoriser.
  2. ${bold}Accessibilité${off} — pour que le texte se colle tout seul.
     Réglages > Confidentialité et sécurité > Accessibilité > +
     puis ⌘⇧G et coller : $APP

Sans la seconde, le texte va dans le presse-papiers et vous faites ⌘V.

Essai : ⌘⇧E, parlez, ⌘⇧E — ou gardez ⌘⇧E enfoncé le temps de parler.
Échap pendant l'écoute annule.
Journal : /tmp/murmure-$(id -u)/murmure.log
FIN
