# make-reel.sh

Schneidet die Clips aus `clips/` in Dateinamen-Reihenfolge zu einem Reel
zusammen. Braucht `ffmpeg` (im Container per `apt-get install -y ffmpeg`).

## Schnellstart

`tools/reel.sh` enthaelt die abgestimmten Einstellungen fuer dieses Reel
(9:16 hochkant, mittiger Crop, max. 4 s pro Clip, 0,5 s Crossfade, 0,5 s
Ein-/Ausblenden, Originalton). Clips nach `clips/` legen, dann:

    tools/reel.sh

Zusaetzliche Optionen werden durchgereicht, z.B. `tools/reel.sh --music song.m4a`.

## Weitere Beispiele

    # Alles in voller Laenge, harte Schnitte
    tools/make-reel.sh --aspect 9:16 --fit cover

    # Schnelles Reel-Tempo: jeder Clip max. 3s, weiche Uebergaenge, Blenden
    tools/make-reel.sh --aspect 9:16 --fit cover --max-dur 3 --xfade 0.4 --fade 0.5

    # Querformat-Clips ohne Bildverlust, weichgezeichnete Balken statt Crop
    tools/make-reel.sh --aspect 9:16 --fit blur

    # Mit eigener Musik statt Originalton (wird auf Videolaenge geloopt/getrimmt)
    tools/make-reel.sh --aspect 9:16 --fit cover --music musik.m4a --fade 0.5

## Optionen

| Option | Wirkung |
|---|---|
| `--in DIR` | Clip-Ordner, Standard `clips` |
| `--out FILE` | Ausgabedatei, Standard `build/reel.mp4` |
| `--aspect A` | `9:16` (1080x1920), `16:9` (1920x1080), `1:1` (1080x1080) |
| `--fit MODE` | `cover` beschneidet mittig · `contain` schwarze Balken · `blur` weiche Balken |
| `--max-dur S` | kuerzt jeden Clip auf S Sekunden (schneidet ab Clip-Anfang) |
| `--xfade S` | Crossfade-Dauer; ohne die Option harte Schnitte |
| `--fade S` | Ein-/Ausblenden aus/nach Schwarz |
| `--music FILE` | ersetzt den Originalton |
| `--fps N` | Bildrate, Standard 30 |

## Wie es arbeitet

1. **Normalisieren** — jeder Clip wird einzeln auf dieselbe Aufloesung, Bildrate,
   SAR und dasselbe Audioformat (48 kHz stereo AAC) gebracht. Stumme Clips
   bekommen eine Stille-Tonspur, sonst brechen `concat` und `xfade`.
2. **Zusammenfuegen** — harte Schnitte per `concat`-Demuxer ohne Neukodierung,
   Crossfades per `xfade`/`acrossfade` mit fortlaufend berechneten Offsets.
3. **Nachbearbeiten** — Blenden und Musikspur, `+faststart` fuers Web.

## Getestet

Gegen generierte Clips in 1920x1080, 1080x1920, 720x720 und 640x480 mit
24/25/30 fps, davon einer ohne Tonspur. Geprueft: Reihenfolge (`10` nach `3`),
Gesamtlaengen (harte Schnitte 18,07 s; mit 0,4 s Crossfade 10,79 s = 4x3s - 3x0,4s),
durchgehender Musikpegel ueber die volle Laenge bei nur 4 s langer Quelldatei,
sowie Blenden und Blur-Balken per Kontaktbogen.
