# This script is meant to be sourced.
# It's not for directly running.

# shellcheck shell=bash

# The run is in steps, and the first of them may replace this very file: a pull
# brings the new version of the updater along with everything else. So once
# something has been pulled the rest is left to the new version, started on the
# commit that was there before (--continue-from), rather than read on from a
# file that has changed underneath.

UPDATE_STAMP="${XDG_STATE_HOME}/yuki/updated"

# Releases are annotated tags named for their day, YYYY.MM.DD, with .1, .2 for
# a second and a third on the same day. A lightweight tag of that shape, as the
# upstream's 2026.05.11, is not a release of YukiUI.
RELEASE_PATTERN='^[0-9]{4}\.[0-9]{2}\.[0-9]{2}(\.[0-9]+)?$'

# The channel this copy follows, kept in the repository's own git config:
# "stable", the latest release, which is what it follows unless told otherwise,
# or "main", every commit on the main branch.
function update_channel(){
  local channel
  channel="$(git -C "$REPO_ROOT" config --get yuki.channel 2> /dev/null || true)"
  [[ "$channel" == "main" ]] && echo main || echo stable
}

# The newest release, or nothing before the first.
function update_latest_release(){
  local type name
  while read -r type name; do
    if [[ "$type" == "tag" && "$name" =~ $RELEASE_PATTERN ]]; then
      echo "$name"
      return 0
    fi
  done < <(git -C "$REPO_ROOT" for-each-ref --sort=-v:refname --format='%(objecttype) %(refname:short)' refs/tags 2> /dev/null)
}

# The release this copy stands on, and how many commits it is past it: "<tag>
# <count>", or " <count>" before the first release.
function update_version(){
  local described
  described="$(git -C "$REPO_ROOT" describe --match '[0-9][0-9][0-9][0-9].[0-9][0-9].[0-9][0-9]*' --long 2> /dev/null || true)"
  if [[ "$described" =~ ^(.+)-([0-9]+)-g[0-9a-f]+$ ]]; then
    printf '%s\t%s\n' "${BASH_REMATCH[1]}" "${BASH_REMATCH[2]}"
  else
    printf '\t%s\n' "$(git -C "$REPO_ROOT" rev-list --count HEAD 2> /dev/null || echo 0)"
  fi
}

# How the repository stands against what its channel follows, one fact a line,
# tab between a key and its value. Read by the shell as well as printed for a
# person:
#
#   repository  <path>
#   channel     stable or main
#   version     <release> <commits past it>, the release empty before the first
#   latest      the newest release, or empty
#   branch      <name>, or empty when detached, as a release is checked out
#   state       ok, dirty, no-upstream, no-release, unreachable or diverged
#   behind      how many commits the target has that this does not
#   ahead       how many this has that the target does not
#   commit      <short hash> <subject>, one line for each commit behind
#
# The target is the latest release on the stable channel. On the main one it is
# the remote of the branch checked out, and of the main branch when none is, as
# after following releases: a branch of one's own is followed as it is, not
# swapped for main. A copy already past the latest release, as one that
# followed main, stays where it is on the stable channel until a newer release
# comes: a channel never takes it back.
# dirty: tracked files changed here, which a move would have to go over.
# unreachable: the fetch failed, so the counts are those of the last fetch.
function update_target(){
  local branch
  if [[ "$(update_channel)" == "stable" ]]; then
    local latest
    latest="$(update_latest_release)"
    [[ -n "$latest" ]] && echo "$latest^{commit}"
    return 0
  fi
  branch="$(git -C "$REPO_ROOT" symbolic-ref --quiet --short HEAD 2> /dev/null || echo main)"
  if git -C "$REPO_ROOT" rev-parse --verify --quiet "$branch@{upstream}" > /dev/null 2>&1; then
    echo "$branch@{upstream}"
  fi
}

function update_status(){
  local branch channel state="ok" behind=0 ahead=0 latest target=""
  channel="$(update_channel)"
  printf 'repository\t%s\n' "$REPO_ROOT"
  printf 'channel\t%s\n' "$channel"
  # Never a prompt for a password: the shell asks with nobody to answer.
  # Offline, nothing is fetched and the counts are those of the last fetch.
  if [[ "$UPDATE_OFFLINE" != true ]] \
    && ! GIT_TERMINAL_PROMPT=0 timeout 60 git -C "$REPO_ROOT" fetch --quiet --tags 2> /dev/null; then
    state="unreachable"
  fi
  latest="$(update_latest_release)"
  printf 'version\t%s\n' "$(update_version)"
  printf 'latest\t%s\n' "$latest"
  branch="$(git -C "$REPO_ROOT" symbolic-ref --quiet --short HEAD 2> /dev/null || true)"
  printf 'branch\t%s\n' "$branch"
  target="$(update_target)"
  if [[ -z "$target" && "$state" == "ok" ]]; then
    [[ "$channel" == "stable" ]] && state="no-release" || state="no-upstream"
  fi
  if [[ -n "$target" ]]; then
    behind="$(git -C "$REPO_ROOT" rev-list --count "HEAD..$target" 2> /dev/null || echo 0)"
    ahead="$(git -C "$REPO_ROOT" rev-list --count "$target..HEAD" 2> /dev/null || echo 0)"
    # Past the latest release on the stable channel is where it stays.
    if [[ "$channel" == "stable" ]] && (( behind == 0 )); then
      ahead=0
    fi
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
    git -C "$REPO_ROOT" log --max-count=50 --format='commit%x09%h%x09%s' "HEAD..$target" 2> /dev/null || true
  fi
  return 0
}

