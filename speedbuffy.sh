#!/usr/bin/env bash
# speedbuffy.sh — ASCII speed test for Raspberry Pi / Debian (zero‑install)
#
# • Uses only: bash, curl, ping, awk, tput (no python/node/go; no bc)
# • Live ASCII UI with fixed header/logo and bottom‑right footer
# • Quick test: 10s latency → download → upload (no pause; returns to shell)
# • Menu tests: latency / download / upload / export JSON
# • JSON modes: --json (stdout), --save-json (timestamp file), --out-json FILE
# • Robust download fallbacks (HTTPS→HTTP, Range→full fetch) + sanitized math
# • Defensive against set -u (no “unbound variable”); numeric guards everywhere
# • Logs when --debug is set → /tmp/speedbuffy.log
# • Footer credit: Designed by @ai_chohan

set -euo pipefail
export LC_ALL=C

# ------------------------------ Defaults ------------------------------------ #
SIZE_MB=100          # default download size
DL_TIMECAP=30        # max seconds for download test
UL_TIMECAP=20        # max seconds for upload test
UL_CHUNK_MB=8        # upload chunk MB
LAT_QUICK_SECONDS=10 # quick-test latency window
LAT_MENU_SECONDS=30  # menu latency window
IPV_MODE="auto"      # 4 | 6 | auto
SERVER="hetzner"     # hetzner | thinkbroadband | tele2
MODE="menu"          # menu | quick
JSON_OUT=0           # print JSON only
SAVE_JSON=0          # save JSON to timestamped file
OUT_JSON=""          # save JSON to a specific file
USE_COLOR=1          # TTY only by default
DEBUG_LOG=0
LOGF="/tmp/speedbuffy.log"

# ------------------------------ CLI ----------------------------------------- #
usage(){ cat <<EOF
speedbuffy.sh — ASCII speed test (zero-install)

Options:
  --quick                   Run latency+download+upload (visuals) and exit
  --json                    Print JSON only and exit (no visuals/menu)
  --save-json               Like --json but also save to speedbuffy-YYYYMMDD-HHMMSS.json
  --out-json FILE           Like --json but save to FILE (and still print to stdout)
  --size MB                 Download size (default ${SIZE_MB})
  --dlcap SEC               Download time cap (default ${DL_TIMECAP})
  --ulcap SEC               Upload time cap (default ${UL_TIMECAP})
  --ipv 4|6|auto            Force IP family (default ${IPV_MODE})
  --server NAME             hetzner|thinkbroadband|tele2 (default ${SERVER})
  --no-color|--color        Force disable/enable colors
  --debug                   Log internals to ${LOGF}
  -h, --help                Show help

Examples:
  ./speedbuffy.sh --quick --ipv 4 --server tele2 --no-color
  ./speedbuffy.sh --json --out-json results.json
  ./speedbuffy.sh --save-json   # prints JSON and writes a timestamped file
EOF
}

while [[ ${1:-} ]]; do
  case "$1" in
    --quick) MODE="quick"; shift ;;
    --json)  JSON_OUT=1; MODE="quick"; shift ;;
    --save-json) JSON_OUT=1; SAVE_JSON=1; MODE="quick"; shift ;;
    --out-json) JSON_OUT=1; MODE="quick"; OUT_JSON=${2:-}; shift 2 ;;
    --size)  SIZE_MB=${2:-$SIZE_MB}; shift 2 ;;
    --dlcap) DL_TIMECAP=${2:-$DL_TIMECAP}; shift 2 ;;
    --ulcap) UL_TIMECAP=${2:-$UL_TIMECAP}; shift 2 ;;
    --ipv)   IPV_MODE=${2:-$IPV_MODE}; shift 2 ;;
    --server) SERVER=${2:-$SERVER}; shift 2 ;;
    --no-color) USE_COLOR=0; shift ;;
    --color)    USE_COLOR=1; shift ;;
    --debug)    DEBUG_LOG=1; : > "$LOGF"; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown arg: $1" >&2; usage; exit 1 ;;
  esac
done

