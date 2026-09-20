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

STATE_DIR="${MURMURE_STATE_DIR:-/tmp/murmure-$(id -u)}"
PID_FILE="$STATE_DIR/ffmpeg.pid"
WAV="$STATE_DIR/recording.wav"
LOG="$STATE_DIR/murmure.log"
STATUS="$STATE_DIR/status"
OVERLAY="${MURMURE_OVERLAY:-$MURMURE_HOME/overlay}"
mkdir -p "$STATE_DIR"

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
  local pid; pid=$(cat "$PID_FILE" 2>/dev/null)
  rm -f "$PID_FILE"
  if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; then
    kill -INT "$pid" 2>/dev/null
    for _ in $(seq 1 40); do kill -0 "$pid" 2>/dev/null || break; sleep 0.05; done
    kill -0 "$pid" 2>/dev/null && kill -9 "$pid" 2>/dev/null
  fi
  ding Pop
  printf 'transcribing' >"$STATUS"

  [ -s "$WAV" ] || die "Aucun fichier audio produit"
  local bytes; bytes=$(stat -f%z "$WAV")
  [ "$bytes" -gt "$MIN_BYTES" ] || die "Trop court — garde la touche plus longtemps"

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
           "${prompt_args[@]}" --no-timestamps --no-prints 2>>"$LOG")
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

  rm -f "$STATUS"
  printf '%s' "$text" | iconv -f UTF-8 -t UTF-8 | pbcopy
  log "transcrit: $text"
  osascript -e 'tell application "System Events" to keystroke "v" using command down' \
    >>"$LOG" 2>&1 || notify "Texte copié — Cmd+V pour coller"
}

if [ -f "$PID_FILE" ]; then stop_and_transcribe; else start_recording; fi
