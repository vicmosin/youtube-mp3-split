# youtube-mp3-split

Download a YouTube video and split it into individual MP3 tracks using chapters or timestamps from the description.

## Requirements

- [yt-dlp](https://github.com/yt-dlp/yt-dlp)
- [ffmpeg](https://ffmpeg.org/)
- [jq](https://jqlang.github.io/jq/)

## Usage

```bash
./yt-mp3-split.sh <youtube-url> [output-directory]
```

- `youtube-url` — link to the YouTube video
- `output-directory` — where to save the tracks (default: `output`)

### Example

```bash
./yt-mp3-split.sh "https://www.youtube.com/watch?v=XXXXX"
./yt-mp3-split.sh "https://www.youtube.com/watch?v=XXXXX" my-tracks
```

## How it works

1. Fetches video metadata via `yt-dlp`
2. Extracts track timestamps from chapters (or falls back to the video description)
3. Downloads the audio as MP3
4. Splits it into individual tracks using `ffmpeg`
5. Tags each MP3 with artist, album, and title metadata