# ------------------------------ Reqs ---------------------------------------- #
have(){ command -v "$1" >/dev/null 2>&1; }
for c in curl ping awk tput; do have "$c" || { echo "missing: $c" >&2; exit 1; }; done
[[ -t 1 ]] || USE_COLOR=0
log(){ (( DEBUG_LOG )) && printf '%s\n' "$*" >> "$LOGF" || true; }

# ------------------------------ Helpers ------------------------------------- #
num_or_zero(){ case "${1:-}" in (''|*[!0-9.]* ) echo 0 ;; (*) echo "$1" ;; esac; }
safe_div_MBps(){ # bytes / seconds → MB/s
  local B; B=$(num_or_zero "${1:-0}"); local S; S=$(num_or_zero "${2:-0}");
  awk -v B="$B" -v S="$S" 'BEGIN{ if(S==0){S=0.001}; printf "%.3f", (B/1048576)/S }'
}
mbps_from_MBps(){ local M; M=$(num_or_zero "${1:-0}"); awk -v M="$M" 'BEGIN{ printf "%.1f", M*8 }'; }

color_on(){ (( USE_COLOR )) && tput setaf 2 && tput bold || true; }
color_off(){ (( USE_COLOR )) && tput sgr0 || true; }
clr(){ tput clear; }
pos(){ tput cup "$1" "$2"; }
cols(){ tput cols; }
rows(){ tput lines; }
hr(){ printf '%*s' "$(cols)" '' | tr ' ' '-'; }

header_art(){
  color_on; pos 0 0; cat <<'ART'
                         _   ___        __  __       
 ___ _ __   ___  ___  __| | / __\_   _ / _|/ _|_   _ 
/ __| '_ \ / _ \/ _ \/ _` |/__\// | | | |_| |_| | | |
\__ \ |_) |  __/  __/ (_| / \/  \ |_| |  _|  _| |_| |
|___/ .__/ \___|\___|\__,_\_____/\__,_|_| |_|  \__, |
    |_|                                        |___/ 
         __
        /  \__  /\_/\  Buffy
       /_/\___\ \_ _/  the Dog
          /  /   / \
          \_/   /_/  
ART
color_off
}

print_header(){ header_art; pos 8 0; echo "$(hr)"; }
print_footer(){
  local r; r=$(rows); local c; c=$(cols)
  pos $((r-2)) 0; echo "$(hr)"
  local tag='Designed by @ai_chohan'
  local x=$(( c - ${#tag} - 1 )); (( x<0 )) && x=0
  pos $((r-1)) $x; printf '%s' "$tag"
}
frame_clear(){ clr; print_header; print_footer; }

ipflag(){ case "$IPV_MODE" in 4) echo -4;; 6) echo -6;; *) echo "";; esac }

# ------------------------------ Servers ------------------------------------- #
make_url(){ local size=$1; case "$SERVER" in
  hetzner)         echo "https://speed.hetzner.de/${size}MB.bin" ;;
  thinkbroadband)  echo "https://ipv4.download.thinkbroadband.com/${size}MB.zip" ;;
  tele2)           echo "http://speedtest.tele2.net/${size}MB.zip" ;;
  *)               echo "https://speed.hetzner.de/${size}MB.bin" ;;
esac; }
alt_url(){ echo "${1:-}" | sed -e 's/^https:/http:/'; }

