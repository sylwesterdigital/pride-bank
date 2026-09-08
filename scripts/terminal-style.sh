#!/bin/zsh

if [[ -t 1 ]]; then
  PB_RESET=$'\033[0m'
  PB_MUTED=$'\033[2m'
  PB_GREEN=$'\033[32m'
  PB_YELLOW=$'\033[33m'
  PB_RED=$'\033[31m'
  PB_CYAN=$'\033[36m'
else
  PB_RESET=''
  PB_MUTED=''
  PB_GREEN=''
  PB_YELLOW=''
  PB_RED=''
  PB_CYAN=''
fi

pb_info() { printf '%b%s%b\n' "$PB_CYAN" "$*" "$PB_RESET"; }
pb_ok() { printf '%b%s%b\n' "$PB_GREEN" "$*" "$PB_RESET"; }
pb_warn() { printf '%b%s%b\n' "$PB_YELLOW" "$*" "$PB_RESET" >&2; }
pb_error() { printf '%b%s%b\n' "$PB_RED" "$*" "$PB_RESET" >&2; }
