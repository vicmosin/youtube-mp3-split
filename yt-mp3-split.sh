#!/usr/bin/env bash
set -euo pipefail

URL="$1"
OUTDIR="${2:-output}"
AUDIO_FILE="audio.mp3"
META_FILE="metadata.json"

mkdir -p "$OUTDIR"

echo "📥 Получаем метаданные..."
yt-dlp -J "$URL" > "$META_FILE"

# --- 1️⃣ Проверяем наличие глав (chapters)
CHAPTERS_COUNT=$(jq '.chapters | length' "$META_FILE" 2>/dev/null || echo 0)

if [ "$CHAPTERS_COUNT" -gt 0 ]; then
  echo "✅ Найдены главы ($CHAPTERS_COUNT)."
  jq -r '.chapters[] | "\(.start_time)|\(.title)"' "$META_FILE" > chapters.txt
else
  echo "⚠️ Глав нет. Пытаемся достать таймкоды из описания..."
  DESCRIPTION=$(jq -r '.description' "$META_FILE")
  echo "$DESCRIPTION" | grep -Eo '([0-9]{1,2}:)?[0-9]{1,2}:[0-9]{2}.*' > chapters.txt || true
fi

if [ ! -s chapters.txt ]; then
  echo "❌ Не удалось найти таймкоды."
  exit 1
fi

ARTIST=$(jq -r '.uploader // .channel // "Unknown"' "$META_FILE")
ALBUM=$(jq -r '.title // "Unknown"' "$META_FILE")

echo "🎧 Скачиваем аудио..."
yt-dlp -f bestaudio -x --audio-format mp3 -o "$OUTDIR/$AUDIO_FILE" "$URL"

# --- 2️⃣ Формируем список таймкодов
mapfile -t LINES < chapters.txt
TOTAL=${#LINES[@]}

echo "✂️ Разбиваем аудио на $TOTAL треков..."
for ((i=0; i<$TOTAL; i++)); do
  line="${LINES[$i]}"

  if [[ "$line" =~ ^([0-9]+:[0-9:]+)[[:space:]]*(.*)$ ]]; then
    TIME="${BASH_REMATCH[1]}"
    TITLE="${BASH_REMATCH[2]}"
  elif [[ "$line" =~ ^([0-9.]+)\|(.*)$ ]]; then
    # формат из jq: seconds|title
    SECONDS="${BASH_REMATCH[1]}"
    TIME=$(printf '%02d:%02d:%02d' $((${SECONDS%.*}/3600)) $(((${SECONDS%.*}%3600)/60)) $((${SECONDS%.*}%60)))
    TITLE="${BASH_REMATCH[2]}"
  else
    continue
  fi

  NEXT_TIME=""
  if [ $((i+1)) -lt $TOTAL ]; then
    next_line="${LINES[$((i+1))]}"
    if [[ "$next_line" =~ ^([0-9]+:[0-9:]+) ]]; then
      NEXT_TIME="${BASH_REMATCH[1]}"
    elif [[ "$next_line" =~ ^([0-9.]+)\| ]]; then
      NEXT_SECONDS="${BASH_REMATCH[1]}"
      NEXT_TIME=$(printf '%02d:%02d:%02d' $((${NEXT_SECONDS%.*}/3600)) $(((${NEXT_SECONDS%.*}%3600)/60)) $((${NEXT_SECONDS%.*}%60)))
    fi
  fi

  # Очистим название для имени файла
  SAFE_TITLE=$(echo "$TITLE" | tr '/\\:*?"<>|' '_' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
  OUTFILE=$(printf "%s/%02d - %s.mp3" "$OUTDIR" $((i+1)) "$SAFE_TITLE")

  META_ARGS=(-metadata "artist=$ARTIST" -metadata "album=$ALBUM" -metadata "title=$TITLE" -id3v2_version 3)
  if [ -n "$NEXT_TIME" ]; then
    ffmpeg -loglevel error -y -i "$OUTDIR/$AUDIO_FILE" -ss "$TIME" -to "$NEXT_TIME" -c copy "${META_ARGS[@]}" "$OUTFILE"
  else
    ffmpeg -loglevel error -y -i "$OUTDIR/$AUDIO_FILE" -ss "$TIME" -c copy "${META_ARGS[@]}" "$OUTFILE"
  fi
  echo "🎶 $OUTFILE"
done

# --- 3️⃣ Генерируем плейлист для Apple Music
ABSDIR=$(cd "$OUTDIR" && pwd)
PLAYLIST="$OUTDIR/playlist.m3u8"
echo "#EXTM3U" > "$PLAYLIST"
for f in "$OUTDIR"/*.mp3; do
  [ "$(basename "$f")" = "$AUDIO_FILE" ] && continue
  DURATION=$(ffprobe -v error -show_entries format=duration -of csv=p=0 "$f" 2>/dev/null | cut -d. -f1)
  TITLE_TAG=$(ffprobe -v error -show_entries format_tags=title -of csv=p=0 "$f" 2>/dev/null)
  echo "#EXTINF:${DURATION:--1},${TITLE_TAG:-$(basename "$f" .mp3)}" >> "$PLAYLIST"
  echo "$ABSDIR/$(basename "$f")" >> "$PLAYLIST"
done
echo "📋 Плейлист: $PLAYLIST"

echo "🎉 Готово! Все треки сохранены в папке $OUTDIR"
