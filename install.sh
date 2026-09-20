#!/bin/bash
# Murmure — installation.
set -euo pipefail

MURMURE_HOME="${MURMURE_HOME:-$HOME/.local/share/murmure}"
APP_DIR="${MURMURE_APP_DIR:-$HOME/Applications}"
APP="$APP_DIR/Murmure.app"
MODEL_NAME="${MURMURE_MODEL_NAME:-ggml-large-v3-turbo-q5_0.bin}"
MODEL_URL="https://huggingface.co/ggerganov/whisper.cpp/resolve/main/$MODEL_NAME"
SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

bold=$'\033[1m'; green=$'\033[32m'; yellow=$'\033[33m'; red=$'\033[31m'; off=$'\033[0m'
step() { printf '%s==>%s %s\n' "$bold" "$off" "$1"; }
ok()   { printf '    %s✓%s %s\n' "$green" "$off" "$1"; }
warn() { printf '    %s!%s %s\n' "$yellow" "$off" "$1"; }
fail() { printf '%s✗%s %s\n' "$red" "$off" "$1" >&2; exit 1; }

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
install -m 755 "$SRC/src/murmure.sh"  "$MURMURE_HOME/murmure.sh"
install -m 755 "$SRC/src/corriger.pl" "$MURMURE_HOME/corriger.pl"
for f in vocabulaire corrections; do
  if [ -f "$MURMURE_HOME/$f.txt" ]; then
    warn "$f.txt existe déjà — conservé (nouvelle version dans $f.txt.dist)"
    install -m 644 "$SRC/config/$f.txt" "$MURMURE_HOME/$f.txt.dist"
  else
    install -m 644 "$SRC/config/$f.txt" "$MURMURE_HOME/$f.txt"
  fi
done
ok "scripts et configuration en place"

step "Compilation de la pastille"
swiftc -O -o "$MURMURE_HOME/overlay" "$SRC/src/overlay.swift"
ok "overlay compilé"

step "Modèle Whisper ($MODEL_NAME)"
if [ -s "$MURMURE_HOME/models/$MODEL_NAME" ]; then
  ok "déjà présent"
else
  echo "    téléchargement (~550 Mo, une seule fois)…"
  curl -L --fail --progress-bar -o "$MURMURE_HOME/models/$MODEL_NAME.part" "$MODEL_URL"
  mv "$MURMURE_HOME/models/$MODEL_NAME.part" "$MURMURE_HOME/models/$MODEL_NAME"
  ok "modèle téléchargé"
fi

# Le bundle .app est indispensable : un script nu n'a pas d'identité TCC, macOS ne
# propose jamais l'autorisation micro et livre un flux muet à la place.
step "Création de Murmure.app"
mkdir -p "$APP_DIR"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp "$SRC/app/Info.plist" "$APP/Contents/Info.plist"
cat > "$APP/Contents/MacOS/Murmure" <<EXE
#!/bin/bash
exec "$MURMURE_HOME/murmure.sh"
EXE
chmod +x "$APP/Contents/MacOS/Murmure"
codesign --force --sign - "$APP" >/dev/null 2>&1 || warn "signature ad-hoc impossible"
ok "$APP"

step "Raccourci clavier"
KB_DIR="$HOME/.config/karabiner/assets/complex_modifications"
if [ -d "$HOME/.config/karabiner" ]; then
  mkdir -p "$KB_DIR"
  cat > "$KB_DIR/murmure.json" <<KB
{
    "title": "Murmure",
    "rules": [
        {
            "description": "Murmure : ⌘⇧E bascule dictée",
            "manipulators": [
                {
                    "type": "basic",
                    "from": { "key_code": "e", "modifiers": { "mandatory": ["command", "shift"] } },
                    "to": [{ "shell_command": "/usr/bin/open -n -a '$APP'" }]
                }
            ]
        }
    ]
}
KB
  ok "règle déposée — active-la dans Karabiner > Complex Modifications > Add rule"
else
  warn "Karabiner-Elements non détecté."
  echo "    Associe ce raccourci à la commande :"
  echo "      /usr/bin/open -n -a '$APP'"
fi

cat <<FIN

${bold}Installation terminée.${off}

Il reste deux autorisations à accorder, au ${bold}premier usage${off} :

  1. ${bold}Micro${off} — un dialogue « Murmure » apparaîtra : Autoriser.
  2. ${bold}Accessibilité${off} — pour que le texte se colle tout seul.
     Réglages > Confidentialité et sécurité > Accessibilité > +
     puis ⌘⇧G et coller : $APP

Sans la seconde, le texte va dans le presse-papiers et vous faites ⌘V.

Essai : ⌘⇧E, parlez, ⌘⇧E.
Journal : /tmp/murmure-$(id -u)/murmure.log
FIN
