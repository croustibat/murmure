#!/bin/bash
# Murmure — dictée vocale locale pour macOS.
# Bascule : un appui démarre la capture, un second transcrit et colle.
# Sous-commandes : toggle (défaut), press / release (maintenir pour parler),
# cancel (annuler l'écoute sans rien transcrire), expire (interne : durée max atteinte).
# Lancé depuis Murmure.app pour disposer d'une identité TCC (autorisation Micro).
set -uo pipefail

# Karabiner/launchd ne transmettent aucune locale : sans ça, pbcopy réinterprète
# l'UTF-8 en MacRoman et « Société » devient « Soci√©t√© ».
export LANG="${LANG:-fr_FR.UTF-8}"
export LC_ALL="${LC_ALL:-fr_FR.UTF-8}"
export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"

MURMURE_HOME="${MURMURE_HOME:-$HOME/.local/share/murmure}"

# Réglages lus dans $MURMURE_HOME/config : le raccourci ne transmet aucune
# variable d'environnement. Lignes « CLE=valeur », jamais exécutées (pas de
# source) : seules les clés connues sont retenues, et une variable
# d'environnement l'emporte sur le fichier. Les clés réservées (raccourci lu par
# l'app, presse-papiers) sont acceptées mais pas encore utilisées.
CONFIG="$MURMURE_HOME/config"
CONFIG_KEYS=" MURMURE_LANG MURMURE_DEVICE MURMURE_MAX MURMURE_SILENCE_DB MURMURE_HOLD_MS MURMURE_WHISPER_ARGS MURMURE_SHORTCUT MURMURE_HISTORY MURMURE_RESTORE_CLIPBOARD "
CONFIG_NOTES=()   # anomalies, journalisées une fois le journal disponible
load_config() {
  [ -r "$CONFIG" ] || return 0
  local env_keys=' ' key line value n=0
  for key in $CONFIG_KEYS; do
    [ -n "${!key+x}" ] && env_keys+="$key "
  done
  while IFS= read -r line || [ -n "$line" ]; do
    n=$((n + 1)); line=${line%$'\r'}
    [[ $line =~ ^[[:space:]]*(#|$) ]] && continue
    if ! [[ $line =~ ^[[:space:]]*(MURMURE_[A-Z_]+)[[:space:]]*=[[:space:]]*(.*[^[:space:]])?[[:space:]]*$ ]]; then
      CONFIG_NOTES+=("config ligne $n ignorée (malformée) : $line"); continue
    fi
    key=${BASH_REMATCH[1]} value=${BASH_REMATCH[2]}
    case "$CONFIG_KEYS" in
      *" $key "*) ;;
      *) CONFIG_NOTES+=("config ligne $n ignorée (clé inconnue) : $key"); continue ;;
    esac
    case "$value" in
      \"*\"|\'*\') value=${value:1:${#value}-2} ;;   # guillemets tolérés
    esac
    case "$key" in
      MURMURE_MAX|MURMURE_HOLD_MS) [[ $value =~ ^[0-9]+$ ]] ;;
      MURMURE_SILENCE_DB) [[ $value =~ ^-?[0-9]+$ ]] ;;
      MURMURE_LANG) [[ $value =~ ^[a-z]+$ ]] ;;
      MURMURE_HISTORY) [[ $value =~ ^[01]$ ]] ;;
    esac || { CONFIG_NOTES+=("config ligne $n ignorée (valeur invalide) : $key=$value"); continue; }
    case "$env_keys" in *" $key "*) continue ;; esac
    printf -v "$key" '%s' "$value"
  done <"$CONFIG"
}
load_config

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
LEVELS="$STATE_DIR/levels"   # niveau RMS de la voix, lu par la pastille
LOG="$STATE_DIR/murmure.log"
STATUS="$STATE_DIR/status"
BUSY="$STATE_DIR/transcribing.pid"
TARGET="$STATE_DIR/target"   # app active au démarrage : « pid bundleid »
STARTED="$STATE_DIR/started"   # horodatage du début de capture
WHISPER_ERR="$STATE_DIR/whisper.err"   # sortie d'erreur de whisper-cli
LOG_MAX="${MURMURE_LOG_MAX:-1048576}"   # au-delà, murmure.log devient murmure.log.1
HOLD_MS="${MURMURE_HOLD_MS:-600}" # au-delà, relâcher la touche arrête la capture
OVERLAY="${MURMURE_OVERLAY:-$MURMURE_HOME/overlay}"
HISTORIQUE="$MURMURE_HOME/historique.jsonl"   # dernières dictées, lues par le menu
mkdir -p "$STATE_DIR"

