#!/bin/bash
# Logging helper shared by every script.
# Each message goes to stdout (visible with `docker compose logs`) and to $LOG_FILE.

LOG_DIR="${LOG_DIR:-/var/log/mc-scripts}"

log() {
  local prefix="$1"
  shift

  local line
  line="[$(date '+%Y-%m-%d %H:%M:%S')] [$prefix] $*"

  echo "$line"

  local target="${LOG_FILE:-$LOG_DIR/default.log}"

  mkdir -p "$(dirname "$target")" 2>/dev/null || true
  echo "$line" >> "$target" 2>/dev/null || true
}
