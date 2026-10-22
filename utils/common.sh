#!/bin/bash
# Shared configuration and helpers for the backup scripts.

# shellcheck source=utils/log.sh
source /opt/minecraft-backup/utils/log.sh

umask 0002

DATA_DIR="/data"
REPO_DIR="$DATA_DIR/$REPO_NAME"
GIT_REMOTE_URL="${GIT_REMOTE_URL:-https://github.com/$GITHUB_USER/$REPO_NAME.git}"
GIT_BRANCH="${GIT_BRANCH:-main}"
# shellcheck disable=SC2034 # used by autosave.sh and shutdown.sh
LOCK_FILE="/tmp/minecraft-backup.lock"

# Same user the itzg image uses to run the server (UID/GID env vars, default 1000).
RUN_UID="${UID:-1000}"
RUN_GID="${GID:-1000}"

# Git needs both an author and a committer identity, otherwise `git commit` fails.
export GIT_AUTHOR_NAME="${GIT_AUTHOR_NAME:-Minecraft Autosave}"
export GIT_AUTHOR_EMAIL="${GIT_AUTHOR_EMAIL:-minecraft-autosave@localhost}"
export GIT_COMMITTER_NAME="${GIT_COMMITTER_NAME:-$GIT_AUTHOR_NAME}"
export GIT_COMMITTER_EMAIL="${GIT_COMMITTER_EMAIL:-$GIT_AUTHOR_EMAIL}"

# Git settings passed through the environment (equivalent to `git -c`), so no
# config file is needed and the token is never written to disk or to the remote URL.
export GIT_TERMINAL_PROMPT=0
export GIT_CONFIG_COUNT=3
export GIT_CONFIG_KEY_0="safe.directory"
export GIT_CONFIG_VALUE_0="$REPO_DIR"
export GIT_CONFIG_KEY_1="init.defaultBranch"
export GIT_CONFIG_VALUE_1="$GIT_BRANCH"
export GIT_CONFIG_KEY_2="credential.helper"
# shellcheck disable=SC2016 # expanded by the shell git spawns, not here
export GIT_CONFIG_VALUE_2='!f() { test "$1" = get && test -n "$GITHUB_TOKEN" && echo "username=${GITHUB_USER:-x-access-token}" && echo "password=$GITHUB_TOKEN"; }; f'

is_true() {
  [[ "${1,,}" == "true" ]]
}

# Runs a command as the server user, so files written by git are never owned by root.
as_server_user() {
  if [ "$(id -u)" = 0 ] && [ "$RUN_UID" != 0 ]; then
    gosu "$RUN_UID:$RUN_GID" "$@"
  else
    "$@"
  fi
}

repo_git() {
  as_server_user git -C "$REPO_DIR" "$@"
}

# The image writes the (possibly auto-generated) RCON password to /data/.rcon-cli.yaml.
rcon() {
  local args=(--port "${RCON_PORT:-25575}")

  if [ -f "$DATA_DIR/.rcon-cli.yaml" ]; then
    args+=(--config "$DATA_DIR/.rcon-cli.yaml")
  fi

  rcon-cli "${args[@]}" "$@"
}

server_online() {
  rcon list >/dev/null 2>&1
}

# Gives /data and the backup repository back to the server user. Older versions of
# this project ran git as root, which left root-owned world files behind.
fix_ownership() {
  [ "$(id -u)" = 0 ] || return 0
  [ "$RUN_UID" != 0 ] || return 0
  is_true "${SKIP_CHOWN_DATA:-false}" && return 0

  if [ "$(stat -c '%u' "$DATA_DIR")" != "$RUN_UID" ]; then
    chown -R "$RUN_UID:$RUN_GID" "$DATA_DIR"
  elif [ -d "$REPO_DIR" ]; then
    find "$REPO_DIR" ! -user "$RUN_UID" -exec chown "$RUN_UID:$RUN_GID" {} +
  fi
}

repo_has_commits() {
  repo_git rev-parse -q --verify HEAD >/dev/null 2>&1
}

# Makes sure $REPO_DIR is a git repository whose origin points to $GIT_REMOTE_URL.
ensure_repo() {
  if [ ! -d "$REPO_DIR/.git" ]; then
    as_server_user mkdir -p "$REPO_DIR" || return 1
    repo_git init -q -b "$GIT_BRANCH" || return 1
  fi

  # Also replaces remote URLs with an embedded token left by older versions.
  if repo_git remote get-url origin >/dev/null 2>&1; then
    repo_git remote set-url origin "$GIT_REMOTE_URL" || return 1
  else
    repo_git remote add origin "$GIT_REMOTE_URL" || return 1
  fi

  # The server keeps this file locked while running; it is useless in a backup.
  if ! grep -qx 'session.lock' "$REPO_DIR/.git/info/exclude" 2>/dev/null; then
    as_server_user mkdir -p "$REPO_DIR/.git/info"
    echo 'session.lock' | as_server_user tee -a "$REPO_DIR/.git/info/exclude" >/dev/null
  fi
}
