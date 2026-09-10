#!/bin/sh
set -eu

PROGRAM="zprompt"
RAW_BASE="${ZPROMPT_RAW_BASE:-https://raw.githubusercontent.com/angelozangari/zprompt/main}"

MARK_BEGIN="# >>> zprompt >>>"
MARK_END="# <<< zprompt <<<"

shell_arg=""
dest_arg=""
rc_arg=""
machine_name_arg=""
machine_class_arg=""

non_interactive=0
assume_yes=0

usage() {
  cat <<'EOF'
usage: install.sh [options]

options:
  --shell zsh|bash
  --dest PATH
  --rc PATH
  --machine-name NAME
  --machine-class client|gpu|storage|generic
  --non-interactive
  --yes
  --help

examples:

  interactive:
    ./install.sh

  remote:
    curl -fsSL https://zprompt.angelozangari.com | sh

  declarative:
    ./install.sh \
      --shell bash \
      --machine-name zserver04 \
      --machine-class gpu \
      --non-interactive

environment:

  ZPROMPT_RAW_BASE
    override the remote source base url
EOF
}

die() {
  printf '%s: %s\n' "$PROGRAM" "$*" >&2
  exit 1
}

have_tty() {
  [ -r /dev/tty ] && [ -w /dev/tty ]
}

ask() {
  label=$1
  default=$2

  [ "$non_interactive" -eq 0 ] ||
    die "missing required value for: $label"

  have_tty ||
    die "cannot prompt for $label without a tty; use flags or --non-interactive"

  if [ -n "$default" ]; then
    printf '%s [%s]: ' "$label" "$default" >/dev/tty
  else
    printf '%s: ' "$label" >/dev/tty
  fi

  IFS= read -r answer </dev/tty || answer=""

  if [ -n "$answer" ]; then
    printf '%s\n' "$answer"
  else
    printf '%s\n' "$default"
  fi
}

confirm() {
  [ "$assume_yes" -eq 0 ] || return 0
  [ "$non_interactive" -eq 0 ] || return 0

  have_tty || die "cannot confirm installation without a tty; use --yes"

  printf 'install? [Y/n]: ' >/dev/tty
  IFS= read -r answer </dev/tty || answer=""

  case "$answer" in
    ""|y|Y|yes|YES)
      ;;
    *)
      printf 'cancelled\n'
      exit 0
      ;;
  esac
}

expand_home() {
  case "$1" in
    "~")
      printf '%s\n' "$HOME"
      ;;
    "~/"*)
      printf '%s/%s\n' "$HOME" "${1#~/}"
      ;;
    *)
      printf '%s\n' "$1"
      ;;
  esac
}

validate_shell() {
  case "$1" in
    zsh|bash)
      ;;
    *)
      die "unsupported shell '$1'; expected zsh or bash"
      ;;
  esac
}

validate_machine_class() {
  case "$1" in
    client|gpu|storage|generic)
      ;;
    *)
      die "invalid machine class '$1'; expected client, gpu, storage, or generic"
      ;;
  esac
}

validate_machine_name() {
  case "$1" in
    "")
      die "machine name cannot be empty"
      ;;
    *[!A-Za-z0-9._-]*)
      die "machine name may contain only letters, digits, ., _, and -"
      ;;
  esac
}

read_machine_value() {
  key=$1
  file=$2

  [ -r "$file" ] || return 0

  sed -n "s/^${key}=//p" "$file" | tail -n 1
}

detect_shell() {
  detected=""

  if [ -n "${SHELL:-}" ]; then
    detected=${SHELL##*/}

    case "$detected" in
      zsh|bash)
        printf '%s\n' "$detected"
        return
        ;;
    esac
  fi

  return 1
}

detect_hostname() {
  hostname -s 2>/dev/null || hostname
}

script_dir() {
  [ -f "$0" ] || return 1

  dir=$(dirname -- "$0")
  (
    CDPATH=
    cd -- "$dir" 2>/dev/null
    pwd
  )
}

