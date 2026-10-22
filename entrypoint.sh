#!/bin/bash
# Wraps the itzg/minecraft-server start script with Git backups:
# restore on startup, periodic autosaves and a final backup on shutdown.

# shellcheck source=utils/common.sh
source /opt/minecraft-backup/utils/common.sh

ORIGINAL_ENTRYPOINT="/image/scripts/start"
SCRIPTS_DIR="/opt/minecraft-backup/scripts"

LOG_FILE="$LOG_DIR/entrypoint.log"

MC_PID=""
PERIODIC_PID=""

validate_config() {
  local ok=true

  if [[ -z "$REPO_NAME" || "$REPO_NAME" == *"/"* || "$REPO_NAME" == "." || "$REPO_NAME" == ".." ]]; then
    log "ENTRYPOINT" "ERROR: REPO_NAME must be the repository name only (e.g. MyMinecraftWorld)."
    ok=false
  fi

  if [[ "$GIT_REMOTE_URL" == https://* && -z "$GITHUB_TOKEN" ]]; then
    log "ENTRYPOINT" "ERROR: GITHUB_TOKEN is required to push backups to $GIT_REMOTE_URL."
    ok=false
  fi

  if [[ "$GIT_REMOTE_URL" == "https://github.com//"* ]]; then
    log "ENTRYPOINT" "ERROR: GITHUB_USER is not set."
    ok=false
  fi

  if ! [[ "$INTERVAL_MINUTES" =~ ^[1-9][0-9]*$ ]]; then
    log "ENTRYPOINT" "ERROR: PERIODIC_INTERVAL must be a positive number of minutes (got '$INTERVAL_MINUTES')."
    ok=false
  fi

  if [[ -n "$ENABLE_RCON" ]] && ! is_true "$ENABLE_RCON"; then
    log "ENTRYPOINT" "ERROR: ENABLE_RCON must be true; backups use RCON to flush the world to disk."
    ok=false
  fi

  [ "$ok" = true ]
}

periodic_loop() {
  log "PERIODIC" "First execution in $INTERVAL_MINUTES minutes..."

  while true; do
    sleep "$INTERVAL_SECONDS"

    "$SCRIPTS_DIR/autosave.sh" || log "PERIODIC" "Autosave failed. See autosave.log."
  done
}

finish() {
  local exit_code="$1"

  if [ -n "$PERIODIC_PID" ]; then
    kill "$PERIODIC_PID" 2>/dev/null || true
  fi

  "$SCRIPTS_DIR/shutdown.sh" || log "ENTRYPOINT" "ERROR: final backup failed. See shutdown.log."

  log "ENTRYPOINT" "Container finished (server exit code $exit_code)."

  exit "$exit_code"
}

# Stops the server first so it saves the world cleanly, then takes the final backup.
# shellcheck disable=SC2329 # invoked through trap
on_stop_signal() {
  trap '' SIGTERM SIGINT

  if [ -z "$MC_PID" ]; then
    log "ENTRYPOINT" "Stop signal received before the server started. Exiting."
    exit 0
  fi

  log "ENTRYPOINT" "Stop signal received. Stopping Minecraft server..."

  kill -TERM "$MC_PID" 2>/dev/null || true

  local exit_code=0
  wait "$MC_PID" || exit_code=$?

  log "ENTRYPOINT" "Minecraft server stopped."

  finish "$exit_code"
}

trap on_stop_signal SIGTERM SIGINT

INTERVAL_MINUTES="${PERIODIC_INTERVAL:-15}"

if ! validate_config; then
  log "ENTRYPOINT" "Fix the configuration in .env and start the container again."
  exit 1
fi

INTERVAL_SECONDS=$((INTERVAL_MINUTES * 60))

# An empty RCON_PASSWORD would disable RCON; unset, the image generates a random one.
if [[ -v RCON_PASSWORD && -z "$RCON_PASSWORD" ]]; then
  unset RCON_PASSWORD
fi

log "ENTRYPOINT" "Running startup script..."

"$SCRIPTS_DIR/init.sh" || log "ENTRYPOINT" "ERROR: startup script failed. See init.log."

log "ENTRYPOINT" "Startup script completed."

periodic_loop &
PERIODIC_PID=$!

log "ENTRYPOINT" "Starting Minecraft server..."

"$ORIGINAL_ENTRYPOINT" "$@" &
MC_PID=$!

# Only reached when the server exits on its own (e.g. /stop in game or a crash).
exit_code=0
wait "$MC_PID" || exit_code=$?

log "ENTRYPOINT" "Minecraft server exited."

finish "$exit_code"
