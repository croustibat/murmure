#!/bin/bash
# Murmure — désinstallation.
set -euo pipefail
MURMURE_HOME="${MURMURE_HOME:-$HOME/.local/share/murmure}"
APP="${MURMURE_APP_DIR:-$HOME/Applications}/Murmure.app"
STATE_DIR="${MURMURE_STATE_DIR:-/tmp/murmure-$(id -u)}"
KB="${MURMURE_KARABINER_DIR:-$HOME/.config/karabiner}/assets/complex_modifications/murmure.json"
AGENT="${MURMURE_LAUNCH_AGENTS_DIR:-$HOME/Library/LaunchAgents}/dev.croustibat.murmure.plist"

echo "Cette opération supprime :"
echo "  $APP"
echo "  $MURMURE_HOME (dont le modèle Whisper et un éventuel téléchargement .part)"
[ -f "$KB" ] && echo "  $KB"
[ -f "$AGENT" ] && echo "  $AGENT"
printf 'Continuer ? [o/N] '
read -r a
case "$a" in [oO]*) ;; *) echo "Annulé."; exit 0 ;; esac

# Lancement au démarrage retiré par l'app elle-même (élément de connexion ou
# LaunchAgent), puis l'app résidente est quittée.
[ -x "$APP/Contents/MacOS/Murmure" ] && "$APP/Contents/MacOS/Murmure" --demarrage non >/dev/null 2>&1 || true
pkill -f "$APP/Contents/MacOS/Murmure" 2>/dev/null || true
pkill -f "$MURMURE_HOME/overlay" 2>/dev/null || true
rm -rf "$APP" "$MURMURE_HOME" "$STATE_DIR"
[ -f "$KB" ] && rm -f "$KB"
[ -f "$AGENT" ] && rm -f "$AGENT"
echo "Murmure a été supprimé."
echo "Pensez à retirer l'entrée dans Accessibilité, et une éventuelle règle Murmure dans Karabiner."
