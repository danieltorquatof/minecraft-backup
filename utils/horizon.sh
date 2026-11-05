#!/bin/bash
# Prepares a Horizon server folder before it starts: server.toml, the world name and the game files.
# Horizon reads Minecraft 26.3 files prepared from the user's own copy of the game; they are never
# downloaded from Mojang nor shipped in the image (https://github.com/horizon-rust/horizon/blob/main/docs/hosting.md).

# shellcheck source=utils/common.sh
source /opt/minecraft-backup/utils/common.sh

# Where Horizon looks for the game files next to its engine (/opt/horizon/horizon-engine), as in its own Dockerfile.
HORIZON_RESOURCES_MOUNT="/opt/horizon/.local/horizon-client/26.3"
# Where `horizon-server import-resources` copies them inside the server folder.
HORIZON_RESOURCES_LOCAL="$DATA_DIR/resources"

is_prepared() {
  [ -f "$1/horizon-resources.json" ]
}

# Downloads an archive (.zip or .tar.*) holding a prepared 26.3 folder and imports it into $HORIZON_RESOURCES_LOCAL.
download_resources() {
  local tmp
  tmp="$(as_server_user mktemp -d)" || return 1

  log "HORIZON" "Downloading the game files from HORIZON_RESOURCES_URL..."

  if ! as_server_user curl -fsSL --retry 3 -o "$tmp/archive" "$HORIZON_RESOURCES_URL"; then
    log "HORIZON" "ERROR: could not download HORIZON_RESOURCES_URL."
    rm -rf "$tmp"
    return 1
  fi

  as_server_user mkdir -p "$tmp/files"

  if unzip -tq "$tmp/archive" >/dev/null 2>&1; then
    as_server_user unzip -q "$tmp/archive" -d "$tmp/files"
  else
    as_server_user tar -xf "$tmp/archive" -C "$tmp/files"
  fi || {
    log "HORIZON" "ERROR: HORIZON_RESOURCES_URL is not a .zip or .tar archive."
    rm -rf "$tmp"
    return 1
  }

  # The prepared folder may be at the top of the archive or inside a folder (e.g. 26.3/).
  local manifest
  manifest="$(find "$tmp/files" -maxdepth 3 -name horizon-resources.json -print -quit)"

  if [ -z "$manifest" ]; then
    log "HORIZON" "ERROR: the archive has no horizon-resources.json; it is not a prepared folder."
    rm -rf "$tmp"
    return 1
  fi

  # An existing resources/ folder makes import-resources copy there instead of somewhere else.
  as_server_user mkdir -p "$HORIZON_RESOURCES_LOCAL"

  local status=0
  horizon import-resources "$(dirname "$manifest")" || status=$?

  rm -rf "$tmp"

  if [ "$status" -ne 0 ]; then
    log "HORIZON" "ERROR: horizon-server rejected the downloaded game files."
    return 1
  fi

  log "HORIZON" "Game files imported into $HORIZON_RESOURCES_LOCAL."
}

check_resources() {
  if is_prepared "$HORIZON_RESOURCES_LOCAL"; then
    log "HORIZON" "Using the game files in $HORIZON_RESOURCES_LOCAL."
    return 0
  fi

  if is_prepared "$HORIZON_RESOURCES_MOUNT"; then
    log "HORIZON" "Using the game files mounted at $HORIZON_RESOURCES_MOUNT."
    return 0
  fi

  # A folder of the user's choice set with `engine.resources` in server.toml: Horizon checks it itself.
  if grep -Eq '^[[:space:]]*resources[[:space:]]*=[[:space:]]*"[^"]+"' "$DATA_DIR/server.toml"; then
    log "HORIZON" "Using the game files set by engine.resources in server.toml."
    return 0
  fi

  if [ -n "$HORIZON_RESOURCES_URL" ]; then
    download_resources
    return
  fi

  log "HORIZON" "ERROR: no prepared Minecraft 26.3 game files. Mount the folder prepared by the Horizon launcher" \
    "(or horizon-prepare) at $HORIZON_RESOURCES_MOUNT (HORIZON_RESOURCES_DIR in .env), or set HORIZON_RESOURCES_URL."
  return 1
}

horizon_setup() {
  fix_ownership

  if [ ! -f "$DATA_DIR/server.toml" ]; then
    log "HORIZON" "Creating server.toml from the HORIZON_* variables..."

    # The world folder is also the backup repository, so it is always named after it.
    export HORIZON_WORLD="$REPO_NAME"

    if ! horizon init --yes; then
      log "HORIZON" "ERROR: horizon-server init failed."
      return 1
    fi
  fi

  if ! horizon config set "world.name=$REPO_NAME" >/dev/null; then
    log "HORIZON" "ERROR: could not set world.name in server.toml."
    return 1
  fi

  # Horizon's own zip backups also pause saving (save-off); two backup systems would fight over it.
  if ! is_true "${HORIZON_BUILTIN_BACKUPS:-false}"; then
    horizon config set backups.every=0 >/dev/null ||
      log "HORIZON" "WARNING: could not turn off Horizon's built-in backups."
  fi

  check_resources
}
