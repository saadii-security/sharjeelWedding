#!/bin/bash
# Checks the invitation still says what the printed card says, and that the
# assets still line up with the original animation.
#
# Two things can break silently here:
#  1. assets/final.jpg must be the SAME image as the last frame of invite.mp4,
#     or the ending visibly jumps when the still fades in over the video.
#  2. A date, time, venue or phone number gets edited and no longer matches the
#     card -- including the <time datetime> values, which nobody reads by eye.
set -u
cd "$(dirname "$0")"

SRC="Generatedvideo1-ezgif.com-video-to-jxl-converter.jxl"
fail=0
ok(){  printf '  ok    %s\n' "$1"; }
bad(){ printf '  FAIL  %s\n' "$1"; fail=1; }
has(){ grep -qF -- "$1" index.html && ok "$1" || bad "missing: $1"; }

echo "assets present"
for f in index.html assets/invite.mp4 assets/final.jpg assets/poster.jpg \
         assets/flora-1.jpg assets/flora-2.jpg; do
  [ -s "$f" ] && ok "$f" || bad "$f missing or empty"
done

echo "index.html wiring"
for f in assets/invite.mp4 assets/final.jpg assets/poster.jpg \
         assets/flora-1.jpg assets/flora-2.jpg; do
  grep -qF "$f" index.html && ok "references $f" || bad "does not reference $f"
done

echo "floral decoration"
n_flora=$(grep -c 'class="flora ' index.html)
[ "$n_flora" -eq 6 ] && ok "6 floral pieces" || bad "expected 6 floral pieces, found $n_flora"
# Decoration must never be announced to screen readers or swallow taps.
[ "$(grep -c 'class="flora .*aria-hidden="true"' index.html)" -eq 6 ] \
  && ok "all decoration aria-hidden" || bad "some floral pieces are not aria-hidden"
grep -q 'pointer-events:none' index.html && ok "decoration ignores taps" || bad "decoration may block taps"

echo "tap-to-play and scroll gate"
grep -q 'class="locked"'            index.html && ok "starts scroll-locked"    || bad "page does not start locked"
grep -q "classList.remove('locked')" index.html && ok "unlocks after the film"  || bad "never unlocks scrolling"
grep -q 'id="details" inert'        index.html && ok "details start inert"     || bad "details not inert at start"
grep -q "removeAttribute('inert')"  index.html && ok "details become reachable" || bad "details never un-inert"
grep -q "addEventListener('ended'"  index.html && ok "listens for film end"    || bad "no ended handler"

echo "music"
[ -s assets/music.mp3 ] && ok "assets/music.mp3" || bad "assets/music.mp3 missing or empty"
grep -qF 'assets/music.mp3' index.html && ok "referenced" || bad "not referenced in index.html"
grep -q 'id="music"[^>]*loop'  index.html && ok "loops"            || bad "audio is not set to loop"
grep -q 'music.play()'         index.html && ok "starts on the tap" || bad "music is never started"
grep -q 'id="mute"'            index.html && ok "mute control"     || bad "no mute control"
grep -q 'aria-pressed'         index.html && ok "exposes pressed state" || bad "mute missing aria-pressed"
# Background level: audible under the film, not competing with conversation.
V=$(sed -n 's/.*VOLUME *= *\([0-9.]*\).*/\1/p' index.html | head -1)
if [ -n "$V" ] && awk -v v="$V" 'BEGIN{exit !(v>0 && v<=0.6)}'; then
  ok "volume $V is a background level"
else
  bad "volume '${V:-unset}' is not a quiet background level"
fi
# Regression guard: a timed volume ramp needs requestAnimationFrame, which
# stalls in a hidden tab and once left the music playing at volume 0.
if grep -qF 'requestAnimationFrame(' index.html; then
  bad "volume ramp via requestAnimationFrame can stall and play silently"
else
  ok "no requestAnimationFrame volume ramp"
fi

echo "couple"
has "Sharjeel"
has "Nozaina"

echo "invitation details (must match the printed card)"
has "Sharjeel Mustafa Shahid"
has "Shahid Hussain"
has "Muhammad Saddique"
has "Tail / Mehndi Ceremony"
has "Friday, 18th December 2026"
has "Barat Departure"
has "Saturday, 19th December 2026"
has "House No. 9, Street No. 11"
has "Al Madina Colony"
has "Walima Ceremony"
has "Sunday, 20th December 2026"
has "Khan Forte Marriage Hall"
has "Tajpura, Lahore"
has "Allah Rakha"
has "Muhammad Shahzad"
has "Saad Ali"
has "0335-4655980"
has "0300-4579779"

echo "each <time> agrees with the weekday and clock time printed beside it"
n_times=0
while IFS= read -r el; do
  n_times=$((n_times+1))
  dt=$(printf '%s' "$el" | sed -n 's/.*datetime="\([^"]*\)".*/\1/p')
  txt=$(printf '%s' "$el" | sed -e 's/<[^>]*>/ /g' -e 's/  */ /g')
  day=${dt%%T*}
  hm=${dt#*T}; hh=${hm%%:*}
  want_day=$(date -j -f "%Y-%m-%d" "$day" "+%A" 2>/dev/null)
  h12=$(( 10#$hh % 12 )); [ "$h12" -eq 0 ] && h12=12
  if [ "$(( 10#$hh ))" -ge 12 ]; then ampm=PM; else ampm=AM; fi

  case "$txt" in
    *"$want_day"*) ok "$day is $want_day" ;;
    *) bad "$dt says $want_day, text reads:$txt" ;;
  esac
  case "$txt" in
    *"$h12:${hm#*:} $ampm"*) ok "$dt = $h12:${hm#*:} $ampm" ;;
    *) bad "$dt should read $h12:${hm#*:} $ampm, text reads:$txt" ;;
  esac
