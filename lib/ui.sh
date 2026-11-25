# shellcheck shell=bash
# shellcheck disable=SC2016,SC2034
# UI helpers: colours, logging, prompts. Bash 3.2 compatible (macOS default bash).

if [ -t 1 ] && [ -z "${NO_COLOR:-}" ]; then
  C_BOLD=$'\033[1m'; C_DIM=$'\033[2m'; C_GREEN=$'\033[32m'; C_YELLOW=$'\033[33m'
  C_RED=$'\033[31m'; C_CYAN=$'\033[36m'; C_RESET=$'\033[0m'
else
  C_BOLD=''; C_DIM=''; C_GREEN=''; C_YELLOW=''; C_RED=''; C_CYAN=''; C_RESET=''
fi

info()  { printf '%s▸%s %s\n' "$C_CYAN" "$C_RESET" "$*"; }
ok()    { printf '%s✓%s %s\n' "$C_GREEN" "$C_RESET" "$*"; }
warn()  { printf '%s!%s %s\n' "$C_YELLOW" "$C_RESET" "$*" >&2; }
die()   { printf '%s✗ %s%s\n' "$C_RED" "$*" "$C_RESET" >&2; exit 1; }
title() { printf '\n%s%s%s\n' "$C_BOLD" "$*" "$C_RESET"; }

# heredoc VAR <<'EOF' ... EOF  — read a quoted heredoc into VAR (bash 3.2 safe).
heredoc() { IFS= read -r -d '' "$1" || true; printf -v "$1" '%s' "${!1%$'\n'}"; }

_tty_read() {
  # _tty_read VAR "prompt"
  local __p=$2 __a=''
  if [ -r /dev/tty ]; then
    IFS= read -r -p "$__p" __a </dev/tty || true
  else
    IFS= read -r -p "$__p" __a || true
  fi
  printf -v "$1" '%s' "$__a"
}

# ask VAR "Question" "default"  — free text. Skipped when VAR is already set.
ask() {
  local __var=$1 __q=$2 __def=${3-} __ans
  if [ -n "${!__var-}" ]; then return 0; fi
  if [ "${NONINTERACTIVE:-0}" = 1 ]; then printf -v "$__var" '%s' "$__def"; return 0; fi
  _tty_read __ans "${C_BOLD}?${C_RESET} ${__q}${__def:+ ${C_DIM}[${__def}]${C_RESET}}: "
  printf -v "$__var" '%s' "${__ans:-$__def}"
}

# confirm VAR "Question" y|n  — sets VAR to y or n.
confirm() {
  local __var=$1 __q=$2 __def=${3:-n} __ans
  if [ -n "${!__var-}" ]; then
    case "${!__var}" in y|Y|yes|true|1) printf -v "$__var" y ;; *) printf -v "$__var" n ;; esac
    return 0
  fi
  if [ "${NONINTERACTIVE:-0}" = 1 ]; then printf -v "$__var" '%s' "$__def"; return 0; fi
  local hint='y/N'; [ "$__def" = y ] && hint='Y/n'
  while :; do
    _tty_read __ans "${C_BOLD}?${C_RESET} ${__q} ${C_DIM}(${hint})${C_RESET}: "
    __ans=${__ans:-$__def}
    case "$__ans" in
      y|Y|yes|YES) printf -v "$__var" y; return 0 ;;
      n|N|no|NO)   printf -v "$__var" n; return 0 ;;
    esac
  done
}

# choose VAR "Question" DEFAULT_ID "id|Label" "id|Label" ...  — single choice.
choose() {
  local __var=$1 __q=$2 __def=$3; shift 3
  local __opts=("$@"); local __i __id __label __ans __n=${#__opts[@]}
  if [ -n "${!__var-}" ]; then
    for __i in "${__opts[@]}"; do [ "${__i%%|*}" = "${!__var}" ] && return 0; done
    die "Invalid value '${!__var}' for: $__q (allowed: $(_ids "${__opts[@]}"))"
  fi
  if [ "${NONINTERACTIVE:-0}" = 1 ]; then printf -v "$__var" '%s' "$__def"; return 0; fi
  printf '%s?%s %s\n' "$C_BOLD" "$C_RESET" "$__q"
  local __defn=1
  for ((__i = 0; __i < __n; __i++)); do
    __id=${__opts[$__i]%%|*}; __label=${__opts[$__i]#*|}
    [ "$__id" = "$__def" ] && __defn=$((__i + 1))
    printf '   %s%2d)%s %s\n' "$C_CYAN" $((__i + 1)) "$C_RESET" "$__label"
  done
  while :; do
    _tty_read __ans "   choose [${__defn}]: "
    __ans=${__ans:-$__defn}
    if [[ "$__ans" =~ ^[0-9]+$ ]] && [ "$__ans" -ge 1 ] && [ "$__ans" -le "$__n" ]; then
      printf -v "$__var" '%s' "${__opts[$((__ans - 1))]%%|*}"
      return 0
    fi
  done
}

# choose_multi VAR "Question" "default ids (space sep)" "id|Label" ...  — sets VAR to space-separated ids, in the order picked.
choose_multi() {
  local __var=$1 __q=$2 __def=$3; shift 3
  local __opts=("$@"); local __i __id __label __ans __n=${#__opts[@]} __out='' __tok
  if [ -n "${!__var-}" ]; then
    local __v=${!__var//,/ }
    for __tok in $__v; do
      local __found=n
      for __i in "${__opts[@]}"; do [ "${__i%%|*}" = "$__tok" ] && __found=y; done
      [ $__found = y ] || die "Invalid value '$__tok' for: $__q (allowed: $(_ids "${__opts[@]}"))"
    done
    printf -v "$__var" '%s' "$__v"
    return 0
  fi
  if [ "${NONINTERACTIVE:-0}" = 1 ]; then printf -v "$__var" '%s' "$__def"; return 0; fi
  printf '%s?%s %s %s(comma-separated numbers; first = default)%s\n' "$C_BOLD" "$C_RESET" "$__q" "$C_DIM" "$C_RESET"
  local __defnums=''
  for ((__i = 0; __i < __n; __i++)); do
    __id=${__opts[$__i]%%|*}; __label=${__opts[$__i]#*|}
    for __tok in $__def; do [ "$__tok" = "$__id" ] && __defnums="${__defnums:+$__defnums,}$((__i + 1))"; done
    printf '   %s%2d)%s %s\n' "$C_CYAN" $((__i + 1)) "$C_RESET" "$__label"
  done
  while :; do
    _tty_read __ans "   choose [${__defnums}]: "
    __ans=${__ans:-$__defnums}
    __out=''
    local __bad=n
    for __tok in ${__ans//,/ }; do
      if [[ "$__tok" =~ ^[0-9]+$ ]] && [ "$__tok" -ge 1 ] && [ "$__tok" -le "$__n" ]; then
        __id=${__opts[$((__tok - 1))]%%|*}
        case " $__out " in *" $__id "*) ;; *) __out="${__out:+$__out }$__id" ;; esac
      else
        __bad=y
      fi
    done
    if [ $__bad = n ] && [ -n "$__out" ]; then printf -v "$__var" '%s' "$__out"; return 0; fi
  done
}

_ids() { local i o=''; for i in "$@"; do o="${o:+$o, }${i%%|*}"; done; printf '%s' "$o"; }

has_word() { case " $1 " in *" $2 "*) return 0 ;; esac; return 1; }
