# Scripts

Local utility scripts.

## transcode-h264.sh

Transcode a single video file to H.264+AAC MP4 (1080p max) to avoid runtime transcoding on Pi 5. Skips files already in the target format.

```bash
# Default output: ./movie.mp4
./scripts/transcode-h264.sh movie.mkv

# Custom output path
./scripts/transcode-h264.sh movie.mkv ~/output/movie.mp4

# Custom title (default: source title or "<name> <height>p (transcoded)")
./scripts/transcode-h264.sh movie.mkv ./movie.mp4 "My Movie"
```

**Encoding settings:** H.264 CRF 23, medium preset, AAC 128k stereo, max 1080p (no upscale), faststart.

## ffmpeg/ffprobe Cheat Sheet

### Inspect a file

```bash
# Full stream info (codecs, resolution, bitrate, duration)
ffprobe -hide_banner movie.mkv

# Just video codec and resolution
ffprobe -v quiet -select_streams v:0 \
  -show_entries stream=codec_name,width,height,bit_rate \
  -of default=noprint_wrappers=1 movie.mkv

# Just audio codec and channels
ffprobe -v quiet -select_streams a:0 \
  -show_entries stream=codec_name,channels,sample_rate,bit_rate \
  -of default=noprint_wrappers=1 movie.mkv

# Container format and duration
ffprobe -v quiet -show_entries format=format_name,duration,size,bit_rate \
  -of default=noprint_wrappers=1 movie.mkv

# JSON output (useful for scripting)
ffprobe -v quiet -print_format json -show_streams -show_format movie.mkv
```

### Transcode

```bash
# H.264+AAC MP4, 1080p max, good quality
ffmpeg -i input.mkv \
  -c:v libx264 -crf 23 -preset medium \
  -vf "scale=-2:'min(1080,ih)'" \
  -c:a aac -b:a 128k -ac 2 \
  -movflags +faststart \
  output.mp4

# Same but faster (lower quality)
ffmpeg -i input.mkv \
  -c:v libx264 -crf 23 -preset fast \
  -vf "scale=-2:'min(1080,ih)'" \
  -c:a aac -b:a 128k -ac 2 \
  -movflags +faststart \
  output.mp4

# Higher quality (slower, larger file)
ffmpeg -i input.mkv \
  -c:v libx264 -crf 18 -preset slow \
  -vf "scale=-2:'min(1080,ih)'" \
  -c:a aac -b:a 192k -ac 2 \
  -movflags +faststart \
  output.mp4

# 720p instead of 1080p (smaller files)
ffmpeg -i input.mkv \
  -c:v libx264 -crf 23 -preset medium \
  -vf "scale=-2:'min(720,ih)'" \
  -c:a aac -b:a 128k -ac 2 \
  -movflags +faststart \
  output.mp4
```

### Remux (change container, no re-encoding)

```bash
# MKV → MP4 (just repackages, instant)
ffmpeg -i movie.mkv -c copy movie.mp4

# Fix MP4 for streaming (move metadata to front)
ffmpeg -i movie.mp4 -c copy -movflags +faststart fixed.mp4
```

### Extract streams

```bash
# Extract audio only
ffmpeg -i movie.mkv -vn -c:a copy audio.aac

# Extract video only (no audio)
ffmpeg -i movie.mkv -an -c:v copy video.h264

# Extract subtitles
ffmpeg -i movie.mkv -map 0:s:0 subs.srt
```

### Quick checks

```bash
# List all streams (video, audio, subtitle)
ffprobe -v quiet -show_entries stream=index,codec_type,codec_name,width,height \
  -of csv=p=0 movie.mkv

# Check if a file will direct play on Jellyfin (H.264+AAC in MP4)
ffprobe -v quiet -select_streams v:0 -show_entries stream=codec_name -of csv=p=0 movie.mp4
# → should print "h264"

ffprobe -v quiet -select_streams a:0 -show_entries stream=codec_name -of csv=p=0 movie.mp4
# → should print "aac"

# Batch check a directory
for f in *.mp4 *.mkv; do
  vc=$(ffprobe -v quiet -select_streams v:0 -show_entries stream=codec_name -of csv=p=0 "$f" 2>/dev/null)
  ac=$(ffprobe -v quiet -select_streams a:0 -show_entries stream=codec_name -of csv=p=0 "$f" 2>/dev/null)
  echo "$f: video=$vc audio=$ac"
done
```

### CRF reference

| CRF | Quality | Use case |
|-----|---------|----------|
| 18 | Visually lossless | Archival, high quality |
| 23 | Good (default) | General use, good size/quality balance |
| 28 | Acceptable | Smaller files, less critical content |
| 51 | Worst | Don't |
