# This script is meant to be sourced.
# It's not for directly running.

# shellcheck shell=bash

# The run is in steps, and the first of them may replace this very file: a pull
# brings the new version of the updater along with everything else. So once
# something has been pulled the rest is left to the new version, started on the
# commit that was there before (--continue-from), rather than read on from a
# file that has changed underneath.

UPDATE_STAMP="${XDG_STATE_HOME}/yuki/updated"

# How the repository stands against its remote, one fact a line, tab between a
# key and its value. Read by the shell as well as printed for a person:
#
#   repository  <path>
#   branch      <name>, or empty when detached
#   state       ok, dirty, detached, no-upstream, unreachable or diverged
#   behind      how many commits the remote has that this does not
#   ahead       how many this has that the remote does not
#   commit      <short hash> <subject>, one line for each commit behind
#
# dirty: tracked files changed here, which a pull would have to go over.
# unreachable: the fetch failed, so the counts are those of the last fetch.
function update_status(){
  local branch state="ok" behind=0 ahead=0
  printf 'repository\t%s\n' "$REPO_ROOT"
  branch="$(git -C "$REPO_ROOT" symbolic-ref --quiet --short HEAD 2> /dev/null || true)"
  printf 'branch\t%s\n' "$branch"
  if [[ -z "$branch" ]]; then
    state="detached"
  elif ! git -C "$REPO_ROOT" rev-parse --abbrev-ref '@{upstream}' > /dev/null 2>&1; then
    state="no-upstream"
  else
    # Never a prompt for a password: the shell asks with nobody to answer.
    if ! GIT_TERMINAL_PROMPT=0 timeout 60 git -C "$REPO_ROOT" fetch --quiet 2> /dev/null; then
      state="unreachable"
    fi
    behind="$(git -C "$REPO_ROOT" rev-list --count 'HEAD..@{upstream}' 2> /dev/null || echo 0)"
    ahead="$(git -C "$REPO_ROOT" rev-list --count '@{upstream}..HEAD' 2> /dev/null || echo 0)"
    if [[ "$state" == "ok" ]]; then
      if (( behind > 0 && ahead > 0 )); then
        state="diverged"
      elif [[ -n "$(git -C "$REPO_ROOT" status --porcelain --untracked-files=no 2> /dev/null)" ]]; then
        state="dirty"
      fi
    fi
  fi
  printf 'state\t%s\n' "$state"
  printf 'behind\t%s\n' "$behind"
  printf 'ahead\t%s\n' "$ahead"
  if (( behind > 0 )); then
    git -C "$REPO_ROOT" log --max-count=50 --format='commit%x09%h%x09%s' 'HEAD..@{upstream}' 2> /dev/null || true
  fi
  return 0
}

function update_heading(){
  printf "\n${STY_CYAN}${STY_BOLD}%s${STY_RST}\n" "$1"
}

# Pulls when there is something to pull and nothing in the way, and then sets
# UPDATE_PULLED_FROM to the commit it started from. Set rather than printed:
# the commands it runs say what they do on standard output.
UPDATE_PULLED_FROM=""
function update_pull(){
  local status state behind before
  status="$(update_status)"
  state="$(awk -F'\t' '$1 == "state" {print $2}' <<< "$status")"
  behind="$(awk -F'\t' '$1 == "behind" {print $2}' <<< "$status")"
  case "$state" in
    detached)
      printf "${STY_YELLOW}The repository is not on a branch, so there is nothing to pull into. Left as it is.${STY_RST}\n" >&2
      return 0 ;;
    no-upstream)
      printf "${STY_YELLOW}The branch follows no remote branch, so there is nothing to pull. Left as it is.${STY_RST}\n" >&2
      return 0 ;;
    unreachable)
      printf "${STY_YELLOW}The remote could not be reached. YukiUI is left as it is.${STY_RST}\n" >&2
      return 0 ;;
    diverged)
      printf "${STY_YELLOW}This branch and the remote have both moved on, so pulling would mean merging. Left as it is, for you to sort out.${STY_RST}\n" >&2
      return 0 ;;
    dirty)
      if (( behind > 0 )); then
        printf "${STY_YELLOW}There are changes in the repository that are not committed, and a pull would have to go over them:${STY_RST}\n" >&2
        git -C "$REPO_ROOT" status --short --untracked-files=no >&2
        printf "${STY_YELLOW}Commit or stash them and update again. YukiUI is left as it is.${STY_RST}\n" >&2
        return 0
      fi ;;
  esac
  if (( behind == 0 )); then
    printf "${STY_GREEN}YukiUI is up to date.${STY_RST}\n" >&2
    return 0
  fi
  printf "${STY_BLUE}%s new changes:${STY_RST}\n" "$behind" >&2
  awk -F'\t' '$1 == "commit" {printf "  %s  %s\n", $2, $3}' <<< "$status" >&2
  before="$(git -C "$REPO_ROOT" rev-parse HEAD)"
  x git -C "$REPO_ROOT" pull --ff-only
  x git -C "$REPO_ROOT" submodule update --init --recursive
  UPDATE_PULLED_FROM="$before"
}

