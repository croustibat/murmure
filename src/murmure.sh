#!/bin/bash
# Murmure — dictée vocale locale pour macOS.
# Bascule : un appui démarre la capture, un second transcrit et colle.
# Lancé depuis Murmure.app pour disposer d'une identité TCC (autorisation Micro).
set -uo pipefail

# Karabiner/launchd ne transmettent aucune locale : sans ça, pbcopy réinterprète
# l'UTF-8 en MacRoman et « Société » devient « Soci√©t√© ».
export LANG="${LANG:-fr_FR.UTF-8}"
export LC_ALL="${LC_ALL:-fr_FR.UTF-8}"
export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"

MURMURE_HOME="${MURMURE_HOME:-$HOME/.local/share/murmure}"
MODEL_NAME="${MURMURE_MODEL_NAME:-ggml-large-v3-turbo-q5_0.bin}"

WHISPER_BIN="${MURMURE_WHISPER:-/opt/homebrew/bin/whisper-cli}"
FFMPEG_BIN="${MURMURE_FFMPEG:-/opt/homebrew/bin/ffmpeg}"
MODEL="${MURMURE_MODEL:-$MURMURE_HOME/models/$MODEL_NAME}"
LANGUAGE="${MURMURE_LANG:-fr}"
DEVICE="${MURMURE_DEVICE:-:0}"
MAX_SECONDS="${MURMURE_MAX:-300}"
MIN_BYTES="${MURMURE_MIN_BYTES:-48000}"   # ~1,5 s à 16 kHz mono 16 bits
SILENCE_DB="${MURMURE_SILENCE_DB:--70}"   # en dessous : rien n'a été capté
PROMPT_FILE="${MURMURE_PROMPT_FILE:-$MURMURE_HOME/vocabulaire.txt}"
CORRECTIONS="${MURMURE_CORRECTIONS:-$MURMURE_HOME/corrections.txt}"
CORRIGER="${MURMURE_CORRIGER:-$MURMURE_HOME/corriger.pl}"
CADENCE="${MURMURE_CADENCE:-$MURMURE_HOME/cadence}"   # vitesse mesurée de la machine
# Options ajoutées à whisper-cli (ex. « -bs 1 -bo 1 »). Vide par défaut : aucune
# option mesurée par scripts/bench.sh n'accélère une dictée courte d'au moins 10 %
# sans dégrader le texte, l'encodeur (fenêtre fixe de 30 s) dominant le temps.
read -r -a WHISPER_ARGS <<<"${MURMURE_WHISPER_ARGS:-}"

STATE_DIR="${MURMURE_STATE_DIR:-/tmp/murmure-$(id -u)}"
PID_FILE="$STATE_DIR/ffmpeg.pid"
WAV="$STATE_DIR/recording.wav"
LOG="$STATE_DIR/murmure.log"
STATUS="$STATE_DIR/status"
BUSY="$STATE_DIR/transcribing.pid"
OVERLAY="${MURMURE_OVERLAY:-$MURMURE_HOME/overlay}"
mkdir -p "$STATE_DIR"

# Calculs décimaux en locale C : en fr_FR, awk écrirait « 5,36 ».
calc()   { LC_ALL=C awk "$@"; }
now()    { perl -MTime::HiRes=time -e 'printf "%.3f", time'; }
log()    { printf '[%s] %s\n' "$(date '+%H:%M:%S')" "$*" >>"$LOG"; }
ding()   { afplay "/System/Library/Sounds/$1.aiff" >/dev/null 2>&1 & }
notify() { osascript -e "display notification \"$1\" with title \"Murmure\"" >/dev/null 2>&1; }
die()    { rm -f "$STATUS"; log "ERREUR: $*"; ding Basso; notify "$1"; exit 1; }

start_recording() {
  [ -x "$FFMPEG_BIN" ] || die "ffmpeg introuvable"
  [ -f "$MODEL" ]      || die "Modèle Whisper introuvable"
  rm -f "$WAV"
  nohup "$FFMPEG_BIN" -hide_banner -loglevel error \
      -f avfoundation -i "$DEVICE" \
      -t "$MAX_SECONDS" -ar 16000 -ac 1 -y "$WAV" \
      >>"$LOG" 2>&1 &
  echo $! >"$PID_FILE"
  log "capture démarrée (pid $!)"
  ding Tink

  printf 'recording' >"$STATUS"
  pkill -f "$OVERLAY" 2>/dev/null
  [ -x "$OVERLAY" ] && nohup "$OVERLAY" "$STATUS" "$MURMURE_HOME/murmure.sh" \
      >>"$LOG" 2>&1 &
}

# Whisper hallucine des génériques de sous-titres quand l'audio est vide.
is_hallucination() {
  # Testé sur une seule ligne : pas de motif « ligne vide » ici, il rejetterait
  # toute transcription valide (whisper préfixe sa sortie d'une ligne vide).
  printf '%s' "$1" | grep -qiE 'sous-titrage|sous-titres réalisés|amara\.org|radio-canada|merci d.avoir regardé cette vidéo|abonnez-vous à la chaîne'
}

# Vrai test de vacuité : au moins une lettre, sinon c'est du bruit.
has_speech() {
  printf '%s' "$1" | grep -qE '[[:alpha:]]'
}

