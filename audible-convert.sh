#!/usr/bin/env zsh

if [ -z "$(which ffmpeg)" ] || [ -z "$(which audible)" ] || [ -z "$(which jq)" ]; then
    echo "Error: Needs ffmpeg, audible-cli and jq installed"
fi

if [[ "$1" == "--profile" ]]; then
  asin="$3"
  ext="${4:-}"
  cmd=(audible --profile "$2")

  if [[ -z "$2" || -z "$3" ]]; then
    echo "Usage: ./convert.sh [--profile <name>] <ASIN> [--aax]"
    if [[ -z "$2" ]]; then
      audible library list
    else
      "${cmd[@]}" library list
    fi
    exit 1
  fi

  if [[ -n "$ext" && "$ext" != "--aax" ]]; then
    echo "Usage: ./convert.sh [--profile <name>] <ASIN> [--aax]"
    exit 1
  fi
else
  asin="$1"
  ext="${2:-}"
  cmd=(audible)

  if [[ -z "$1" ]]; then
    echo "Usage: ./convert.sh [--profile <name>] <ASIN> [--aax]"
    "${cmd[@]}" library list
    exit 1
  fi

  if [[ -n "$ext" && "$ext" != "--aax" ]]; then
    echo "Usage: ./convert.sh [--profile <name>] <ASIN> [--aax]"
    exit 1
  fi
fi

set -euo pipefail

dir="$PWD/$asin"
mkdir -p "$dir"

if [ "$ext" == "--aax" ]; then
  aax="--aax-fallback"
else
  aax="--aaxc"
fi

"${cmd[@]}" download -a "$asin" "$aax" --cover --cover-size 1215 --chapter -o "$dir"

chapters_json=$(find "$dir" -maxdepth 1 -name "*-chapters.json" -print -quit 2>/dev/null)
if [[ -z "$chapters_json" ]]; then
  echo "Error: could not find *-chapters.json in $dir"
  exit 1
fi
item_name="${chapters_json##*/}"
item_name="${item_name%-chapters.json}"
outFile="$dir/$item_name.mp3"

info=$("${cmd[@]}" api -p response_groups="media,contributors,series,category_ladders" /1.0/library/"$asin" | jq '.item')

chapter_txt="$dir/chapters.txt"
series_info=$(echo "$info" | jq '.series | if (length > 0) then sort_by(.sequence | if . != "" then tonumber else 0 end) | .[-1] else "" end')

typeset -a decrypt
key=""
voucher=$(find "$dir" -maxdepth 1 -name "*.voucher" -print -quit 2>/dev/null)
if [[ -n "$voucher" ]]; then
  echo "Preparing to decrypt aacx file"
  key=$(jq -r '.content_license.license_response.key' < "$voucher")
  iv=$(jq -r '.content_license.license_response.iv' < "$voucher")
  decrypt=(-audible_key "$key" -audible_iv "$iv")
fi
if [ -z "$key" ]; then
  echo "Preparing to decrypt aax file"
  decrypt=(-activation_bytes "$("${cmd[@]}" activation-bytes)")
fi
echo "${decrypt[@]}"

aax_file=$(find "$dir" -maxdepth 1 \( -name "*.aax" -o -name "*.aaxc" \) -print -quit 2>/dev/null)
jpg_file=$(find "$dir" -maxdepth 1 -name "*.jpg" -print -quit 2>/dev/null)
copyright=$(ffprobe "${decrypt[@]}" "$aax_file" 2>&1 | grep copyright | sed 's/^.*: //')

# Write book metadata
echo ";FFMETADATA1
title=$(echo "$info" | jq -r '.title')
artist=$(echo "$info" | jq -r '.authors | [.[].name] | join(", ")')
composer=$(echo "$info" | jq -r '.narrators | [.[].name] | join(", ")')
year=$(echo "$info" | jq -r '.release_date | sub("-[0-9][0-9]-[0-9][0-9]"; "")')
copyright=$copyright
language=$(echo "$info" | jq -r '.language')
description=$(echo "$info" | jq -r '.merchandising_summary | sub("</?[a-z]+>"; ""; "g")')
asin=$asin
" > "$chapter_txt"

if [ "$series_info" != '""' ]; then
    echo "series=$(echo "$series_info" | jq -r '.title')
series-part=$(echo "$series_info" | jq -r '.sequence')
" >> "$chapter_txt"
fi

# Write chapter timestamps to txt
json_file="$chapters_json"
jq -r 'def flat:
  reduce .[] as $c ([]; if $c.chapters? then .+[$c | del(.chapters)]+[$c.chapters | flat] else .+[$c] end) | flatten;
    .content_metadata.chapter_info.chapters
    | flat
    | .[] |
"[CHAPTER]
TIMEBASE=1/1000
START=\((.start_offset_ms))
END=\((.start_offset_ms + .length_ms))
title=\((.title))
"' < "$json_file" >> "$chapter_txt"

# We reencode the file because some players have problems with the way audible encodes their files
# the ffmpeg reencode "cleans up" the file
ffmpeg "${decrypt[@]}" \
    -i "$aax_file" -i "$jpg_file" -i "$chapter_txt" \
    -map 0:a -map 1:v -map_metadata 2 -map_chapters 2 -c:v copy \
    -c:a libmp3lame \
    -id3v2_version 3 \
    -disposition:v attached_pic -movflags +faststart -movflags +use_metadata_tags \
    -metadata:s:v title="Album cover" -metadata:s:v comment="Cover (front)" \
    -metadata:s:a language="$(echo "$info" | jq -r '.language.[0:3]')" \
    "$outFile"
