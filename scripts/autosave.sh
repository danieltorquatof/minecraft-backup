#!/bin/bash
# Periodic backup, run every PERIODIC_INTERVAL minutes while the server is up.
# Can also be run by hand: docker compose exec minecraft /opt/minecraft-backup/scripts/autosave.sh

# shellcheck source=utils/saveWorld.sh
source /opt/minecraft-backup/utils/saveWorld.sh

LOG_FILE="$LOG_DIR/autosave.log"

exec 9>"$LOCK_FILE"

if ! flock -n 9; then
  log "AUTOSAVE" "Another backup is still running. Skipping."
  exit 0
fi

if ! server_online; then
  log "AUTOSAVE" "Server is not accepting RCON commands yet. Skipping."
  exit 0
fi

log "AUTOSAVE" "Starting execution..."

if ! saveWorld "AUTOSAVE"; then
  log "AUTOSAVE" "Execution failed."
  exit 1
fi

log "AUTOSAVE" "Execution completed."
