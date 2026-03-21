#!/usr/bin/env bash

set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$repo_root"

if [[ -x "$repo_root/setup" ]]; then
  setup_cmd=("$repo_root/setup")
else
  printf 'No setup entrypoint found. Expected ./setup\n' >&2
  exit 1
fi

if ! git diff --quiet || ! git diff --cached --quiet; then
  printf 'Working tree is dirty. Commit or stash your changes before updating.\n' >&2
  exit 1
fi

current_branch="$(git branch --show-current)"
if [[ -z "$current_branch" ]]; then
  printf 'Detached HEAD is not supported. Check out a branch first.\n' >&2
  exit 1
fi

printf 'Fetching fork and upstream...\n'
git fetch --prune origin
git fetch --prune upstream

printf 'Fast-forwarding %s from origin/%s...\n' "$current_branch" "$current_branch"
git pull --ff-only origin "$current_branch"

printf 'Integrating upstream/main...\n'
merged_upstream=false
if git merge --ff-only upstream/main; then
  merged_upstream=true
  printf 'Upstream integrated with a fast-forward.\n'
elif git merge --no-edit upstream/main; then
  merged_upstream=true
  printf 'Upstream merged successfully.\n'
else
  printf '\nMerge conflicts detected while integrating upstream/main.\n' >&2
  printf 'Resolve them in %s, then run:\n' "$repo_root" >&2
  printf '  git add <resolved-files>\n' >&2
  printf '  git commit\n' >&2
  printf '  git push origin %s\n' "$current_branch" >&2
  printf '  %s install\n' "${setup_cmd[0]}" >&2
  exit 1
fi

if [[ "$merged_upstream" == true ]]; then
  printf 'Pushing %s to origin...\n' "$current_branch"
  git push origin "$current_branch"
fi

printf 'Running installer...\n'
"${setup_cmd[@]}" install
