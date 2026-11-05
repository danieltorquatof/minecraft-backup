#!/bin/bash
# Server backend: how to start the server, send it console commands and tell whether it is up.
# SERVER_FLAVOR is set by the Dockerfile:
#   java    - itzg/minecraft-server (Dockerfile), commands go through RCON.
#   horizon - Horizon, the Rust server (Dockerfile.horizon), commands go through its local control API.
# Sourced by common.sh, after DATA_DIR, RUN_UID/RUN_GID and as_server_user are defined.

SERVER_FLAVOR="${SERVER_FLAVOR:-java}"

# Start script of the itzg/minecraft-server image.
ITZG_START="/image/scripts/start"

is_horizon() {
  [ "$SERVER_FLAVOR" = "horizon" ]
}

# The itzg image writes the (possibly auto-generated) RCON password to /data/.rcon-cli.yaml.
rcon() {
  local args=(--port "${RCON_PORT:-25575}")

  if [ -f "$DATA_DIR/.rcon-cli.yaml" ]; then
    args+=(--config "$DATA_DIR/.rcon-cli.yaml")
  fi

  rcon-cli "${args[@]}" "$@"
}

# Runs a horizon-server subcommand on the server folder, as the server user.
horizon() {
  as_server_user horizon-server --dir "$DATA_DIR" "$@"
}

# Runs one console command (e.g. `server_cmd save-all flush`). Fails if the server can't be reached.
server_cmd() {
  if is_horizon; then
    horizon cmd "$@"
  else
    rcon "$@"
  fi
}

server_online() {
  if is_horizon; then
    horizon status --json 2>/dev/null | grep -q '"phase":"running"'
  else
    rcon list >/dev/null 2>&1
  fi
}

# Horizon's supervisor stays up when the game is stopped from inside (`/stop` in game, RCON,
# `horizon-server cmd stop`), waiting for a `start` that never comes in a container. This ends it,
# so the container stops and takes its final backup as with the Java server. Run it in the background.
# Only that case reports the "stopped" phase (a crash restarts as "restarting"); it is checked twice,
# and only after the game has been up, to skip the moment a `horizon-server restart` passes through it.
server_watch_stop() {
  local pid="$1"
  local seen_running=false
  local stopped_checks=0
  local status

  is_horizon || return 0

  while kill -0 "$pid" 2>/dev/null; do
    sleep 5

    status="$(horizon status --json 2>/dev/null)"

    case "$status" in
      *'"phase":"running"'*)
        seen_running=true
        stopped_checks=0
        ;;
      *'"phase":"stopped"'*)
        [ "$seen_running" = true ] && stopped_checks=$((stopped_checks + 1))
        ;;
      *)
        stopped_checks=0
        ;;
    esac

    if [ "$stopped_checks" -ge 2 ]; then
      log "ENTRYPOINT" "The game was stopped from inside the server. Ending horizon-server..."
      kill -TERM "$pid" 2>/dev/null
      return 0
    fi
  done
}

# Replaces the current process with the server. Run it in the background (`server_start "$@" &`)
# so that $! is the server's own PID and SIGTERM reaches it directly.
server_start() {
  if ! is_horizon; then
    # The itzg start script drops to the server user by itself.
    exec "$ITZG_START" "$@"
  fi

  # horizon-server supervises the game and, on SIGTERM, saves the world before stopping.
  if [ "$(id -u)" = 0 ] && [ "$RUN_UID" != 0 ]; then
    exec gosu "$RUN_UID:$RUN_GID" horizon-server --dir "$DATA_DIR" run
  fi

  exec horizon-server --dir "$DATA_DIR" run
}
