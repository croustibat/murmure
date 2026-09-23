#!/bin/bash
# Banc d'essai des options de whisper-cli, avec les options réelles de Murmure
# (prompt de vocabulaire, --carry-initial-prompt, -l fr).
#
#   scripts/bench.sh [-n exécutions] [-c 'nom|options'] … audio.wav …
#
# Chaque configuration est un nom et des options ajoutées à la commande de base.
# Dans les options, @AC est remplacé par une fenêtre audio proportionnelle à la
# durée du fichier (voir audio_ctx) et @VAD par le chemin du modèle VAD.
# Les configurations sont entrelacées (A B C A B C…) pour que la charge du
# système pèse autant sur chacune ; on retient la médiane du temps réel, modèle
# chargé compris, puisque Murmure le recharge à chaque dictée.
# Si audio.txt existe à côté d'audio.wav, le taux d'erreur par mot (WER) de
# chaque transcription est calculé par rapport à ce texte de référence.
set -uo pipefail
export LC_ALL=C

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
MURMURE_HOME="${MURMURE_HOME:-$HOME/.local/share/murmure}"
WHISPER_BIN="${MURMURE_WHISPER:-/opt/homebrew/bin/whisper-cli}"
MODEL="${MURMURE_MODEL:-$MURMURE_HOME/models/ggml-large-v3-turbo-q5_0.bin}"
PROMPT_FILE="${MURMURE_PROMPT_FILE:-$ROOT/config/vocabulaire.txt}"
VAD_MODEL="${MURMURE_VAD_MODEL:-$MURMURE_HOME/models/ggml-silero-v5.1.2.bin}"
OUT="${BENCH_OUT:-$(mktemp -d /tmp/murmure-bench.XXXXXX)}"
RUNS=5

CONFIGS=()
while getopts 'n:c:' opt; do
  case $opt in
    n) RUNS=$OPTARG ;;
    c) CONFIGS+=("$OPTARG") ;;
    *) exit 2 ;;
  esac
done
shift $((OPTIND - 1))
[ $# -gt 0 ] || { echo "usage : $0 [-n exécutions] [-c 'nom|options'] audio.wav …" >&2; exit 2; }
[ ${#CONFIGS[@]} -gt 0 ] || CONFIGS=(
  'défaut|'
  'glouton|-bs 1 -bo 1'
  'beam 2|-bs 2 -bo 2'
  'no-fallback|-nf'
  'fenêtre|-ac @AC'
  'fenêtre 15 s|-ac 750'
  'threads 6|-t 6'
  'vad|--vad -vm @VAD'
)

now() { perl -MTime::HiRes=time -e 'printf "%.3f", time'; }
duration() { ffprobe -v error -show_entries format=duration -of csv=p=0 "$1"; }

# Fenêtre audio : 50 trames par seconde, plus une marge d'une seconde et demie.
audio_ctx() {
  awk -v d="$(duration "$1")" 'BEGIN { a = int(d * 50 + 0.999) + 75; print (a > 1500 ? 1500 : a) }'
}

# Taux d'erreur par mot, casse et ponctuation ignorées.
wer() {
  perl -CSA -Mutf8 -e '
    sub w { my $s = lc shift; $s =~ s/[^\w\x{2019}'"'"'-]+/ /g; split " ", $s }
    my @r = w($ARGV[0]); my @h = w($ARGV[1]);
    my @d = (0 .. @h);
    for my $i (1 .. @r) {
      my @n = ($i);
      for my $j (1 .. @h) {
        my $c = $d[$j-1] + ($r[$i-1] eq $h[$j-1] ? 0 : 1);
        $n[$j] = (sort { $a <=> $b } $c, $d[$j] + 1, $n[$j-1] + 1)[0];
      }
      @d = @n;
    }
    printf "%.1f", @r ? 100 * $d[-1] / @r : 0' "$1" "$2"
}

prompt=$(tr -d '\n' <"$PROMPT_FILE")
mkdir -p "$OUT"
RAW="$OUT/mesures.tsv"
: >"$RAW"
echo "résultats dans $OUT" >&2

for run in $(seq 1 "$RUNS"); do
  for wav in "$@"; do
    ac=$(audio_ctx "$wav")
    for i in "${!CONFIGS[@]}"; do
      name=${CONFIGS[$i]%%|*}
      opts=${CONFIGS[$i]#*|}
      opts=${opts//@AC/$ac}
      opts=${opts//@VAD/$VAD_MODEL}
      t0=$(now)
      # shellcheck disable=SC2086 # options découpées volontairement
      text=$("$WHISPER_BIN" -m "$MODEL" -f "$wav" -l fr \
               --prompt "$prompt" --carry-initial-prompt \
               --no-timestamps --no-prints $opts 2>/dev/null)
      t1=$(now)
      text=$(printf '%s' "$text" | tr '\n' ' ' | sed -e 's/  */ /g' -e 's/^ *//' -e 's/ *$//')
      ref="${wav%.wav}.txt"
      w=-; [ -f "$ref" ] && w=$(wer "$(cat "$ref")" "$text")
      elapsed=$(awk -v a="$t0" -v b="$t1" 'BEGIN { printf "%.3f", b - a }')
      printf '%s\t%s\t%s\t%s\t%s\t%s\n' "$run" "$(basename "$wav")" "$i" "$elapsed" "$w" "$text" >>"$RAW"
      printf '%d/%d  %-12s %-12s %6ss  WER %s%%\n' "$run" "$RUNS" "$(basename "$wav")" "$name" "$elapsed" "$w" >&2
    done
  done
done

# Synthèse : médiane par fichier et configuration, gain relatif à la première.
names=$(printf '%s\n' "${CONFIGS[@]}" | cut -d'|' -f1)
perl -CSDA -Mutf8 -F'\t' -lane '
  BEGIN { @names = split /\n/, shift @ARGV }
  push @{$t{$F[1]}{$F[2]}}, $F[3]; push @{$w{$F[1]}{$F[2]}}, $F[4];
  $txt{$F[1]}{$F[2]}{$F[5]}++; $files{$F[1]} = 1;
  sub med { my @s = sort { $a <=> $b } @_; my $n = @s;
            $n % 2 ? $s[$n/2] : ($s[$n/2-1] + $s[$n/2]) / 2 }
  END {
    for my $f (sort keys %files) {
      print "\n### $f\n";
      print "| configuration | médiane | gain | WER médian | transcriptions distinctes |";
      print "|---|---:|---:|---:|---:|";
      my $ref = med(@{$t{$f}{0}});
      for my $i (0 .. $#names) {
        next unless $t{$f}{$i};
        my $m = med(@{$t{$f}{$i}});
        my @ws = grep { $_ ne "-" } @{$w{$f}{$i}};
        printf "| %s | %.2f s | %+.0f %% | %s | %d |\n", $names[$i], $m,
          100 * ($ref - $m) / $ref, @ws ? sprintf("%.1f %%", med(@ws)) : "-",
          scalar keys %{$txt{$f}{$i}};
      }
      print "\n<details><summary>Transcriptions</summary>\n";
      for my $i (0 .. $#names) {
        for my $x (sort keys %{$txt{$f}{$i}}) { print "- **$names[$i]** : $x" }
      }
      print "\n</details>";
    }
  }' "$names" "$RAW" | tee "$OUT/synthese.md"