# ------------------------------ Latency (live) ------------------------------ #
ping_stats_live(){
  local secs host ipf; secs=${1:-10}; host=8.8.8.8; ipf="$(ipflag)"
  local sent=0 recv=0 start now elapsed width fill pct
  start=$(date +%s)

  while :; do
    now=$(date +%s)
    elapsed=$(( now - start ))
    (( elapsed>=secs )) && break

    if ping $ipf -c 1 -W 1 "$host" >/dev/null 2>&1; then recv=$((recv+1)); fi
    sent=$((sent+1))

    frame_clear; color_on; pos 10 2; printf 'LATENCY — %ds live' "$secs"; color_off
    pct=$(( 100*elapsed/secs )); (( pct<0 )) && pct=0; (( pct>100 )) && pct=100
    width=$(( $(cols) - 6 )); (( width<20 )) && width=20
    fill=$(( pct*width/100 ))
    pos 12 2; printf '['; printf '%*s' "$fill" '' | tr ' ' '#'; printf '%*s' $((width-fill)) '' | tr ' ' ' '
    printf '] %3d%%  %2ds/%2ds  sent:%d recv:%d\n' "$pct" "$elapsed" "$secs" "$sent" "$recv"
    print_footer; sleep 0.2
  done

  local out loss avg_ms jit_ms
  out=$(ping $ipf -c 10 -i 0.2 -w 5 "$host" 2>/dev/null || true)
  loss=$(echo "$out" | awk -F', ' '/packets transmitted/ {print $3}' | awk '{print $1}' | tr -d '%')
  avg_ms=$(echo "$out" | awk -F'[/= ]' '/min\/avg\/max/ {printf "%.3f",$8}')
  jit_ms=$(echo "$out" | awk -F'[/= ]' '/min\/avg\/max/ {printf "%.3f",$14}')
  [[ -z ${loss:-} ]] && loss=0; [[ -z ${avg_ms:-} ]] && avg_ms=0; [[ -z ${jit_ms:-} ]] && jit_ms=0
  printf '%s %s %s\n' "$loss" "$avg_ms" "$jit_ms"
}

# ------------------------------ Download (robust) --------------------------- #
# returns: MBps Mbps elapsed
run_download_live(){
  local size_mb cap; size_mb=${1:-$SIZE_MB}; cap=${2:-$DL_TIMECAP}
  local primary ipf fallback_http; primary=$(make_url "$size_mb"); ipf="$(ipflag)"; fallback_http=$(alt_url "$primary")
  local chunk=$((5*1048576)) start_byte=0 total=0 start_ts now el
  start_ts=$(date +%s)
  local url="$primary" tried_http=0

  _dl_try_chunk(){ # url start end → echo code rip bytes time
    local u=$1 s=$2 e=$3
    curl $ipf -sS -L --http1.1 --fail -r "$s-$e" -o /dev/null \
      -w "%{http_code} %{remote_ip} %{size_download} %{time_total}\n" "$u" \
      || echo "000 - 0 0"
  }
  _dl_full(){ # url → echo MBps Mbps elapsed
    local u=$1 out bytes time MBps Mbps
    out=$(curl $ipf --http1.1 --progress-bar -L -o /dev/null \
           -w "%{size_download} %{time_total} %{speed_download}\n" "$u" 2> >(cat >&2))
    bytes=$(echo "$out" | awk '{print $1}'); time=$(echo "$out" | awk '{print $2}')
    bytes=$(num_or_zero "$bytes"); time=$(num_or_zero "$time"); [[ "$time" = 0 ]] && time=0.001
    MBps=$(safe_div_MBps "$bytes" "$time"); Mbps=$(mbps_from_MBps "$MBps")
    echo "$MBps $Mbps $time"
  }

  while :; do
    now=$(date +%s); el=$(( now - start_ts ))
    (( el>=cap )) && break
    (( total >= size_mb*1048576 )) && break

    local end=$(( start_byte + chunk - 1 ))
    local code="" rip="" bytes="" time=""
    read -r code rip bytes time < <(_dl_try_chunk "$url" "$start_byte" "$end")
    log "DL $url $start_byte-$end code=$code rip=$rip bytes=$bytes time=$time"

    if [[ "$code" != "206" || -z ${bytes:-} || "$bytes" = "0" ]]; then
      if (( tried_http==0 )) && [[ "$url" = https:* ]]; then
        url="$fallback_http"; tried_http=1; log "DL fallback to HTTP: $url"; continue
      fi
      frame_clear; color_on; pos 10 2; printf 'NOW STARTING DOWNLOAD (full fallback)'; color_off
      pos 12 2; printf 'Server: %s   URL: %s' "$SERVER" "$url"; print_footer
      local MBps Mbps elapsed
      read -r MBps Mbps elapsed < <(_dl_full "$url")
      echo "$MBps $Mbps $elapsed"; return 0
    fi

    bytes=$(num_or_zero "$bytes"); time=$(num_or_zero "$time"); [[ "$time" = 0 ]] && time=0.001
    total=$(( total + bytes ))
    local MBps Mbps
    MBps=$(safe_div_MBps "$bytes" "$time"); Mbps=$(mbps_from_MBps "$MBps")

    frame_clear; color_on; pos 10 2; printf 'NOW STARTING DOWNLOAD'; color_off
    pos 12 2; printf 'Server: %s   URL: %s' "$SERVER" "$url"
    pos 13 2; printf 'Chunk: %8d..%-8d  Code:%s  IP:%s' "$start_byte" "$end" "$code" "$rip"
    pos 14 2; printf 'This chunk: %6.3f MB/s (%5.1f Mb/s)   Elapsed: %2ds' "$MBps" "$Mbps" "$el"
    pos 15 2; printf 'Total: %7.2f MB of ~%d MB' "$(awk -v T="$total" 'BEGIN{printf "%.2f",T/1048576}')" "$size_mb"
    print_footer

    start_byte=$(( end + 1 ))
  done

  local elapsed=$(( $(date +%s) - start_ts )); (( elapsed==0 )) && elapsed=1
  local avgMBps=$(awk -v T="$total" -v S="$elapsed" 'BEGIN{printf "%.3f",(T/1048576)/S}')
  local avgMbps=$(mbps_from_MBps "$avgMBps")
  echo "$avgMBps $avgMbps $elapsed"
}