done < <(grep -o '<time[^>]*>.*</time>' index.html)
[ "$n_times" -eq 3 ] && ok "3 ceremonies" || bad "expected 3 <time> ceremonies, found $n_times"

echo "phone links are dialable"
for t in "tel:+923354655980" "tel:+923004579779"; do
  grep -qF "$t" index.html && ok "$t" || bad "missing link $t"
done

echo "video matches the source animation"
read -r W H N DUR <<<"$(ffprobe -v error \
  -select_streams v:0 -count_frames \
  -show_entries stream=width,height,nb_read_frames \
  -show_entries format=duration \
  -of default=nw=1:nk=1 assets/invite.mp4 | paste -sd' ' -)"
[ "$W" = 720 ] && [ "$H" = 1280 ] && ok "720x1280" || bad "expected 720x1280, got ${W}x${H}"
[ "$N" = 192 ] && ok "192 frames" || bad "expected 192 frames, got $N"
# 192 frames * 42ms = 8.064s
case "$DUR" in 8.0[5-7]*) ok "duration ${DUR}s" ;; *) bad "expected ~8.064s, got ${DUR}s" ;; esac

if [ -f "$SRC" ] && command -v jxlinfo >/dev/null 2>&1; then
  SN=$(jxlinfo -v "$SRC" 2>/dev/null | grep -c '^Frame:')
  [ "$SN" = "$N" ] && ok "matches source frame count ($SN)" \
                   || bad "source has $SN frames, mp4 has $N"
fi

echo "final.jpg is the video's last frame"
tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
ffmpeg -v error -y -sseof -0.2 -i assets/invite.mp4 \
  -fps_mode passthrough -update 1 "$tmp/last.png" 2>/dev/null
if [ ! -s "$tmp/last.png" ]; then
  bad "could not extract last frame from invite.mp4"
else
  SSIM=$(ffmpeg -v error -i "$tmp/last.png" -i assets/final.jpg \
           -lavfi "ssim=stats_file=-" -f null - 2>/dev/null \
         | sed -n 's/.*All:\([0-9.]*\).*/\1/p' | head -1)
  if [ -z "$SSIM" ]; then
    bad "SSIM comparison produced no result"
  elif awk -v s="$SSIM" 'BEGIN{exit !(s>0.95)}'; then
    ok "SSIM $SSIM vs last frame"
  else
    bad "final.jpg does not match last frame (SSIM $SSIM, want >0.95)"
  fi
fi

echo
[ "$fail" = 0 ] && echo "PASS" || echo "FAILED"
exit "$fail"
