#!/bin/bash
# Murmure — désinstallation. L'app (installée par ./install.sh, le DMG ou
# Homebrew), le lancement au démarrage et les traces des mises à jour ; les
# données de $MURMURE_HOME (réglages, vocabulaire, modèle…) sur demande seulement.
set -euo pipefail
MURMURE_HOME="${MURMURE_HOME:-$HOME/.local/share/murmure}"
APP="${MURMURE_APP_DIR:-/Applications}/Murmure.app"
# Emplacement des versions ≤ 1.1.0, retiré aussi lors d'une désinstallation par défaut.
OLD_APP=""; [ -z "${MURMURE_APP_DIR:-}" ] && [ -d "$HOME/Applications/Murmure.app" ] && OLD_APP="$HOME/Applications/Murmure.app"
STATE_DIR="${MURMURE_STATE_DIR:-/tmp/murmure-$(id -u)}"
KB="${MURMURE_KARABINER_DIR:-$HOME/.config/karabiner}/assets/complex_modifications/murmure.json"
# MURMURE_LIBRARY_DIR remplace ~/Library (tests) : le domaine de réglages est
# alors lu comme un fichier de ce dossier, jamais celui de l'app installée.
LIBRARY="${MURMURE_LIBRARY_DIR:-$HOME/Library}"
AGENT="${MURMURE_LAUNCH_AGENTS_DIR:-$LIBRARY/LaunchAgents}/dev.croustibat.murmure.plist"
PREFS=dev.croustibat.murmure
[ -n "${MURMURE_LIBRARY_DIR:-}" ] && PREFS="$LIBRARY/Preferences/dev.croustibat.murmure"
# Traces de Sparkle (et des téléchargements de l'app) : son cache, son stockage
# HTTP, et ses clés SU* dans les réglages de l'app.
TRACES=()
for t in "$LIBRARY/Caches/dev.croustibat.murmure" "$LIBRARY/HTTPStorages/dev.croustibat.murmure" \
         "$LIBRARY/HTTPStorages/dev.croustibat.murmure.binarycookies"; do
  [ -e "$t" ] && TRACES+=("$t")
done
SU_KEYS=()
while read -r cle; do [ -n "$cle" ] && SU_KEYS+=("$cle"); done < <(defaults read "$PREFS" 2>/dev/null \
  | sed -n 's/^ *"\{0,1\}\(SU[A-Za-z]*\)"\{0,1\} = .*/\1/p')
CASK=""
command -v brew >/dev/null && [ -d "$(brew --prefix)/Caskroom/murmure" ] && CASK=1

echo "Cette opération supprime :"
[ -d "$APP" ] && echo "  $APP"
[ -n "$OLD_APP" ] && echo "  $OLD_APP"
for t in ${TRACES[@]+"${TRACES[@]}"}; do echo "  $t"; done
[ "${#SU_KEYS[@]}" -gt 0 ] && echo "  les réglages des mises à jour (${SU_KEYS[*]})"
[ -f "$KB" ] && echo "  $KB"
[ -f "$AGENT" ] && echo "  $AGENT"
echo "  le lancement au démarrage et le journal ($STATE_DIR)"
[ -n "$CASK" ] && echo "Installée avec Homebrew : brew uninstall --cask murmure fait la même chose."
printf 'Continuer ? [o/N] '
read -r a || a=""
case "$a" in [oO]*) ;; *) echo "Annulé."; exit 0 ;; esac

# Les données ne sont pas réinstallables : une nouvelle installation les
# reprendrait telles quelles. On ne les retire que sur demande explicite.
DATA=0
if [ -d "$MURMURE_HOME" ]; then
  echo "Vos données sont dans $MURMURE_HOME : réglages, vocabulaire, corrections,"
  echo "historique et modèle Whisper (~550 Mo)."
  printf 'Les supprimer aussi ? [o/N] '
  read -r a || a=""
  case "$a" in [oO]*) DATA=1 ;; esac
fi

# Lancement au démarrage retiré par l'app elle-même (élément de connexion ou
# LaunchAgent), puis l'app résidente est quittée.
[ -x "$APP/Contents/MacOS/Murmure" ] && "$APP/Contents/MacOS/Murmure" --demarrage non >/dev/null 2>&1 || true
pkill -f "$APP/Contents/MacOS/Murmure" 2>/dev/null || true
# Pastille, enregistreur, ou whisper-cli d'un préchauffage, qui survit à l'app.
pkill -f "$APP/Contents/Helpers/" 2>/dev/null || true
rm -rf "$APP" "$STATE_DIR"
[ -n "$OLD_APP" ] && { pkill -f "$OLD_APP/Contents/MacOS/Murmure" 2>/dev/null || true; rm -rf "$OLD_APP"; }
[ -f "$KB" ] && rm -f "$KB"
[ -f "$AGENT" ] && rm -f "$AGENT"
rm -rf ${TRACES[@]+"${TRACES[@]}"}
for cle in ${SU_KEYS[@]+"${SU_KEYS[@]}"}; do defaults delete "$PREFS" "$cle" 2>/dev/null || true; done

echo "Murmure a été supprimé."
if [ "$DATA" = 1 ]; then
  rm -rf "$MURMURE_HOME"
  echo "Données supprimées ($MURMURE_HOME)."
elif [ -d "$MURMURE_HOME" ]; then
  echo "Données conservées dans $MURMURE_HOME : une nouvelle installation les reprendra."
fi
echo "Pensez à retirer l'entrée dans Accessibilité, et une éventuelle règle Murmure dans Karabiner."
