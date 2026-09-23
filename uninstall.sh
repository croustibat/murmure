#!/bin/bash
# Murmure — désinstallation.
set -euo pipefail
MURMURE_HOME="${MURMURE_HOME:-$HOME/.local/share/murmure}"
APP="${MURMURE_APP_DIR:-$HOME/Applications}/Murmure.app"
STATE_DIR="${MURMURE_STATE_DIR:-/tmp/murmure-$(id -u)}"
KB="${MURMURE_KARABINER_DIR:-$HOME/.config/karabiner}/assets/complex_modifications/murmure.json"

echo "Cette opération supprime :"
echo "  $APP"
echo "  $MURMURE_HOME (dont le modèle Whisper et un éventuel téléchargement .part)"
[ -f "$KB" ] && echo "  $KB"
printf 'Continuer ? [o/N] '
read -r a
case "$a" in [oO]*) ;; *) echo "Annulé."; exit 0 ;; esac

pkill -f "$MURMURE_HOME/overlay" 2>/dev/null || true
rm -rf "$APP" "$MURMURE_HOME" "$STATE_DIR"
[ -f "$KB" ] && rm -f "$KB"
echo "Murmure a été supprimé."
echo "Pensez à retirer la règle dans Karabiner et l'entrée dans Accessibilité."
