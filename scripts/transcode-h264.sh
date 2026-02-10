#!/usr/bin/env bash
set -euo pipefail

# Transcode a single video file to H.264+AAC MP4 (1080p max).

usage() {
  echo "Usage: $(basename "$0") <input> [output] [title]"
  echo "  input   - video file"
  echo "  output  - optional, defaults to <name>.mp4 in current directory"
  echo "  title   - optional, defaults to <name> <height>p (transcoded)"
  exit 1
}

err() {
  echo "error: $*" >&2
  exit 1
}

# --- main ---

[[ $# -lt 1 ]] && usage

command -v ffmpeg >/dev/null || err "ffmpeg not found"
command -v ffprobe >/dev/null || err "ffprobe not found"

INPUT="$1"
[[ -f "$INPUT" ]] || err "file not found: $INPUT"

BASENAME="${INPUT##*/}"
NAME="${BASENAME%.*}"
OUTPUT="${2:-./${NAME}.mp4}"

# Skip if already H.264+AAC ≤1080p
video_codec=$(ffprobe -v quiet -select_streams v:0 -show_entries stream=codec_name -of csv=p=0 "$INPUT" 2>/dev/null | head -1)
audio_codec=$(ffprobe -v quiet -select_streams a:0 -show_entries stream=codec_name -of csv=p=0 "$INPUT" 2>/dev/null | head -1)
height=$(ffprobe -v quiet -select_streams v:0 -show_entries stream=height -of csv=p=0 "$INPUT" 2>/dev/null | head -1)

if [[ "$video_codec" == "h264" && "$audio_codec" == "aac" && -n "$height" && "$height" -le 1080 ]]; then
  echo "skip: $BASENAME — already H.264+AAC ≤1080p"
  exit 0
fi

SOURCE_TITLE=$(ffprobe -v quiet -show_entries format_tags=title -of csv=p=0 "$INPUT" 2>/dev/null | head -1)
TITLE="${3:-${SOURCE_TITLE:-${NAME} ${height}p (transcoded)}}"

echo "transcode: $BASENAME → ${OUTPUT##*/} [${height}p]"

# Scale to 1080p max height, preserve aspect ratio, never upscale
ffmpeg -hide_banner -i "$INPUT" \
  -map 0:v:0 -map 0:a:0 \
  -c:v libx264 -crf 23 -preset medium \
  -vf "scale=-2:'min(1080,ih)'" \
  -c:a aac -b:a 128k -ac 2 \
  -c:s mov_text \
  -metadata title="$TITLE" \
  -movflags +faststart \
  -y "$OUTPUT"

echo "done: ${OUTPUT##*/} — title: $TITLE"