stop_and_transcribe() {
  # Verrou posé avant de retirer PID_FILE : un nouvel appui pendant la
  # transcription ne doit pas relancer une capture par-dessus.
  echo $$ >"$BUSY"
  trap 'rm -f "$BUSY"' EXIT
  local pid; pid=$(cat "$PID_FILE" 2>/dev/null)
  rm -f "$PID_FILE"
  if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; then
    kill -INT "$pid" 2>/dev/null
    for _ in $(seq 1 40); do kill -0 "$pid" 2>/dev/null || break; sleep 0.05; done
    kill -0 "$pid" 2>/dev/null && kill -9 "$pid" 2>/dev/null
  fi
  ding Pop
  printf 'transcribing' >"$STATUS"
  local t0; t0=$(now)

  [ -s "$WAV" ] || die "Aucun fichier audio produit"
  local bytes; bytes=$(stat -f%z "$WAV")
  [ "$bytes" -gt "$MIN_BYTES" ] || die "Trop court — garde la touche plus longtemps"

  # Durée estimée de la transcription, pour la jauge de la pastille. Whisper ne
  # donne qu'une progression par fenêtre de 30 s : inexploitable sur une dictée.
  # Base : ~1,8 s de démarrage + 0,1 s par seconde d'audio, pondérée par un
  # facteur appris sur cette machine au fil des transcriptions.
  local base cadence estimate
  base=$(calc -v b="$bytes" 'BEGIN { printf "%.2f", 1.8 + 0.1 * b / 32000 }')
  cadence=$(cat "$CADENCE" 2>/dev/null); cadence=${cadence:-1}
  estimate=$(calc -v b="$base" -v c="$cadence" 'BEGIN { printf "%.2f", b * c }')
  printf 'transcribing %s' "$estimate" >"$STATUS"

  # Garde anti-silence : sans autorisation Micro, macOS livre un flux muet
  # au lieu d'une erreur, et Whisper invente alors du texte.
  local peak
  peak=$("$FFMPEG_BIN" -hide_banner -i "$WAV" -af volumedetect -f null - 2>&1 \
         | sed -n 's/.*max_volume: \(-*[0-9.]*\) dB.*/\1/p' | head -1)
  log "pic sonore: ${peak:-?} dB"
  if [ -n "$peak" ] && [ "${peak%.*}" -lt "$SILENCE_DB" ] 2>/dev/null; then
    die "Aucun son capté — autorise le Micro pour Murmure"
  fi

  # Vocabulaire technique : sans ça, « Bash » devient « Bache », « commit » devient
  # « comité », etc. --carry-initial-prompt le réapplique à chaque fenêtre de 30 s.
  local -a prompt_args=()
  if [ -s "$PROMPT_FILE" ]; then
    prompt_args=(--prompt "$(tr -d '\n' <"$PROMPT_FILE")" --carry-initial-prompt)
  fi

  local text
  text=$("$WHISPER_BIN" -m "$MODEL" -f "$WAV" -l "$LANGUAGE" \
           "${prompt_args[@]}" ${WHISPER_ARGS[@]+"${WHISPER_ARGS[@]}"} \
           --no-timestamps --no-prints 2>>"$LOG")
  text=$(printf '%s' "$text" | tr '\n' ' ' | sed -e 's/  */ /g' -e 's/^ *//' -e 's/ *$//')

  # Dictionnaire de corrections : le prompt initial ne suffit pas sur l'anglais
  # technique (« commit » → « commis »). Édite corrections.txt pour l'enrichir.
  if [ -s "$CORRECTIONS" ] && [ -x "$CORRIGER" ]; then
    text=$(printf '%s' "$text" | "$CORRIGER" "$CORRECTIONS")
  fi

  has_speech "$text" || die "Transcription vide"
  if is_hallucination "$text"; then
    log "rejeté (hallucination): $text"
    die "Rien d'audible détecté"
  fi

  local elapsed; elapsed=$(calc -v a="$t0" -v b="$(now)" 'BEGIN { printf "%.2f", b - a }')
  calc -v c="$cadence" -v e="$elapsed" -v b="$base" 'BEGIN {
    r = e / b; if (r < 0.3) r = 0.3; if (r > 5) r = 5
    printf "%.3f\n", 0.7 * c + 0.3 * r }' >"$CADENCE" 2>/dev/null
  log "transcription: ${elapsed}s (estimé ${estimate}s)"

  # La pastille reste affichée, jauge pleine, jusqu'au collage effectif :
  # osascript met parfois plus d'une seconde à envoyer le ⌘V.
  printf 'pasting' >"$STATUS"
  printf '%s' "$text" | iconv -f UTF-8 -t UTF-8 | pbcopy
  log "transcrit: $text"
  osascript -e 'tell application "System Events" to keystroke "v" using command down' \
    >>"$LOG" 2>&1 || notify "Texte copié — Cmd+V pour coller"
  rm -f "$STATUS"
}

if [ -f "$PID_FILE" ]; then
  stop_and_transcribe
elif kill -0 "$(cat "$BUSY" 2>/dev/null)" 2>/dev/null; then
  log "appui ignoré : transcription en cours"
else
  start_recording
fi