# Calculs décimaux en locale C : en fr_FR, awk écrirait « 5,36 ».
calc()   { LC_ALL=C awk "$@"; }
now()    { perl -MTime::HiRes=time -e 'printf "%.3f", time'; }
log()    { printf '[%s] %s\n' "$(date '+%H:%M:%S')" "$*" >>"$LOG"; }
ding()   { afplay "/System/Library/Sounds/$1.aiff" >/dev/null 2>&1 & }
notify() { osascript -e "display notification \"$1\" with title \"Murmure\"" >/dev/null 2>&1; }
die()    { rm -f "$STATUS"; log "ERREUR: $*"; ding Basso; notify "$1"; exit 1; }

for note in ${CONFIG_NOTES[@]+"${CONFIG_NOTES[@]}"}; do log "$note"; done

# Réclamation atomique de la capture : press, release et cancel tournent dans
# des processus distincts, un seul doit l'arrêter.
claim_capture() { mv "$PID_FILE" "$PID_FILE.$$" 2>/dev/null; }

# Coupe ffmpeg (SIGINT pour qu'il finalise le WAV, SIGKILL en dernier recours).
stop_ffmpeg() {
  local pid; pid=$(cat "$PID_FILE.$$" 2>/dev/null)
  rm -f "$PID_FILE.$$" "$STARTED" "$LEVELS"
  if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; then
    kill -INT "$pid" 2>/dev/null
    for _ in $(seq 1 40); do kill -0 "$pid" 2>/dev/null || break; sleep 0.05; done
    kill -0 "$pid" 2>/dev/null && kill -9 "$pid" 2>/dev/null
  fi
}

# App au premier plan, sous la forme « pid bundleid ».
front_app() {
  lsappinfo info -only pid -only bundleid "$(lsappinfo front)" 2>/dev/null | awk '
    /pid = / { sub(/.*pid = /, ""); sub(/ .*/, ""); pid = $0 }
    /bundleID="/ { sub(/.*bundleID="/, ""); sub(/".*/, ""); id = $0 }
    END { if (pid) print pid, id }'
}

# Mémorise la cible du collage. Murmure.app (LSUIElement) et la pastille ne
# prennent pas le premier plan, mais on écarte Murmure par sécurité.
remember_target() {
  local app; app=$(front_app)
  rm -f "$TARGET"
  case "$app" in
    ''|*' dev.croustibat.murmure') log "cible : inconnue" ;;
    *) printf '%s\n' "$app" >"$TARGET"; log "cible : $app" ;;
  esac
}

# Réactive l'app cible si on en a changé pendant la transcription, puis ⌘V.
# Échoue sans coller si la cible ne revient pas au premier plan.
paste_into() {
  local pid=$1 bundle=$2 front
  front=$(front_app); front=${front%% *}
  if [ -n "$pid" ] && [ "$front" != "$pid" ]; then
    log "retour vers $bundle (pid $pid)"
    osascript -e "tell application \"System Events\" to set frontmost of (first process whose unix id is $pid) to true" \
      >>"$LOG" 2>&1 || { [ -n "$bundle" ] && open -b "$bundle"; }
    for _ in $(seq 1 10); do
      front=$(front_app); [ "${front%% *}" = "$pid" ] && break; sleep 0.05
    done
    [ "${front%% *}" = "$pid" ] || { log "cible non réactivée"; return 1; }
  fi
  osascript -e 'tell application "System Events" to keystroke "v" using command down' \
    >>"$LOG" 2>&1
}

