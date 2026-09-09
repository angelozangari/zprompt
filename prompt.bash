# ---------- machine metadata ----------

[[ -r ~/.config/zprompt/machine ]] && source ~/.config/zprompt/machine


# ---------- history ----------

HISTSIZE=10000
HISTFILESIZE=10000

shopt -s histappend

# Important: PS1 will contain Git/context strings.
# Prevent Bash from evaluating $(), variables, etc. embedded in them.
shopt -u promptvars


# ---------- research context ----------

ctx() {
  local gitdir

  gitdir=$(command git rev-parse --absolute-git-dir 2>/dev/null) || {
    printf '%s\n' "ctx: not in a Git repository" >&2
    return 1
  }

  local file="$gitdir/z-context"

  if (( $# == 0 )); then
    if [[ -r "$file" ]]; then
      cat -- "$file"
    else
      printf '%s\n' "(none)"
    fi
    return
  fi

  if [[ "$1" == "-" && $# == 1 ]]; then
    rm -f -- "$file"
    return
  fi

  printf '%s\n' "$*" > "$file"
}


# ---------- prompt ----------

b_prompt_update() {
  # ANSI colors wrapped in \[...\] so readline knows they have zero width.

  local reset='\[\e[0m\]'
  local bold='\[\e[1m\]'

  local gray='\[\e[38;5;245m\]'
  local darkgray='\[\e[38;5;240m\]'
  local blue='\[\e[38;5;39m\]'
  local cyan='\[\e[38;5;45m\]'
  local yellow='\[\e[38;5;214m\]'
  local red='\[\e[38;5;196m\]'
  local purple='\[\e[38;5;141m\]'

  local machine=""
  local location=""
  local git_part=""
  local research_part=""


  # ----- execution risk -----

  local risk="${gray}›${reset}"

  if (( EUID == 0 )); then
    risk="${bold}${red}›${reset}"
  elif [[ -n "${SSH_CONNECTION-}" || -n "${SSH_TTY-}" ]]; then
    risk="${yellow}›${reset}"
  fi


  # ----- machine / compute context -----

  local class=${Z_MACHINE_CLASS:-generic}
  local name=${Z_MACHINE_NAME:-${HOSTNAME%%.*}}

  if [[ "$class" != "client" ]]; then
    local glyph

    case "$class" in
      gpu)     glyph='◆' ;;
      storage) glyph='▣' ;;
      *)       glyph='◇' ;;
    esac

    machine="${cyan}${glyph}${reset} ${gray}${name}${reset} ${darkgray}·${reset} "
  fi


  # ----- Git / location -----

  local root
  root=$(command git rev-parse --show-toplevel 2>/dev/null)

  if [[ -n "$root" ]]; then
    local repo prefix loc
    local branch status
    local dirty=0
    local staged=0
    local conflict=0

    repo=${root##*/}
    prefix=$(command git rev-parse --show-prefix 2>/dev/null)

    loc="$repo"

    if [[ -n "$prefix" ]]; then
      loc+="/${prefix%/}"
    fi

    location="${blue}${loc}${reset}"


    # ----- branch / detached HEAD -----

    branch=$(command git symbolic-ref --quiet --short HEAD 2>/dev/null)

    if [[ -z "$branch" ]]; then
      branch="@$(command git rev-parse --short HEAD 2>/dev/null)"
    fi


    # ----- working-tree state -----

    status=$(command git status --porcelain 2>/dev/null)

    if [[ -n "$status" ]]; then
      dirty=1

      local line code

      while IFS= read -r line; do
        code=${line:0:2}

        case "$code" in
          '??')
            ;;

          DD|AU|UD|UA|DU|AA|UU)
            conflict=1
            ;;

          *)
            [[ "${line:0:1}" != " " ]] && staged=1
            ;;
        esac
      done <<< "$status"
    fi


    # ----- branch color -----

    local branch_color="$gray"

    (( dirty ))    && branch_color="$yellow"
    (( conflict )) && branch_color="$red"


    # ----- structural Git state -----

    local symbols=""

    if (( conflict )); then
      symbols+='!'
    elif (( staged )); then
      symbols+='+'
    fi


    # ----- upstream topology -----

    local upstream
    local ahead=0
    local behind=0

    upstream=$(command git rev-parse \
      --abbrev-ref \
      --symbolic-full-name '@{upstream}' 2>/dev/null)

    if [[ -n "$upstream" ]]; then
      read -r behind ahead < <(
        command git rev-list \
          --left-right \
          --count "${upstream}...HEAD" 2>/dev/null
      )

      if (( ahead > 0 && behind > 0 )); then
        symbols+='↕'
      elif (( ahead > 0 )); then
        symbols+='↑'
      elif (( behind > 0 )); then
        symbols+='↓'
      fi
    fi

    git_part=" ${branch_color}${branch}${reset}"

    if [[ -n "$symbols" ]]; then
      git_part+=" ${gray}${symbols}${reset}"
    fi


    # ----- research context -----

    local gitdir context

    gitdir=$(command git rev-parse --absolute-git-dir 2>/dev/null)

    if [[ -r "$gitdir/z-context" ]]; then
      IFS= read -r context < "$gitdir/z-context"

      if [[ -n "$context" ]]; then
        research_part=" ${purple}⟨${context}⟩${reset}"
      fi
    fi

  else
    # Bash's \w gives cwd with HOME abbreviated to ~.
    location="${blue}\w${reset}"
  fi


  PS1="${machine}${location}${git_part}${research_part} ${risk} "
}


# Run before every interactive prompt.

PROMPT_COMMAND=b_prompt_update