download_renderer() {
  shell=$1
  destination=$2

  local_dir=""

  if local_dir=$(script_dir 2>/dev/null); then
    local_file="$local_dir/prompt.$shell"

    if [ -r "$local_file" ]; then
      cp "$local_file" "$destination"
      return
    fi
  fi

  command -v curl >/dev/null 2>&1 ||
    die "curl is required for remote installation"

  url="$RAW_BASE/prompt.$shell"

  printf 'downloading %s\n' "$url"
  curl -fsSL "$url" -o "$destination"
}

write_machine() {
  file=$1
  name=$2
  class=$3

  existing_name=$(read_machine_value "Z_MACHINE_NAME" "$file")
  existing_class=$(read_machine_value "Z_MACHINE_CLASS" "$file")

  if [ -f "$file" ] &&
     [ "$existing_name" = "$name" ] &&
     [ "$existing_class" = "$class" ]; then
    return
  fi

  tmp="${file}.tmp.$$"

  cat >"$tmp" <<EOF
Z_MACHINE_NAME=$name
Z_MACHINE_CLASS=$class
EOF

  chmod 0644 "$tmp"
  mv "$tmp" "$file"
}

escape_double_quotes() {
  printf '%s' "$1" | sed 's/[\\`"$]/\\&/g'
}

update_rc() {
  rc=$1
  machine_file=$2
  prompt_file=$3

  rc_dir=$(dirname -- "$rc")
  mkdir -p "$rc_dir"

  [ -e "$rc" ] || : >"$rc"

  begin_count=$(grep -Fxc "$MARK_BEGIN" "$rc" 2>/dev/null || true)
  end_count=$(grep -Fxc "$MARK_END" "$rc" 2>/dev/null || true)

  if [ "$begin_count" -ne "$end_count" ] ||
     [ "$begin_count" -gt 1 ]; then
    die "malformed existing zprompt block in $rc"
  fi

  tmp="${rc}.zprompt.tmp.$$"

  awk \
    -v begin="$MARK_BEGIN" \
    -v end="$MARK_END" '
      $0 == begin { skip = 1; next }
      $0 == end   { skip = 0; next }
      !skip       { print }
    ' "$rc" >"$tmp"

  machine_escaped=$(escape_double_quotes "$machine_file")
  prompt_escaped=$(escape_double_quotes "$prompt_file")

  {
    printf '\n%s\n' "$MARK_BEGIN"
    printf 'source "%s"\n' "$machine_escaped"
    printf 'source "%s"\n' "$prompt_escaped"
    printf '%s\n' "$MARK_END"
  } >>"$tmp"

  mv "$tmp" "$rc"
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --shell)
      [ "$#" -ge 2 ] || die "--shell requires a value"
      shell_arg=$2
      shift 2
      ;;
    --shell=*)
      shell_arg=${1#*=}
      shift
      ;;
    --dest)
      [ "$#" -ge 2 ] || die "--dest requires a value"
      dest_arg=$2
      shift 2
      ;;
    --dest=*)
      dest_arg=${1#*=}
      shift
      ;;
    --rc)
      [ "$#" -ge 2 ] || die "--rc requires a value"
      rc_arg=$2
      shift 2
      ;;
    --rc=*)
      rc_arg=${1#*=}
      shift
      ;;
    --machine-name)
      [ "$#" -ge 2 ] || die "--machine-name requires a value"
      machine_name_arg=$2
      shift 2
      ;;
    --machine-name=*)
      machine_name_arg=${1#*=}
      shift
      ;;
    --machine-class)
      [ "$#" -ge 2 ] || die "--machine-class requires a value"
      machine_class_arg=$2
      shift 2
      ;;
    --machine-class=*)
      machine_class_arg=${1#*=}
      shift
      ;;
    --non-interactive)
      non_interactive=1
      shift
      ;;
    --yes|-y)
      assume_yes=1
      shift
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    *)
      die "unknown argument: $1"
      ;;
  esac
