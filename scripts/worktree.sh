#!/usr/bin/env bash
set -euo pipefail
CMD="${1:-}"
case "$CMD" in
  NEW)
    ISSUE="${2:?Usage: worktree.sh NEW CTB-123 short-slug}"
    SLUG="${3:?Usage: worktree.sh NEW CTB-123 short-slug}"
    BRANCH="$ISSUE-$SLUG"
    git fetch origin
    mkdir -p .work
    git worktree add ".work/$BRANCH" origin/main
    cd ".work/$BRANCH"
    git switch -c "$BRANCH"
    echo "Created worktree .work/$BRANCH"
    ;;
  CLEAN)
    BRANCH="${2:?Usage: worktree.sh CLEAN CTB-123-short-slug}"
    git worktree remove ".work/$BRANCH"
    git branch -D "$BRANCH" || true
    ;;
  *)
    echo "Usage: worktree.sh NEW <ISSUEKEY> <slug> | CLEAN <branch>"
    exit 1
    ;;
esac
