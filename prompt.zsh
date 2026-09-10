# ---------- machine metadata ----------

[[ -r ~/.config/zprompt/machine ]] && source ~/.config/zprompt/machine

# ---------- history ----------

HISTFILE=~/.zsh_history
HISTSIZE=10000
SAVEHIST=10000

setopt HIST_IGNORE_DUPS
setopt SHARE_HISTORY


# ---------- research context ----------
#
# ctx scaling-law
# ctx
# ctx -
#
# Stored in .git/z-context, so it is:
# - per repository
# - per clone
# - never committed

ctx() {
  local gitdir
  gitdir=$(command git rev-parse --absolute-git-dir 2>/dev/null) || {
    print -u2 "ctx: not in a Git repository"
    return 1
  }

  local file="$gitdir/z-context"

  if (( $# == 0 )); then
    if [[ -r "$file" ]]; then
      print -r -- "$(<"$file")"
    else
      print "(none)"
    fi
    return
  fi

  if [[ "$1" == "-" && $# == 1 ]]; then
    rm -f -- "$file"
    return
  fi

  print -r -- "$*" >| "$file"
}


# ---------- prompt ----------

autoload -Uz add-zsh-hook

z_prompt_escape() {
  REPLY=${1//\%/%%}
}

z_prompt_update() {
  local machine=""
  local location
  local git_part=""
  local research_part=""

  # ----- execution-risk glyph -----

  local risk='%F{245}›%f'       # local: neutral

  if (( EUID == 0 )); then
    risk='%B%F{196}›%f%b'       # root: red
  elif [[ -n "${SSH_CONNECTION-}" || -n "${SSH_TTY-}" ]]; then
    risk='%F{214}›%f'           # SSH: amber
  fi


  # ----- machine / compute context -----
  
  local class=${Z_MACHINE_CLASS:-client}
  local name=${Z_MACHINE_NAME:-${HOST%%.*}}
  
  if [[ "$class" != "client" ]]; then
    local glyph
  
    case "$class" in
      gpu)     glyph='◆' ;;
      storage) glyph='▣' ;;
      *)       glyph='◇' ;;
    esac
  
    z_prompt_escape "$name"
    name=$REPLY
  
    machine="%F{45}${glyph}%f %F{245}${name}%f %F{240}·%f "
  fi

  # ----- Git / location -----

  local root
  root=$(command git rev-parse --show-toplevel 2>/dev/null)

  if [[ -n "$root" ]]; then
    local prefix repo branch git_status line code
    local dirty=0
    local staged=0
    local conflict=0

    repo=${root:t}
    prefix=$(command git rev-parse --show-prefix 2>/dev/null)

    local loc="$repo"
    [[ -n "$prefix" ]] && loc+="/${prefix%/}"

    z_prompt_escape "$loc"
    loc=$REPLY

    location="%F{39}${loc}%f"


    # Branch, or commit if HEAD is detached.

    branch=$(command git symbolic-ref --quiet --short HEAD 2>/dev/null)

    if [[ -z "$branch" ]]; then
      branch="@$(command git rev-parse --short HEAD 2>/dev/null)"
    fi


    # Working-tree state.

    git_status=$(command git status --porcelain 2>/dev/null)

    if [[ -n "$git_status" ]]; then
      dirty=1

      for line in ${(f)git_status}; do
        code=${line[1,2]}

        case "$code" in
          '??')
            ;;
          DD|AU|UD|UA|DU|AA|UU)
            conflict=1
            ;;
          *)
            [[ "${line[1]}" != ' ' ]] && staged=1
            ;;
        esac
      done
    fi


    # Branch color:
    # gray   = clean
    # yellow = changed
    # red    = conflicts

    local branch_color=245

    (( dirty ))    && branch_color=214
    (( conflict )) && branch_color=196

    z_prompt_escape "$branch"
    branch=$REPLY


    # Structural Git state.

    local symbols=""

    if (( conflict )); then
      symbols+='!'
    elif (( staged )); then
      symbols+='+'
    fi


    # Upstream topology.

    local upstream counts
    local ahead=0
    local behind=0

    upstream=$(command git rev-parse \
      --abbrev-ref \
      --symbolic-full-name '@{upstream}' 2>/dev/null)

    if [[ -n "$upstream" ]]; then
      counts=$(command git rev-list \
        --left-right \
        --count "${upstream}...HEAD" 2>/dev/null)

      if [[ -n "$counts" ]]; then
        behind=${counts%%[[:space:]]*}
        ahead=${counts##*[[:space:]]}
      fi

      if (( ahead > 0 && behind > 0 )); then
        symbols+='↕'
      elif (( ahead > 0 )); then
        symbols+='↑'
      elif (( behind > 0 )); then
        symbols+='↓'
      fi
    fi


    git_part=" %F{${branch_color}}${branch}%f"

    [[ -n "$symbols" ]] &&
      git_part+=" %F{245}${symbols}%f"


    # ----- research context -----

    local gitdir context
    gitdir=$(command git rev-parse --absolute-git-dir 2>/dev/null)

    if [[ -r "$gitdir/z-context" ]]; then
      IFS= read -r context < "$gitdir/z-context"

      if [[ -n "$context" ]]; then
        z_prompt_escape "$context"
        context=$REPLY
        research_part=" %F{141}⟨${context}⟩%f"
      fi
    fi

  else
    # Outside Git: ordinary cwd.
    location='%F{39}%~%f'
  fi


  PROMPT="${machine}${location}${git_part}${research_part} ${risk} "
}

add-zsh-hook precmd z_prompt_update
