#!/usr/bin/env bash
set -euo pipefail

REPO_DIR="${REPO_DIR:-/home/jibby2k1/Documents/SPS/Ares/ares_tracker}"
REMOTE="${REMOTE:-public}"
MAIN_BRANCH="${MAIN_BRANCH:-main}"

STAGES=(
  stage-2-session
  stage-3-uid
  stage-4-calories
  stage-5-appearance-core
  stage-6-appearance-features
)

log() {
  printf "[%s] %s\n" "$(date '+%Y-%m-%d %H:%M:%S')" "$*"
}

cd "$REPO_DIR"

if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  log "Not a git repo: $REPO_DIR"
  exit 1
fi

while true; do
  if ! git diff --quiet || ! git diff --cached --quiet; then
    log "Working tree not clean; skipping this cycle."
    sleep 300
    continue
  fi

  git fetch "$REMOTE" >/dev/null 2>&1 || true

  next_stage=""
  for stage in "${STAGES[@]}"; do
    if ! git show-ref --verify --quiet "refs/heads/$stage"; then
      if git show-ref --verify --quiet "refs/remotes/$REMOTE/$stage"; then
        git branch "$stage" "$REMOTE/$stage"
      else
        continue
      fi
    fi
    if git merge-base --is-ancestor "$stage" "$MAIN_BRANCH"; then
      continue
    fi
    next_stage="$stage"
    break
  done

  if [[ -z "$next_stage" ]]; then
    log "No remaining stages to merge. Exiting."
    exit 0
  fi

  log "Merging $next_stage into $MAIN_BRANCH"
  git checkout "$MAIN_BRANCH" >/dev/null
  git merge --no-ff "$next_stage" -m "Merge $next_stage" >/dev/null
  git push "$REMOTE" "$MAIN_BRANCH"
  log "Pushed $MAIN_BRANCH to $REMOTE"

  jitter=$((RANDOM % 1801)) # 0..1800 sec (0..30m)
  if (( RANDOM % 2 == 0 )); then
    sleep_for=$((7200 - jitter))
  else
    sleep_for=$((7200 + jitter))
  fi
  log "Sleeping ${sleep_for}s"
  sleep "$sleep_for"
done
