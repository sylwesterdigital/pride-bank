#!/bin/zsh
if [[ -n "${PB_TERMINAL_STYLE_LOADED:-}" ]]; then return 0; fi
PB_TERMINAL_STYLE_LOADED=1
PB_C_RESET=''; PB_C_BOLD=''; PB_C_RED=''; PB_C_RED_BOLD=''; PB_C_GREEN=''; PB_C_GREEN_BOLD=''; PB_C_YELLOW=''; PB_C_YELLOW_BOLD=''; PB_C_BLUE_BOLD=''; PB_C_CYAN=''; PB_C_CYAN_BOLD=''; PB_C_WHITE_BOLD=''; PB_C_MUTED=''; PB_C_MAGENTA=''
if [[ -z "${NO_COLOR:-}" && "${TERM:-}" != "dumb" && ( -t 1 || "${FORCE_COLOR:-0}" == "1" ) ]]; then
  PB_C_RESET=$'\033[0m'; PB_C_BOLD=$'\033[1m'; PB_C_RED=$'\033[31m'; PB_C_RED_BOLD=$'\033[1;31m'; PB_C_GREEN=$'\033[32m'; PB_C_GREEN_BOLD=$'\033[1;32m'; PB_C_YELLOW=$'\033[33m'; PB_C_YELLOW_BOLD=$'\033[1;33m'; PB_C_BLUE_BOLD=$'\033[1;34m'; PB_C_CYAN=$'\033[36m'; PB_C_CYAN_BOLD=$'\033[1;36m'; PB_C_WHITE_BOLD=$'\033[1;37m'; PB_C_MUTED=$'\033[90m'; PB_C_MAGENTA=$'\033[35m'
fi
pb_section(){ printf '\n%b==>%b %b%s%b\n' "$PB_C_CYAN_BOLD" "$PB_C_RESET" "$PB_C_BOLD" "$*" "$PB_C_RESET"; }
pb_step(){ printf '%b→%b %s\n' "$PB_C_BLUE_BOLD" "$PB_C_RESET" "$*"; }
pb_info(){ printf '%b•%b %s\n' "$PB_C_CYAN" "$PB_C_RESET" "$*"; }
pb_success(){ printf '%b✓%b %b%s%b\n' "$PB_C_GREEN_BOLD" "$PB_C_RESET" "$PB_C_GREEN" "$*" "$PB_C_RESET"; }
pb_warn(){ printf '\n%bWARNING:%b %s\n' "$PB_C_YELLOW_BOLD" "$PB_C_RESET" "$*" >&2; }
pb_error(){ printf '\n%bERROR:%b %s\n' "$PB_C_RED_BOLD" "$PB_C_RESET" "$*" >&2; }
pb_field(){ local label="$1"; shift; printf '%b%-12s%b %s\n' "$PB_C_MUTED" "$label" "$PB_C_RESET" "$*"; }
pb_banner_info(){ printf '\n%b============================================================%b\n' "$PB_C_BLUE_BOLD" "$PB_C_RESET"; printf '%b%s%b\n' "$PB_C_WHITE_BOLD" "$*" "$PB_C_RESET"; printf '%b============================================================%b\n' "$PB_C_BLUE_BOLD" "$PB_C_RESET"; }
pb_banner_success(){ printf '\n%b============================================================%b\n' "$PB_C_GREEN_BOLD" "$PB_C_RESET"; printf '%b%s%b\n' "$PB_C_GREEN_BOLD" "$*" "$PB_C_RESET"; printf '%b============================================================%b\n' "$PB_C_GREEN_BOLD" "$PB_C_RESET"; }
pb_banner_error(){ printf '\n%b============================================================%b\n' "$PB_C_RED_BOLD" "$PB_C_RESET" >&2; printf '%b%s%b\n' "$PB_C_RED_BOLD" "$*" "$PB_C_RESET" >&2; printf '%b============================================================%b\n' "$PB_C_RED_BOLD" "$PB_C_RESET" >&2; }