# ------------------------------ Upload (robust) ----------------------------- #
run_upload_live(){
  local chunk_mb cap; chunk_mb=${1:-$UL_CHUNK_MB}; cap=${2:-$UL_TIMECAP}
  local ipf; ipf="$(ipflag)"; local url="http://speedtest.tele2.net/upload.php"
  local start now el total=0; start=$(date +%s)

  while :; do
    now=$(date +%s); el=$(( now - start )); (( el>=cap )) && break
    local out sz rip t MBps Mbps
    out=$( dd if=/dev/zero bs=1M count="$chunk_mb" 2>/dev/null | \
      curl $ipf --http1.1 -s -L -o /dev/null \
      -w "%{size_upload} %{remote_ip} %{time_total} %{speed_upload}\n" \
      -X POST --data-binary @- "$url" ) || out="0 - 0 0"
    sz=$(num_or_zero "$(echo "$out" | awk '{print $1}')"); rip=$(echo "$out" | awk '{print $2}')
    t=$(num_or_zero "$(echo "$out" | awk '{print $3}')"); [[ "$t" = 0 ]] && t=0.001
    total=$(( total + sz ))
    MBps=$(safe_div_MBps "$sz" "$t"); Mbps=$(mbps_from_MBps "$MBps")

    frame_clear; color_on; pos 10 2; printf 'NOW STARTING UPLOAD'; color_off
    pos 12 2; printf 'Server: tele2   URL: %s' "$url"
    pos 13 2; printf 'Chunk: %d MB   IP:%s' "$chunk_mb" "$rip"
    pos 14 2; printf 'This chunk: %6.3f MB/s (%5.1f Mb/s)   Elapsed: %2ds' "$MBps" "$Mbps" "$el"
    pos 15 2; printf 'Total: %7.2f MB' "$(awk -v T="$total" 'BEGIN{printf "%.2f",T/1048576}')"
    print_footer
  done

  local elapsed=$(( $(date +%s) - start )); (( elapsed==0 )) && elapsed=1
  local avgMBps=$(awk -v T="$total" -v S="$elapsed" 'BEGIN{printf "%.3f",(T/1048576)/S}')
  local avgMbps=$(mbps_from_MBps "$avgMBps")
  echo "$avgMBps $avgMbps $elapsed"
}

# ------------------------------ JSON & Results ------------------------------ #
emit_json(){
  local loss=$1 avg=$2 jit=$3 dMB=$4 dMb=$5 dSec=$6 uMB=$7 uMb=$8 uSec=$9
  printf '{"latency":{"loss_pct":%s,"avg_ms":%s,"jitter_ms":%s},"download":{"MBps":%s,"Mbps":%s,"seconds":%s},"upload":{"MBps":%s,"Mbps":%s,"seconds":%s}}\n' \
    "$loss" "$avg" "$jit" "$dMB" "$dMb" "$dSec" "$uMB" "$uMb" "$uSec"
}

