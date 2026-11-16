#!/usr/bin/env bash
# Prints one line with memory, swap, disk and load every N seconds, plus the
# largest processes. The Android emulator jobs start it in the background
# before the build, so that a runner that dies leaves its last readings in
# the job log.
set -u
interval="${1:-20}"
while true; do
  mem="$(free -m | awk '
    /^Mem:/  {printf "mem_total=%d used=%d avail=%d", $2, $3, $7}
    /^Swap:/ {printf " swap_total=%d swap_used=%d", $2, $3}')"
  disk="$(df --output=avail -m / | tail -n 1 | tr -d ' ')"
  load="$(cut -d' ' -f1 /proc/loadavg)"
  top="$(ps -eo rss=,args= --sort=-rss | awk '
    $2 ~ /(^|\/)(awk|ps)$/ { next }
    shown >= 5 { exit }
    {
    shown++
    name = $2
    if ($0 ~ /GradleDaemon/) name = "gradle-daemon"
    else if ($0 ~ /KotlinCompileDaemon/) name = "kotlin-daemon"
    else if ($0 ~ /GradleWorkerMain/) name = "gradle-worker"
    else if ($0 ~ /qemu-system/) name = "emulator"
    else if ($0 ~ /frontend_server/) name = "dart-frontend"
    else { n = split($2, parts, "/"); name = parts[n] }
    printf "%s=%dMB ", name, $1 / 1024
  }')"
  echo "RES $(date -u +%H:%M:%S) ${mem} disk_avail_mb=${disk} load=${load} top: ${top}"
  sleep "$interval"
done
