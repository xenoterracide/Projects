#!/usr/bin/env bash
# SPDX-FileCopyrightText: Copyright © 2025 Caleb Cushing
#
# SPDX-License-Identifier: MIT

# A small helper to execute a command in every git submodule (and optionally in root).
#
# Usage:
#   scripts/run-in-submodules.sh [-r] [-p N] [-n] -- <command> [args...]
#
# Options:
#   -r        Also run the command once in the repository root (default: off)
#   -p N      Run up to N submodules in parallel (default: 1 = sequential)
#   -n        Dry run: print what would be executed without running it
#   -h        Show this help and exit
#
# Examples:
#   scripts/run-in-submodules.sh -- git status -sb
#   scripts/run-in-submodules.sh -r -- git fetch --all --prune
#   scripts/run-in-submodules.sh -p 4 -- git checkout -B chore/update
#   scripts/run-in-submodules.sh -n -- make ci-build

set -euo pipefail

print_help() { sed -n '1,40p' "$0" | sed 's/^# \{0,1\}//'; }

run_root=false
parallel=1
dry_run=false

while getopts ":rp:nh" opt; do
  case "$opt" in
    r) run_root=true ;;
    p) parallel="$OPTARG" ;;
    n) dry_run=true ;;
    h) print_help; exit 0 ;;
    :) echo "Option -$OPTARG requires an argument" >&2; exit 2 ;;
    \?) echo "Unknown option: -$OPTARG" >&2; print_help; exit 2 ;;
  esac
done
shift $((OPTIND-1))

if [[ "$#" -eq 0 ]]; then
  echo "Error: missing command to run. Use -- to separate options from the command." >&2
  print_help
  exit 2
fi

# Ensure we are at repo root with .gitmodules (optional but helpful)
if [[ ! -f .gitmodules ]]; then
  echo "Warning: .gitmodules not found in current directory $(pwd). Proceeding anyway..." >&2
fi

# Collect submodule paths from git
mapfile -t submodules < <(git config --file .gitmodules --get-regexp path | awk '{print $2}')

if [[ ${#submodules[@]} -eq 0 ]]; then
  echo "No submodules found." >&2
  exit 0
fi

# Function to execute in a submodule directory
run_in_dir() {
  local dir="$1"; shift
  if [[ ! -d "$dir/.git" && ! -f "$dir/.git" ]]; then
    echo "[SKIP] $dir is not a git repository (submodule not initialized?)" >&2
    return 0
  fi
  if $dry_run; then
    echo "[DRY-RUN] (cd $dir && $*)"
    return 0
  fi
  echo "[RUN] $dir: $*"
  ( cd "$dir" && "$@" )
}

# Optional run in root first
if $run_root; then
  if $dry_run; then
    echo "[DRY-RUN] (in root) $*"
  else
    echo "[RUN] (root): $*"
    "$@"
  fi
fi

# Parallel execution helper using xargs if available
# Note: When running interactive commands (e.g., gh that prompt for input),
# we must ensure stdin is attached to the terminal for the child process.
# - For sequential mode or when parallel=1, we simply run directly so prompts work.
# - For true parallelism (>1), GNU xargs usually closes stdin for children, which
#   breaks interactive prompts. To support prompts, we forward the TTY to each
#   child using </dev/tty if available. If no TTY is present (non-interactive CI),
#   this will still work for non-interactive commands but interactive ones will fail
#   as expected.
if [[ "$parallel" -le 1 ]]; then
  # Sequential: preserve stdin/tty for interactive commands
  for sm in "${submodules[@]}"; do
    run_in_dir "$sm" "$@"
  done
elif command -v xargs >/dev/null 2>&1; then
  export -f run_in_dir
  export dry_run
  # Detect TTY; use it to attach stdin to children
  if [[ -t 0 ]] && [[ -e /dev/tty ]]; then
    printf '%s\n' "${submodules[@]}" | xargs -I{} -P "$parallel" bash -lc 'run_in_dir "$@" </dev/tty' _ {} "$@"
  else
    # No TTY available: still run in parallel, but interactive prompts will not work
    printf '%s\n' "${submodules[@]}" | xargs -I{} -P "$parallel" bash -c 'run_in_dir "$@"' _ {} "$@"
  fi
else
  # Fallback sequential
  for sm in "${submodules[@]}"; do
    run_in_dir "$sm" "$@"
  done
fi
