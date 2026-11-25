# shellcheck shell=bash
# shellcheck disable=SC2016,SC2034
# Rendering and safe file writing.

# Bash >= 5.2 treats '&' in ${x//pat/rep} as "the match"; we need literal values.
shopt -u patsub_replacement 2>/dev/null || true

# Variables substituted by render(). Placeholders look like {{NAME}}.
RENDER_VARS=''
register_vars() { local v; for v in "$@"; do has_word "$RENDER_VARS" "$v" || RENDER_VARS="$RENDER_VARS $v"; done; }

# render < template  — replaces {{VAR}} for every registered VAR (two passes so values may contain placeholders).
render() {
  local __t __v __pass
  __t=$(cat; printf x); __t=${__t%x}
  for __pass in 1 2; do
    for __v in $RENDER_VARS; do
      __t=${__t//"{{$__v}}"/${!__v-}}
    done
  done
  printf '%s' "$__t"
}

# write_file often runs at the end of a pipeline (a subshell), so progress is kept in files.
BACKUP_DIR=".sdd-init-backup/$(date +%Y%m%d-%H%M%S)"
WRITE_LOG=$(mktemp "${TMPDIR:-/tmp}/sdd-init-log.XXXXXX")
BACKUP_LOG=$(mktemp "${TMPDIR:-/tmp}/sdd-init-bak.XXXXXX")
trap 'rm -f "$WRITE_LOG" "$BACKUP_LOG"' EXIT

_backup() {
  # _backup path  — copy an existing file into the run's backup folder (Spec Kit placeholders are not worth keeping).
  local f=$1
  [ -f "$f" ] || return 0
  grep -q '\[PROJECT_NAME\] Constitution' "$f" 2>/dev/null && return 0
  mkdir -p "$BACKUP_DIR/$(dirname "$f")"
  cp -p "$f" "$BACKUP_DIR/$f"
  printf '%s\n' "$f" >>"$BACKUP_LOG"
}

# write_file path  < content   — writes, backing up a different existing file first.
write_file() {
  local f=$1 tmp
  tmp=$(mktemp "${TMPDIR:-/tmp}/sdd-init.XXXXXX")
  cat >"$tmp"
  if [ -f "$f" ] && cmp -s "$tmp" "$f"; then rm -f "$tmp"; return 0; fi
  if [ "${DRY_RUN:-0}" = 1 ]; then rm -f "$tmp"; info "would write $f"; return 0; fi
  mkdir -p "$(dirname "$f")"
  _backup "$f"
  mv "$tmp" "$f"
  chmod 0644 "$f"
  printf '%s\n' "$f" >>"$WRITE_LOG"
}

# write_managed_block path  < content  — keep the rest of a user file, replace only our block.
MARK_START='<!-- sdd-init:start (managed by sdd-init; edit outside this block) -->'
MARK_END='<!-- sdd-init:end -->'
write_managed_block() {
  local f=$1 block before after
  block=$(cat; printf x); block=${block%x}
  block="$MARK_START
${block%$'\n'}
$MARK_END"
  if [ -f "$f" ]; then
    local cur; cur=$(cat "$f"; printf x); cur=${cur%x}
    case "$cur" in
      *"$MARK_START"*"$MARK_END"*)
        before=${cur%%"$MARK_START"*}
        after=${cur#*"$MARK_END"}
        printf '%s%s%s' "$before" "$block" "$after" | write_file "$f"
        ;;
      *)
        printf '%s\n\n%s\n' "${cur%$'\n'}" "$block" | write_file "$f"
        ;;
    esac
  else
    printf '%s\n' "$block" | write_file "$f"
  fi
}