ts_name(){ date +"speedbuffy-%Y%m%d-%H%M%S.json"; }
maybe_save_json(){
  local payload=$1
  if [[ -n "$OUT_JSON" ]]; then printf '%s\n' "$payload" > "$OUT_JSON"; echo "$OUT_JSON"; return; fi
  if (( SAVE_JSON )); then local f; f=$(ts_name); printf '%s\n' "$payload" > "$f"; echo "$f"; return; fi
  echo ""
}

results_page(){
  local loss=$1 avg=$2 jit=$3 dMB=$4 dMb=$5 dSec=$6 uMB=$7 uMb=$8 uSec=$9
  frame_clear; color_on; pos 10 2; printf 'RESULTS'; color_off
  pos 12 2; printf 'Latency:  loss=%s%%  avg=%sms  jitter=%sms' "$loss" "$avg" "$jit"
  pos 13 2; printf 'Download: %s MB/s (%s Mb/s) in %ss' "$dMB" "$dMb" "$dSec"
  pos 14 2; printf 'Upload:   %s MB/s (%s Mb/s) in %ss' "$uMB" "$uMb" "$uSec"
  print_footer
  if [[ "${_SPEEDBUFFY_CALLER:-menu}" == "menu" ]]; then
    pos $(( $(rows)-1 )) 0; read -r -p "Press Enter to return to the main menu…" _ || true
  fi
}

# ------------------------------ Menu ---------------------------------------- #
settings_panel(){
  frame_clear; color_on; pos 10 2; printf 'SETTINGS'; color_off
  pos 12 2; printf 'Server: %s   (hetzner|thinkbroadband|tele2)' "$SERVER"
  pos 13 2; printf 'IPv: %s     (4|6|auto)' "$IPV_MODE"
  pos 14 2; printf 'DL size: %d MB   DL cap: %ds   UL cap: %ds' "$SIZE_MB" "$DL_TIMECAP" "$UL_TIMECAP"
  print_footer
  pos $(( $(rows)-1 )) 0; read -r -p "Change settings? [y/N]: " a
  if [[ ${a:-N} =~ ^[Yy]$ ]]; then
    local v
    read -r -p "Server [$SERVER]: " v; [[ -n ${v:-} ]] && SERVER=$v
    read -r -p "IPv (4|6|auto) [$IPV_MODE]: " v; [[ -n ${v:-} ]] && IPV_MODE=$v
    read -r -p "DL size MB [$SIZE_MB]: " v; [[ -n ${v:-} ]] && SIZE_MB=$v
    read -r -p "DL cap s [$DL_TIMECAP]: " v; [[ -n ${v:-} ]] && DL_TIMECAP=$v
    read -r -p "UL cap s [$UL_TIMECAP]: " v; [[ -n ${v:-} ]] && UL_TIMECAP=$v
  fi
}

latency_only(){ local L A J; read -r L A J < <(ping_stats_live "$LAT_MENU_SECONDS"); results_page "$L" "$A" "$J" 0 0 0 0 0 0; }

_download_menu(){
  frame_clear; color_on; pos 10 2; printf 'DOWNLOAD TEST'; color_off
  pos 12 2; printf 'Use defaults? size=%dMB cap=%ds  [Y/n]: ' "$SIZE_MB" "$DL_TIMECAP"; local a; read -r a
  local s=$SIZE_MB c=$DL_TIMECAP v
  if [[ ${a:-Y} =~ ^[Nn]$ ]]; then
    read -r -p "DL size MB [$SIZE_MB]: " v; [[ -n ${v:-} ]] && s=$v
    read -r -p "DL cap s  [$DL_TIMECAP]: " v; [[ -n ${v:-} ]] && c=$v
  fi
  local dMB dMb dSec; read -r dMB dMb dSec < <(run_download_live "$s" "$c")
  results_page 0 0 0 "$dMB" "$dMb" "$dSec" 0 0 0
}

