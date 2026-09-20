#!/bin/bash
# Murmure — désinstallation.
set -euo pipefail
MURMURE_HOME="${MURMURE_HOME:-$HOME/.local/share/murmure}"
APP="${MURMURE_APP_DIR:-$HOME/Applications}/Murmure.app"
KB="$HOME/.config/karabiner/assets/complex_modifications/murmure.json"

echo "Cette opération supprime :"
echo "  $APP"
echo "  $MURMURE_HOME (dont le modèle Whisper)"
[ -f "$KB" ] && echo "  $KB"
printf 'Continuer ? [o/N] '
read -r a
case "$a" in [oO]*) ;; *) echo "Annulé."; exit 0 ;; esac

pkill -f "$MURMURE_HOME/overlay" 2>/dev/null || true
rm -rf "$APP" "$MURMURE_HOME" "/tmp/murmure-$(id -u)"
[ -f "$KB" ] && rm -f "$KB"
echo "Murmure a été supprimé."
echo "Pensez à retirer la règle dans Karabiner et l'entrée dans Accessibilité."