function update_system(){
  if [[ "$UPDATE_SYSTEM" != true ]]; then
    printf "Left alone, as asked.\n"
    return 0
  fi
  if ! command -v pacman > /dev/null 2>&1; then
    printf "${STY_YELLOW}This is not an Arch system. Update its packages the way your distribution does.${STY_RST}\n"
    return 0
  fi
  # yay and paru take the AUR along with the repositories.
  if command -v yay > /dev/null 2>&1; then
    x yay -Syu
  elif command -v paru > /dev/null 2>&1; then
    x paru -Syu
  else
    x sudo pacman -Syu
  fi
}

# The packages built from this repository: each one whose PKGBUILD builds
# something other than what is installed, and the plugins also when their
# sources were pulled, since those are read from outside the PKGBUILD's own
# directory and moved on without a new version more than once.
function update_local_packages(){
  local since="$1" dir name
  local -a stale=()
  if ! command -v pacman > /dev/null 2>&1; then
    printf "Nothing to build here: these are Arch packages.\n"
    return 0
  fi
  source ./sdata/dist-arch/local-packages.sh
  for dir in "${LOCAL_PKGBUILDS[@]}"; do
    name="$(local_pkgbuild_name "$dir")"
    if local_pkgbuild_outdated "$dir"; then
      stale+=("$dir")
    elif [[ "$name" == "yuki-hyprland-plugins" && -n "$since" ]] \
      && [[ -n "$(git -C "$REPO_ROOT" diff --name-only "$since" HEAD -- hypr-plugins helpers)" ]]; then
      stale+=("$dir")
    fi
  done
  if (( ${#stale[@]} == 0 )); then
    printf "${STY_GREEN}Every one of them is up to date.${STY_RST}\n"
    return 0
  fi
  if ! command -v yay > /dev/null 2>&1; then
    printf "${STY_YELLOW}These need building, and yay is not installed to build them: %s${STY_RST}\n" "${stale[*]##*/}"
    printf "${STY_YELLOW}Run ./setup install-deps to install it along with them.${STY_RST}\n"
    return 0
  fi
  export PACMAN_AUTH="${PACMAN_AUTH:-sudo}"
  for dir in "${stale[@]}"; do
    printf "${STY_BLUE}Building %s${STY_RST}\n" "$(local_pkgbuild_name "$dir")"
    install-local-pkgbuild "$dir" "--needed --noconfirm"
  done
}

function update_files(){
  # A process of its own: the install step is written to be run by setup, and
  # this keeps its options and its traps out of the update's way. The desktops
  # already installed are kept, which is what it does when not told otherwise.
  x "$REPO_ROOT/setup" install-files -f
}

function update_finish(){
  mkdir -p "$(dirname "$UPDATE_STAMP")"
  date +%s > "$UPDATE_STAMP"
  update_heading "Done"
  printf "The shell picks up its new files by itself. If something looks off, restart it with Ctrl+Super+R.\n"
  if [[ -t 0 ]]; then
    read -r -p "Press Enter to close. " _
  fi
}

#####################################################################################

if [[ "$UPDATE_CHECK" == true ]]; then
  update_status
  exit 0
fi

ask=false

if [[ -z "$UPDATE_CONTINUE_FROM" ]]; then
  update_heading "1/4  YukiUI"
  update_pull
  if [[ -n "$UPDATE_PULLED_FROM" ]]; then
    printf "${STY_BLUE}Pulled. Going on with the new version of the updater.${STY_RST}\n"
    continue_args=(--continue-from "$UPDATE_PULLED_FROM")
    if [[ "$UPDATE_SYSTEM" != true ]]; then continue_args+=(--no-system); fi
    exec "$REPO_ROOT/setup" update "${continue_args[@]}"
  fi
fi

update_heading "2/4  System packages"
update_system

update_heading "3/4  Packages built from this repository"
update_local_packages "$UPDATE_CONTINUE_FROM"

update_heading "4/4  Files"
if [[ -n "$UPDATE_CONTINUE_FROM" || "$UPDATE_FILES" == true ]]; then
  update_files
else
  printf "Nothing was pulled, so the files on the machine are already these.\n"
fi

update_finish
