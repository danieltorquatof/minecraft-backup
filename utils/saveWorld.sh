#!/bin/bash

# shellcheck source=utils/common.sh
source /opt/minecraft-backup/utils/common.sh

# Flushes the world to disk (when the server is running), commits every change and pushes it.
saveWorld() {
  local prefix="$1"
  local online=false

  if [ ! -d "$REPO_DIR" ]; then
    log "$prefix" "World directory $REPO_DIR does not exist yet. Nothing to back up."
    return 0
  fi

  if ! ensure_repo; then
    log "$prefix" "ERROR: could not prepare the git repository at $REPO_DIR."
    return 1
  fi

  if server_online; then
    online=true

    rcon 'tellraw @a {"text":"📂 Backup started!","color":"gold"}' >/dev/null

    # Pause automatic saving so region files are not rewritten while they are staged.
    rcon save-off >/dev/null
    rcon save-all flush >/dev/null

    log "$prefix" "World successfully saved."
  fi

  local add_status=0
  repo_git add -A || add_status=$?

  if [ "$online" = true ]; then
    rcon save-on >/dev/null || log "$prefix" "WARNING: could not re-enable automatic saving."
  fi

  if [ "$add_status" -ne 0 ]; then
    log "$prefix" "ERROR: git add failed."
    return 1
  fi

  if repo_git diff --cached --quiet; then
    log "$prefix" "No changes since the last backup."
  else
    local commit_msg
    commit_msg="$(date -u +"%Y-%m-%dT%H:%M:%SZ") - $prefix"

    if ! repo_git commit -q -m "$commit_msg"; then
      log "$prefix" "ERROR: git commit failed."
      return 1
    fi

    log "$prefix" "Created commit \"$commit_msg\"."
  fi

  if ! repo_has_commits; then
    log "$prefix" "Repository has no commits yet. Nothing to push."
    return 0
  fi

  # Also sends commits left behind by previous failed pushes.
  if ! repo_git push -q -u origin HEAD; then
    log "$prefix" "ERROR: git push failed. Check GITHUB_USER, GITHUB_TOKEN and REPO_NAME, and whether the remote history diverged."

    if [ "$online" = true ]; then
      rcon 'tellraw @a {"text":"⚠ Backup failed to upload!","color":"red"}' >/dev/null || true
    fi

    return 1
  fi

  log "$prefix" "Backup successfully pushed."

  if [ "$online" = true ]; then
    rcon 'tellraw @a {"text":"📁 Backup completed!","color":"green"}' >/dev/null || true
  fi
}