# MURMURE_DEVICE accepte un index avfoundation (« :0 ») ou un nom de micro,
# résolu ici en index : l'index change quand on branche un casque, pas le nom.
# Nom exact (casse ignorée), sinon premier micro dont le nom le contient.
resolve_device() {
  case "$DEVICE" in *[!0-9:]*) ;; *) return 0 ;; esac
  local name=${DEVICE#:} index
  index=$("$FFMPEG_BIN" -hide_banner -f avfoundation -list_devices true -i "" 2>&1 \
    | awk -v want="$name" '
      /AVFoundation audio devices:/ { audio = 1; next }
      /AVFoundation video devices:/ { audio = 0; next }
      audio && sub(/^\[[^]]*\] \[/, "") {
        i = $0; sub(/\].*/, "", i); n = $0; sub(/^[0-9]+\] /, "", n)
        if (tolower(n) == tolower(want)) { if (exact == "") exact = i }
        else if (index(tolower(n), tolower(want)) && part == "") part = i
      }
      END { print (exact != "" ? exact : part) }')
  if [ -n "$index" ]; then
    log "micro « $name » : index $index"
    DEVICE=":$index"
  else
    log "micro « $name » introuvable : micro par défaut"
    DEVICE=":0"
  fi
}

start_recording() {
  [ -x "$FFMPEG_BIN" ] || die "ffmpeg introuvable"
  [ -f "$MODEL" ]      || die "Modèle Whisper introuvable"
  resolve_device
  rm -f "$WAV" "$LEVELS"
  local size; size=$(stat -f%z "$LOG" 2>/dev/null || echo 0)
  [ "$size" -gt "$LOG_MAX" ] && mv -f "$LOG" "$LOG.1"
  # Niveau RMS écrit 20 fois par seconde (trames de 800 échantillons à 16 kHz)
  # pour l'onde de la pastille ; astats ne modifie pas l'audio enregistré.
  # Le fichier croît d'environ 1,5 Ko/s, borné par MAX_SECONDS.
  nohup "$FFMPEG_BIN" -hide_banner -loglevel error \
      -f avfoundation -i "$DEVICE" \
      -af "aresample=16000,asetnsamples=n=800:p=0,astats=metadata=1:reset=1,ametadata=print:key=lavfi.astats.Overall.RMS_level:file=$LEVELS:direct=1" \
      -t "$MAX_SECONDS" -ar 16000 -ac 1 -y "$WAV" \
      >>"$LOG" 2>&1 &
  local pid=$! t0; t0=$(now)
  echo "$t0" >"$STARTED"
  echo $pid >"$PID_FILE"
  # À la limite, ffmpeg s'arrête seul (-t) : on transcrit alors comme sur un
  # second appui. Une seconde de marge laisse ffmpeg finaliser le WAV ; expire
  # vérifie pid et horodatage pour ne jamais couper une capture suivante.
  nohup /bin/bash -c 'sleep "$1" && exec /bin/bash "$2" expire "$3" "$4"' _ \
      "$((MAX_SECONDS + 1))" "$0" "$pid" "$t0" >>"$LOG" 2>&1 &
  log "capture démarrée (pid $pid)"
  remember_target   # après ffmpeg : ne pas retarder la capture
  ding Tink

  printf 'recording %s' "$MAX_SECONDS" >"$STATUS"   # durée max : compte à rebours
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

# Ajoute la dictée à l'historique (une ligne JSON par dictée, 100 au plus, les
# plus anciennes supprimées). JSON::PP échappe guillemets et retours ligne ;
# réécriture dans un fichier temporaire puis renommage, lecture comprise par le
# menu. Local uniquement : MURMURE_HISTORY=0 n'écrit rien.
# $1 texte, $2 taille du WAV en octets, $3 bundle id de l'app cible.
add_history() {
  [ "${MURMURE_HISTORY:-1}" = 0 ] && return 0
  HIST_TEXTE=$1 HIST_OCTETS=$2 HIST_APP=$3 perl -MJSON::PP -MPOSIX=strftime -e '
    my $f = shift;
    my $texte = $ENV{HIST_TEXTE}; utf8::decode($texte);
    (my $date = strftime("%Y-%m-%dT%H:%M:%S%z", localtime)) =~ s/(\d\d)$/:$1/;
    my @l;
    if (open my $in, "<", $f) { @l = map { s/\n?\z/\n/r } grep { /\S/ } <$in>; close $in }
    push @l, JSON::PP->new->utf8->canonical->encode({
      date => $date, texte => $texte, app => $ENV{HIST_APP} || undef,
      duree_audio_s => 0 + sprintf("%.1f", ($ENV{HIST_OCTETS} - 44) / 32000),
    }) . "\n";
    splice @l, 0, @l - 100 if @l > 100;
    umask 077;
    open my $out, ">", "$f.$$" or die "$f.$$ : $!\n";
    print $out @l; close $out or die "$f.$$ : $!\n";
    rename "$f.$$", $f or die "$f : $!\n";
  ' "$HISTORIQUE" 2>>"$LOG" || log "historique : écriture impossible"
}

stop_and_transcribe() {
  # Verrou posé juste après la réclamation : un nouvel appui pendant la
  # transcription ne doit pas relancer une capture par-dessus.
  claim_capture || exit 0
  echo $$ >"$BUSY"
  trap 'rm -f "$BUSY"' EXIT
  stop_ffmpeg
  ding Pop
  printf 'transcribing' >"$STATUS"
  local t0; t0=$(now)

  [ -s "$WAV" ] || die "Aucun fichier audio produit"
  local bytes; bytes=$(stat -f%z "$WAV")
  [ "$bytes" -gt "$MIN_BYTES" ] || die "Trop court — parle un peu plus longtemps"

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

  local text rc
  text=$("$WHISPER_BIN" -m "$MODEL" -f "$WAV" -l "$LANGUAGE" \
           ${prompt_args[@]+"${prompt_args[@]}"} ${WHISPER_ARGS[@]+"${WHISPER_ARGS[@]}"} \
           --no-timestamps --no-prints 2>"$WHISPER_ERR")
  rc=$?
  text=$(printf '%s' "$text" | tr '\n' ' ' | sed -e 's/  */ /g' -e 's/^ *//' -e 's/ *$//')
  # Les ~40 lignes Metal/ggml de chaque dictée ne vont au journal qu'en cas d'échec.
  if [ "$rc" -ne 0 ] || ! has_speech "$text"; then
    log "whisper-cli (code $rc) :"; cat "$WHISPER_ERR" >>"$LOG" 2>/dev/null
  fi
  rm -f "$WHISPER_ERR"

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
  local pid='' bundle=''
  read -r pid bundle 2>/dev/null <"$TARGET"
  if [ -n "$pid" ] && ! kill -0 "$pid" 2>/dev/null; then
    log "app cible quittée ($bundle) : texte laissé dans le presse-papiers"
    notify "Texte copié — Cmd+V pour coller"
  else
    paste_into "$pid" "$bundle" || notify "Texte copié — Cmd+V pour coller"
  fi
  rm -f "$STATUS" "$TARGET"
  add_history "$text" "$bytes" "$bundle"   # après le collage : ne pas le retarder
}

# Annulation : on coupe l'écoute, rien n'est transcrit ni collé.
cancel_recording() {
  claim_capture || return 0
  stop_ffmpeg
  rm -f "$WAV" "$STATUS" "$TARGET"
  log "capture annulée"
  ding Funk
}

# Relâchement : seul un appui maintenu au-delà de HOLD_MS arrête la capture ;
# un appui bref la laisse tourner (mode bascule).
held_long_enough() {
  local t0; t0=$(cat "$STARTED" 2>/dev/null)
  [ -n "$t0" ] || return 1
  calc -v a="$t0" -v b="$(now)" -v h="$HOLD_MS" 'BEGIN { exit !((b - a) * 1000 >= h) }'
}

toggle() {
  if [ -f "$PID_FILE" ]; then
    stop_and_transcribe
  elif kill -0 "$(cat "$BUSY" 2>/dev/null)" 2>/dev/null; then
    log "appui ignoré : transcription en cours"
  else
    start_recording
  fi
}

case "${1:-toggle}" in
  toggle|press) toggle ;;
  expire)   # minuterie de start_recording : $2 pid ffmpeg, $3 horodatage
    if [ "$(cat "$PID_FILE" 2>/dev/null)" = "${2:-}" ] \
       && [ "$(cat "$STARTED" 2>/dev/null)" = "${3:-}" ]; then
      log "durée maximale atteinte (${MAX_SECONDS} s)"
      stop_and_transcribe
    fi ;;
  release)
    if [ -f "$PID_FILE" ] && held_long_enough; then
      stop_and_transcribe
    fi ;;
  cancel)
    if [ -f "$PID_FILE" ]; then
      cancel_recording
    fi ;;
  *) log "commande inconnue : $1"; exit 2 ;;
esac
