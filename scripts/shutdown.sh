#!/bin/bash
# Final backup, run after the Minecraft server has stopped and flushed the world to disk.

# shellcheck source=utils/saveWorld.sh
source /opt/minecraft-backup/utils/saveWorld.sh

LOG_FILE="$LOG_DIR/shutdown.log"

exec 9>"$LOCK_FILE"

if ! flock -w 120 9; then
  log "SHUTDOWN" "WARNING: a previous backup is still running. Continuing anyway."
fi

log "SHUTDOWN" "Running final backup..."

if ! saveWorld "SHUTDOWN"; then
  log "SHUTDOWN" "Final backup failed."
  exit 1
fi

log "SHUTDOWN" "Complete closure!"
