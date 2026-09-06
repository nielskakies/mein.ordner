#!/usr/bin/env bash
# make-reel.sh - schneidet die Clips aus einem Ordner zu einem Reel zusammen.
# Die Reihenfolge ergibt sich aus der natuerlichen Sortierung der Dateinamen
# (01_..., 02_..., 10_...), daher unbedingt durchnummerieren.
set -euo pipefail

IN_DIR="clips"
OUT="build/reel.mp4"
ASPECT="9:16"        # 9:16 | 16:9 | 1:1
FIT="cover"          # cover (beschneiden) | contain (schwarze Balken) | blur (weiche Balken)
MAXDUR=""            # z.B. 3 -> jeder Clip auf max. 3s gekuerzt
XFADE=""             # z.B. 0.4 -> Crossfade-Dauer in Sekunden, leer = harte Schnitte
FADE=""              # z.B. 0.5 -> Ein-/Ausblenden aus/nach Schwarz
MUSIC=""             # Pfad zu einer Audiodatei, ersetzt den Originalton
FPS=30

usage() {
  sed -n '2,4p' "$0"
  cat <<EOF

  --in DIR        Clip-Ordner (Standard: $IN_DIR)
  --out FILE      Ausgabedatei (Standard: $OUT)
  --aspect A      9:16 | 16:9 | 1:1 (Standard: $ASPECT)
  --fit MODE      cover | contain | blur (Standard: $FIT)
  --max-dur S     jeden Clip auf S Sekunden kuerzen
  --xfade S       Crossfade-Dauer in Sekunden
  --fade S        Ein-/Ausblenden am Anfang und Ende
  --music FILE    Musik statt Originalton
  --fps N         Bildrate (Standard: $FPS)
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --in) IN_DIR="$2"; shift 2 ;;
    --out) OUT="$2"; shift 2 ;;
    --aspect) ASPECT="$2"; shift 2 ;;
    --fit) FIT="$2"; shift 2 ;;
    --max-dur) MAXDUR="$2"; shift 2 ;;
    --xfade) XFADE="$2"; shift 2 ;;
    --fade) FADE="$2"; shift 2 ;;
    --music) MUSIC="$2"; shift 2 ;;
    --fps) FPS="$2"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unbekannte Option: $1" >&2; usage; exit 1 ;;
  esac
done

case "$ASPECT" in
  9:16) W=1080; H=1920 ;;
  16:9) W=1920; H=1080 ;;
  1:1)  W=1080; H=1080 ;;
  *) echo "Unbekanntes Seitenverhaeltnis: $ASPECT" >&2; exit 1 ;;
esac

command -v ffmpeg >/dev/null || { echo "ffmpeg fehlt" >&2; exit 1; }
[[ -d "$IN_DIR" ]] || { echo "Ordner '$IN_DIR' existiert nicht" >&2; exit 1; }

# --- Clips einsammeln, natuerlich sortiert -----------------------------------
mapfile -t CLIPS < <(
  find "$IN_DIR" -maxdepth 1 -type f \
    \( -iname '*.mp4' -o -iname '*.mov' -o -iname '*.m4v' -o -iname '*.avi' \
       -o -iname '*.mkv' -o -iname '*.webm' -o -iname '*.mts' -o -iname '*.3gp' \) \
    -printf '%f\n' | sort -V | sed "s|^|$IN_DIR/|"
)
N=${#CLIPS[@]}
[[ $N -gt 0 ]] || { echo "Keine Videodateien in '$IN_DIR' gefunden" >&2; exit 1; }

echo "Reihenfolge ($N Clips):"
for i in "${!CLIPS[@]}"; do printf '  %2d. %s\n' "$((i+1))" "${CLIPS[$i]}"; done

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$(dirname "$OUT")"

# --- Skalierungs-Filter je nach Fit-Modus ------------------------------------
case "$FIT" in
  cover)
    VF="scale=${W}:${H}:force_original_aspect_ratio=increase,crop=${W}:${H}" ;;
  contain)
    VF="scale=${W}:${H}:force_original_aspect_ratio=decrease,pad=${W}:${H}:(ow-iw)/2:(oh-ih)/2:black" ;;
  blur)
    VF="split=2[bg][fg];[bg]scale=${W}:${H}:force_original_aspect_ratio=increase,crop=${W}:${H},gblur=sigma=30[bgb];[fg]scale=${W}:${H}:force_original_aspect_ratio=decrease[fgs];[bgb][fgs]overlay=(W-w)/2:(H-h)/2" ;;
  *) echo "Unbekannter Fit-Modus: $FIT" >&2; exit 1 ;;
esac
VF="${VF},fps=${FPS},setsar=1,format=yuv420p"