_upload_menu(){
  frame_clear; color_on; pos 10 2; printf 'UPLOAD TEST'; color_off
  pos 12 2; printf 'Use defaults? chunk=%dMB cap=%ds  [Y/n]: ' "$UL_CHUNK_MB" "$UL_TIMECAP"; local a; read -r a
  local ch=$UL_CHUNK_MB uc=$UL_TIMECAP v
  if [[ ${a:-Y} =~ ^[Nn]$ ]]; then
    read -r -p "Chunk MB [$UL_CHUNK_MB]: " v; [[ -n ${v:-} ]] && ch=$v
    read -r -p "UL cap s [$UL_TIMECAP]: " v; [[ -n ${v:-} ]] && uc=$v
  fi
  local uMB uMb uSec; read -r uMB uMb uSec < <(run_upload_live "$ch" "$uc")
  results_page 0 0 0 0 0 0 "$uMB" "$uMb" "$uSec"
}

_export_json_menu(){
  local loss avg jit dMB dMb dSec uMB uMb uSec payload file
  read -r loss avg jit < <(ping_stats_live 1)
  read -r dMB dMb dSec < <(run_download_live "$SIZE_MB" "$DL_TIMECAP")
  read -r uMB uMb uSec < <(run_upload_live "$UL_CHUNK_MB" "$UL_TIMECAP")
  payload=$(emit_json "$loss" "$avg" "$jit" "$dMB" "$dMb" "$dSec" "$uMB" "$uMb" "$uSec")
  file=$(ts_name); printf '%s\n' "$payload" > "$file"
  frame_clear; color_on; pos 10 2; printf 'EXPORTED'; color_off
  pos 12 2; printf 'Saved %s' "$file"; print_footer
  pos $(( $(rows)-1 )) 0; read -r -p "Press Enter to return to the main menu…" _ || true
}

menu(){
  while :; do
    frame_clear; color_on; pos 10 2; printf 'Choose an option:'; color_off
    pos 12 2; echo "[1] Quick Test (10s latency + download + upload)"
    pos 13 2; echo "[2] Latency only (30s live)"
    pos 14 2; echo "[3] Download test"
    pos 15 2; echo "[4] Upload test"
    pos 16 2; echo "[5] Settings"
    pos 17 2; echo "[6] Export JSON (run full test + save file)"
    pos 18 2; echo "[0] Exit"
    print_footer
    pos $(( $(rows)-1 )) 0; local choice; read -r -p "> " choice || exit 0
    case "$choice" in
      1) quick_run_visual ;;
      2) latency_only ;;
      3) _download_menu ;;
      4) _upload_menu ;;
      5) settings_panel ;;
      6) _export_json_menu ;;
      0|q|Q) clr; exit 0 ;;
    esac
  done
}

# ------------------------------ Quick & Entry ------------------------------- #
quick_run_visual(){
  _SPEEDBUFFY_CALLER="quick"
  local LOSS AVG JIT dMB dMb dSec uMB uMb uSec
  read -r LOSS AVG JIT < <(ping_stats_live "$LAT_QUICK_SECONDS")
  read -r dMB dMb dSec < <(run_download_live "$SIZE_MB" "$DL_TIMECAP")
  read -r uMB uMb uSec < <(run_upload_live "$UL_CHUNK_MB" "$UL_TIMECAP")
  results_page "$LOSS" "$AVG" "$JIT" "$dMB" "$dMb" "$dSec" "$uMB" "$uMb" "$uSec"
}

if (( JSON_OUT )); then
  local loss avg jit dMB dMb dSec uMB uMb uSec payload saved
  read -r loss avg jit < <(ping_stats_live "$LAT_QUICK_SECONDS")
  read -r dMB dMb dSec < <(run_download_live "$SIZE_MB" "$DL_TIMECAP")
  read -r uMB uMb uSec < <(run_upload_live "$UL_CHUNK_MB" "$UL_TIMECAP")
  payload=$(emit_json "$loss" "$avg" "$jit" "$dMB" "$dMb" "$dSec" "$uMB" "$uMb" "$uSec")
  echo "$payload"
  saved=$(maybe_save_json "$payload"); [[ -n "$saved" ]] && echo "Saved: $saved" 1>&2
  exit 0
fi

if [[ "${MODE}" == "quick" ]]; then
  quick_run_visual; exit 0
fi

menu
