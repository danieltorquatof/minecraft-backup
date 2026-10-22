#!/bin/bash
# Runs once before the Minecraft server starts: restores the world from the backup repository.

# shellcheck source=utils/common.sh
source /opt/minecraft-backup/utils/common.sh

LOG_FILE="$LOG_DIR/init.log"

clone_repo() {
  local remote_refs="$1"
  local args=(-q)

  # Don't depend on the remote's default branch pointing at the backups.
  if grep -q "refs/heads/$GIT_BRANCH\$" <<< "$remote_refs"; then
    args+=(--branch "$GIT_BRANCH")
  fi

  log "INIT" "Cloning backup repository into $REPO_DIR..."

  if ! as_server_user git clone "${args[@]}" "$GIT_REMOTE_URL" "$REPO_DIR"; then
    log "INIT" "ERROR: clone failed."
    return 1
  fi

  ensure_repo
}

# Keeps a local world that has no history instead of overwriting it with the remote one.
move_local_world_aside() {
  local backup_dir
  backup_dir="$REPO_DIR.local-$(date +%Y%m%d-%H%M%S)"

  log "INIT" "WARNING: $REPO_DIR has no backup history but the remote does. Moving it to $backup_dir."

  mv "$REPO_DIR" "$backup_dir"
}

check_and_process_repo() {
  fix_ownership

  local remote_output
  if ! remote_output=$(as_server_user git ls-remote "$GIT_REMOTE_URL" 2>&1); then
    log "INIT" "ERROR: could not reach the backup repository. Check GITHUB_USER, GITHUB_TOKEN and REPO_NAME."
    log "INIT" "git: $(tail -n 1 <<< "$remote_output")"

    return 0
  fi

  if [ -z "$remote_output" ]; then
    log "INIT" "The remote repository is empty. Preparing a new local repository..."

    ensure_repo || log "INIT" "ERROR: could not initialize $REPO_DIR."

    return 0
  fi

  if [ -d "$REPO_DIR/.git" ] && repo_has_commits; then
    log "INIT" "Repository already cloned. Syncing..."

    ensure_repo

    local branch
    branch="$(repo_git rev-parse --abbrev-ref HEAD)"

    if ! repo_git pull -q --ff-only origin "$branch"; then
      log "INIT" "ERROR: local and remote histories diverged. Starting with the local world; backups will fail until this is fixed manually."
    fi

    return 0
  fi

  if [ -e "$REPO_DIR" ]; then
    move_local_world_aside
  fi

  clone_repo "$remote_output"
}

log "INIT" "Preparing backup repository..."

check_and_process_repo

log "INIT" "Done."