# --- Schritt 1: jeden Clip auf ein gemeinsames Format normalisieren ----------
echo
echo "Normalisiere auf ${W}x${H} @ ${FPS}fps (${FIT}) ..."
NORM=()
for i in "${!CLIPS[@]}"; do
  src="${CLIPS[$i]}"
  dst="$TMP/$(printf '%04d' "$i").mp4"
  has_audio=$(ffprobe -v error -select_streams a -show_entries stream=index \
                -of csv=p=0 "$src" | head -1)
  args=(-y -v error)
  [[ -n "$MAXDUR" ]] && args+=(-t "$MAXDUR")
  args+=(-i "$src")
  if [[ -z "$has_audio" ]]; then
    # Stummer Clip: Stilletonspur ergaenzen, damit concat/xfade konsistent bleibt
    args+=(-f lavfi -i anullsrc=channel_layout=stereo:sample_rate=48000
           -shortest -map 0:v:0 -map 1:a:0)
  else
    args+=(-map 0:v:0 -map 0:a:0)
  fi
  args+=(-vf "$VF" -c:v libx264 -preset medium -crf 20 -pix_fmt yuv420p
         -c:a aac -b:a 192k -ar 48000 -ac 2 -video_track_timescale 90000 "$dst")
  ffmpeg "${args[@]}"
  NORM+=("$dst")
  printf '  [%2d/%2d] %s\n' "$((i+1))" "$N" "$(basename "$src")"
done

dur_of() { ffprobe -v error -show_entries format=duration -of csv=p=0 "$1"; }

# --- Schritt 2: aneinanderreihen --------------------------------------------
JOINED="$TMP/joined.mp4"
if [[ -n "$XFADE" && $N -gt 1 ]]; then
  echo "Fuege mit ${XFADE}s Crossfade zusammen ..."
  inputs=(); fc=""; vprev="0:v"; aprev="0:a"; acc=""
  for f in "${NORM[@]}"; do inputs+=(-i "$f"); done
  acc=$(dur_of "${NORM[0]}")
  for ((i=1; i<N; i++)); do
    off=$(awk -v a="$acc" -v d="$XFADE" 'BEGIN{printf "%.4f", a-d}')
    fc+="[${vprev}][${i}:v]xfade=transition=fade:duration=${XFADE}:offset=${off}[v${i}];"
    fc+="[${aprev}][${i}:a]acrossfade=d=${XFADE}[a${i}];"
    vprev="v${i}"; aprev="a${i}"
    acc=$(awk -v a="$acc" -v n="$(dur_of "${NORM[$i]}")" -v d="$XFADE" \
              'BEGIN{printf "%.4f", a+n-d}')
  done
  fc="${fc%;}"
  ffmpeg -y -v error "${inputs[@]}" -filter_complex "$fc" \
    -map "[${vprev}]" -map "[${aprev}]" \
    -c:v libx264 -preset medium -crf 20 -pix_fmt yuv420p \
    -c:a aac -b:a 192k -ar 48000 -ac 2 "$JOINED"
else
  echo "Fuege mit harten Schnitten zusammen ..."
  : > "$TMP/list.txt"
  for f in "${NORM[@]}"; do printf "file '%s'\n" "$f" >> "$TMP/list.txt"; done
  ffmpeg -y -v error -f concat -safe 0 -i "$TMP/list.txt" -c copy "$JOINED"
fi

TOTAL=$(dur_of "$JOINED")
printf 'Gesamtlaenge: %.2f s\n' "$TOTAL"

# --- Schritt 3: Musik und Blenden --------------------------------------------
post_v=""; post_a=""
if [[ -n "$FADE" ]]; then
  out_start=$(awk -v t="$TOTAL" -v f="$FADE" 'BEGIN{printf "%.4f", t-f}')
  post_v="fade=t=in:st=0:d=${FADE},fade=t=out:st=${out_start}:d=${FADE}"
  post_a="afade=t=in:st=0:d=${FADE},afade=t=out:st=${out_start}:d=${FADE}"
fi

if [[ -n "$MUSIC" ]]; then
  [[ -f "$MUSIC" ]] || { echo "Musikdatei '$MUSIC' nicht gefunden" >&2; exit 1; }
  echo "Lege Musikspur an (Originalton wird ersetzt) ..."
  # Musik ggf. loopen, dann exakt auf die Videolaenge trimmen
  af="atrim=0:${TOTAL},asetpts=N/SR/TB,aresample=48000"
  [[ -n "$post_a" ]] && af="${af},${post_a}"
  ffmpeg -y -v error -i "$JOINED" -stream_loop -1 -i "$MUSIC" \
    -filter_complex "[0:v]${post_v:-null}[v];[1:a]${af}[a]" \
    -map "[v]" -map "[a]" -t "$TOTAL" \
    -c:v libx264 -preset medium -crf 20 -pix_fmt yuv420p \
    -c:a aac -b:a 192k -ar 48000 -ac 2 -movflags +faststart "$OUT"
elif [[ -n "$FADE" ]]; then
  ffmpeg -y -v error -i "$JOINED" -vf "$post_v" -af "$post_a" \
    -c:v libx264 -preset medium -crf 20 -pix_fmt yuv420p \
    -c:a aac -b:a 192k -ar 48000 -ac 2 -movflags +faststart "$OUT"
else
  ffmpeg -y -v error -i "$JOINED" -c copy -movflags +faststart "$OUT"
fi

echo
echo "Fertig: $OUT"
ffprobe -v error -show_entries format=duration,size \
  -show_entries stream=codec_type,codec_name,width,height,r_frame_rate \
  -of default=noprint_wrappers=1 "$OUT"