# A heading, and in an unattended run the line the shell reads the step from:
# "@yuki step <number> <of> <key>".
UPDATE_STEP=""
function update_heading(){
  printf "\n${STY_CYAN}${STY_BOLD}%s${STY_RST}\n" "$1"
  if [[ "$UPDATE_UNATTENDED" == true && -n "${2:-}" ]]; then
    UPDATE_STEP="$3"
    printf '@yuki step %s %s %s\n' "$2" 4 "$3"
  fi
}

# How the run ended, said as it ends, whatever ended it. The run that pulls
# leaves the rest to a new one in its place, which says it itself.
function update_ending(){
  local status=$?
  if (( status == 0 )); then
    printf '@yuki done\n'
  else
    printf '@yuki failed %s\n' "${UPDATE_STEP:-start}"
  fi
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
    no-release)
      printf "${STY_YELLOW}YukiUI has no release yet to follow. Left as it is.${STY_RST}\n" >&2
      return 0 ;;
    no-upstream)
      printf "${STY_YELLOW}This branch follows no remote branch, so there is nothing to pull. Left as it is.${STY_RST}\n" >&2
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
  if [[ "$(update_channel)" == "stable" ]]; then
    # The release itself, which leaves the repository on no branch.
    x git -C "$REPO_ROOT" checkout --quiet --detach "$(update_latest_release)"
  else
    # Back on the main branch from a release it was left on, and on with
    # whichever branch it is on.
    if ! git -C "$REPO_ROOT" symbolic-ref --quiet HEAD > /dev/null 2>&1; then
      x git -C "$REPO_ROOT" checkout --quiet main
    fi
    x git -C "$REPO_ROOT" merge --ff-only --quiet '@{upstream}'
  fi
  x git -C "$REPO_ROOT" submodule update --init --recursive
  UPDATE_PULLED_FROM="$before"
}

function update_system(){
  if [[ "$UPDATE_SYSTEM" != true ]]; then
    printf "Left alone, as asked.\n"
    return 0
  fi
  local -a args=()
  if [[ "$UPDATE_UNATTENDED" == true ]]; then args+=(--unattended); fi
  if [[ "$UPDATE_AUR" != true ]]; then args+=(--no-aur); fi
  x bash "$REPO_ROOT/dots/.config/quickshell/yuki/scripts/system/update-packages.sh" "${args[@]}"
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
  if [[ "$UPDATE_UNATTENDED" == true ]]; then
    # sudo where it asks for no password, and polkit's prompt otherwise.
    if command -v sudo > /dev/null 2>&1 && sudo -n true > /dev/null 2>&1; then
      export PACMAN_AUTH="${PACMAN_AUTH:-sudo}"
    else
      export PACMAN_AUTH="${PACMAN_AUTH:-pkexec}"
    fi
  else
    export PACMAN_AUTH="${PACMAN_AUTH:-sudo}"
  fi
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

# Switched to another channel first, by a person or by the shell's settings.
if [[ -n "$UPDATE_SET_CHANNEL" ]]; then
  git -C "$REPO_ROOT" config yuki.channel "$UPDATE_SET_CHANNEL"
fi

if [[ "$UPDATE_CHECK" == true ]]; then
  update_status
  exit 0
fi

ask=false
if [[ "$UPDATE_UNATTENDED" == true ]]; then trap update_ending EXIT; fi

if [[ -z "$UPDATE_CONTINUE_FROM" ]]; then
  update_heading "1/4  YukiUI" 1 shell
  update_pull
  if [[ -n "$UPDATE_PULLED_FROM" ]]; then
    printf "${STY_BLUE}Pulled. Going on with the new version of the updater.${STY_RST}\n"
    continue_args=(--continue-from "$UPDATE_PULLED_FROM")
    if [[ "$UPDATE_SYSTEM" != true ]]; then continue_args+=(--no-system); fi
    if [[ "$UPDATE_AUR" != true ]]; then continue_args+=(--no-aur); fi
    if [[ "$UPDATE_UNATTENDED" == true ]]; then continue_args+=(--unattended); fi
    exec "$REPO_ROOT/setup" update "${continue_args[@]}"
  fi
fi

update_heading "2/4  System packages" 2 system
update_system

update_heading "3/4  Packages built from this repository" 3 packages
update_local_packages "$UPDATE_CONTINUE_FROM"

update_heading "4/4  Files" 4 files
if [[ -n "$UPDATE_CONTINUE_FROM" || "$UPDATE_FILES" == true ]]; then
  update_files
else
  printf "Nothing was pulled, so the files on the machine are already these.\n"
fi

update_finish