done

if [ -n "$shell_arg" ]; then
  selected_shell=${shell_arg##*/}
else
  detected_shell=$(detect_shell 2>/dev/null || true)

  if [ "$non_interactive" -eq 1 ]; then
    [ -n "$detected_shell" ] ||
      die "could not detect shell; pass --shell"
    selected_shell=$detected_shell
  else
    selected_shell=$(ask "shell (zsh/bash)" "$detected_shell")
  fi
fi

validate_shell "$selected_shell"

default_dest="${XDG_CONFIG_HOME:-$HOME/.config}/zprompt"

if [ -n "$dest_arg" ]; then
  dest=$dest_arg
elif [ "$non_interactive" -eq 1 ]; then
  dest=$default_dest
else
  dest=$(ask "install location" "$default_dest")
fi

dest=$(expand_home "$dest")

case "$selected_shell" in
  zsh)
    default_rc="$HOME/.zshrc"
    ;;
  bash)
    default_rc="$HOME/.bashrc"
    ;;
esac

if [ -n "$rc_arg" ]; then
  rc=$rc_arg
elif [ "$non_interactive" -eq 1 ]; then
  rc=$default_rc
else
  rc=$(ask "shell config" "$default_rc")
fi

rc=$(expand_home "$rc")

machine_file="$dest/machine"

existing_name=$(read_machine_value "Z_MACHINE_NAME" "$machine_file")
existing_class=$(read_machine_value "Z_MACHINE_CLASS" "$machine_file")

default_name=$existing_name

if [ -z "$default_name" ]; then
  default_name=$(detect_hostname)
fi

if [ -n "$machine_name_arg" ]; then
  machine_name=$machine_name_arg
elif [ "$non_interactive" -eq 1 ]; then
  machine_name=$default_name
else
  machine_name=$(ask "machine name" "$default_name")
fi

validate_machine_name "$machine_name"

if [ -n "$machine_class_arg" ]; then
  machine_class=$machine_class_arg
elif [ -n "$existing_class" ]; then
  if [ "$non_interactive" -eq 1 ]; then
    machine_class=$existing_class
  else
    machine_class=$(ask \
      "machine class (client/gpu/storage/generic)" \
      "$existing_class")
  fi
elif [ "$non_interactive" -eq 1 ]; then
  die "--machine-class is required for a new non-interactive installation"
else
  case "$selected_shell" in
    zsh)  class_default="client" ;;
    bash) class_default="generic" ;;
  esac

  machine_class=$(ask \
    "machine class (client/gpu/storage/generic)" \
    "$class_default")
fi

validate_machine_class "$machine_class"

prompt_file="$dest/prompt.$selected_shell"

printf '\n'
printf 'shell          %s\n' "$selected_shell"
printf 'destination    %s\n' "$dest"
printf 'shell config   %s\n' "$rc"
printf 'machine name   %s\n' "$machine_name"
printf 'machine class  %s\n' "$machine_class"
printf '\n'

confirm

mkdir -p "$dest"

tmp_renderer="$dest/.prompt.$selected_shell.tmp.$$"

cleanup() {
  rm -f "$tmp_renderer"
}

trap cleanup EXIT HUP INT TERM

download_renderer "$selected_shell" "$tmp_renderer"

chmod 0644 "$tmp_renderer"
mv "$tmp_renderer" "$prompt_file"

write_machine \
  "$machine_file" \
  "$machine_name" \
  "$machine_class"

update_rc \
  "$rc" \
  "$machine_file" \
  "$prompt_file"

trap - EXIT HUP INT TERM

printf '\ninstalled zprompt\n\n'
printf '  prompt   %s\n' "$prompt_file"
printf '  machine  %s\n' "$machine_file"
printf '  rc       %s\n' "$rc"
printf '\nreload with:\n\n'
printf '  source "%s"\n\n' "$rc"
