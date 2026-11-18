# This is NOT a script for execution, but for loading functions, so NOT need execution permission or shebang.
# shellcheck shell=bash

# Which of the shell's desktops (environments) are installed.
#
# A desktop is a directory under environments/ that holds a manifest. Files of
# its own that sit elsewhere in the shell's tree, a settings window in the root
# say, are listed in that manifest under "files", so leaving a desktop out
# leaves out all of it. Everything else in the tree is shared and always goes.
#
# Blueberry alone is installed unless others are asked for. An install that
# already holds some keeps the ones it holds, so running the installer again to
# update does not take away a desktop somebody chose earlier.
#
# Every function here returns 0 unless it means to fail: the installer runs
# under `set -e`, and a test that merely came out false would end it.

FAMILIES_SOURCE_ROOT="dots/.config/quickshell/yuki"
FAMILIES_DEFAULT="blueberry"

# Filled by families_select.
FAMILIES_SELECTED=()
# How the selection was arrived at: "asked", "kept" or "default".
FAMILIES_SELECTED_HOW=""

function families_target_root(){
  printf '%s\n' "${XDG_CONFIG_HOME}/quickshell/yuki"
}

# The desktops this repository carries, one id per line, by name.
function families_available(){
  local dir
  for dir in "${REPO_ROOT}/${FAMILIES_SOURCE_ROOT}"/environments/*/; do
    if [[ -f "${dir}manifest.json" ]]; then basename "$dir"; fi
  done
  return 0
}

# The desktops already installed, among the ones this repository carries.
function families_installed(){
  local root id
  root="$(families_target_root)"
  while IFS= read -r id; do
    if [[ -f "${root}/environments/${id}/manifest.json" ]]; then printf '%s\n' "$id"; fi
  done < <(families_available)
  return 0
}

function families_is_available(){
  local id
  while IFS= read -r id; do
    if [[ "$id" == "$1" ]]; then return 0; fi
  done < <(families_available)
  return 1
}

function families_name_of(){
  case "$1" in
    ii) printf 'Illogical Impulse\n' ;;
    waffle) printf 'Waffle\n' ;;
    blueberry) printf 'Blueberry\n' ;;
    *) printf '%s\n' "$1" ;;
  esac
}

# Sets FAMILIES_SELECTED from what --families said, or from the machine when it
# said nothing. Takes the option's value and whether the option was given at
# all, since an empty value is a mistake rather than a request for the default.
function families_select(){
  local spec="$1" given="${2:-false}" id
  local -a wanted=()
  FAMILIES_SELECTED=()
  if [[ "$given" != true ]]; then
    readarray -t wanted < <(families_installed)
    if (( ${#wanted[@]} > 0 )); then
      FAMILIES_SELECTED=("${wanted[@]}")
      FAMILIES_SELECTED_HOW="kept"
    else
      FAMILIES_SELECTED=("$FAMILIES_DEFAULT")
      FAMILIES_SELECTED_HOW="default"
    fi
    return 0
  fi
  if [[ "$spec" == "all" ]]; then
    readarray -t FAMILIES_SELECTED < <(families_available)
    FAMILIES_SELECTED_HOW="asked"
    return 0
  fi
  local -a parts=()
  IFS=',' read -r -a parts <<< "$spec"
  for id in "${parts[@]}"; do
    id="${id//[[:space:]]/}"
    if [[ -z "$id" ]]; then continue; fi
    if ! families_is_available "$id"; then
      printf "${STY_RED}There is no desktop called \"%s\". These can be installed: %s, or \"all\".${STY_RST}\n" \
        "$id" "$(families_available | paste -sd ' ')" >&2
      return 1
    fi
    if [[ " ${FAMILIES_SELECTED[*]} " != *" ${id} "* ]]; then FAMILIES_SELECTED+=("$id"); fi
  done
  if (( ${#FAMILIES_SELECTED[@]} == 0 )); then
    printf "${STY_RED}--families names no desktop. These can be installed: %s, or \"all\".${STY_RST}\n" \
      "$(families_available | paste -sd ' ')" >&2
    return 1
  fi
  FAMILIES_SELECTED_HOW="asked"
  return 0
}

function families_is_selected(){
  [[ " ${FAMILIES_SELECTED[*]} " == *" $1 "* ]]
}

# What belongs to one desktop, as paths inside the shell's tree: its directory
# under environments/, and the files its manifest lists. Fails on a manifest
# that names something outside the tree, or anything a pattern could widen.
function families_owned(){
  local id="$1"
  local manifest="${REPO_ROOT}/${FAMILIES_SOURCE_ROOT}/environments/${id}/manifest.json"
  if ! command -v python3 > /dev/null 2>&1; then
    printf "${STY_RED}python3 is needed to read %s.${STY_RST}\n" "$manifest" >&2
    return 1
  fi
  python3 - "$manifest" "$id" <<'EOF'
import json
import re
import sys

path, ident = sys.argv[1], sys.argv[2]
with open(path) as f:
    manifest = json.load(f)
files = manifest.get("files", [])
if not isinstance(files, list):
    sys.exit(f'{path}: "files" is not a list')
print(f"environments/{ident}")
# Plain names only: each one becomes an rsync pattern, and a star or a bracket
# would reach files that are not the desktop's.
plain = re.compile(r"[A-Za-z0-9_.-]+(/[A-Za-z0-9_.-]+)*")
for entry in files:
    if not isinstance(entry, str) or not plain.fullmatch(entry.rstrip("/")) or ".." in entry.split("/"):
        sys.exit(f"{path}: {entry!r} cannot be one of its files: a path inside the shell's tree, letters, digits, dots, dashes and underscores, with no '..'")
    print(entry.rstrip("/"))
EOF
}

# What the copy leaves out and takes off the machine: everything that belongs
# to a desktop not selected. Refuses when a path is claimed both by a desktop
# that goes and by one that stays, since leaving it out would break the one
# that stays.
function families_excluded_paths(){
  local id path owned
  local -a kept=() dropped=()
  while IFS= read -r id; do
    owned="$(families_owned "$id")" || return 1
    while IFS= read -r path; do
      if families_is_selected "$id"; then kept+=("$path"); else dropped+=("$path"); fi
    done <<< "$owned"
  done < <(families_available)
  for path in "${dropped[@]}"; do
    if [[ " ${kept[*]} " == *" ${path} "* ]]; then
      printf "${STY_RED}\"%s\" is listed by more than one desktop, so it cannot be left out with one of them.${STY_RST}\n" "$path" >&2
      return 1
    fi
  done
  if (( ${#dropped[@]} > 0 )); then printf '%s\n' "${dropped[@]}"; fi
  return 0
}

# What the copy of the shell's tree leaves out, as rsync patterns rooted at the
# directory copied, whose place above the shell's own is passed in: the legacy
# copy takes the whole of ~/.config/quickshell ("/yuki"), the yaml one the
# shell's own directory (""). What tests/ writes into the tree for a run,
# should a run end without taking it away again, and every desktop not
# selected. Meant for --delete-excluded, which takes them off the destination.
function families_rsync_excludes(){
  local prefix="$1" path excluded
  excluded="$(families_excluded_paths)" || return 1
  printf '%s\n' "${prefix}/bench*Probe.qml"
  while IFS= read -r path; do
    if [[ -n "$path" ]]; then printf '%s\n' "${prefix}/${path}"; fi
  done <<< "$excluded"
  return 0
}

# The selection in words, for messages.
function families_describe(){
  local id out=""
  for id in "${FAMILIES_SELECTED[@]}"; do out+="${out:+, }$(families_name_of "$id")"; done
  printf '%s\n' "$out"
}
