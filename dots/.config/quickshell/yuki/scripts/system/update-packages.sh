#!/usr/bin/env bash
# Upgrades the system's packages, the AUR's among them.
#
#   update-packages.sh [--unattended] [--no-aur] [--service]
#
# --unattended  asks nothing. A conflict is answered with no, which stops the
#               run with both packages as they were, and what is built is built
#               without its scripts being shown. Root is gained by sudo where
#               that needs no password, and by polkit's prompt otherwise.
# --no-aur      the repositories' packages alone.
# --service     run by the shell as the whole of an update, not as a step of
#               `setup update`: says so in the lines the shell reads,
#               "@yuki step <number> <of> <key>" and how it ended.

unattended=false
aur=true
service=false
for arg in "$@"; do
  case "$arg" in
    --unattended) unattended=true ;;
    --no-aur) aur=false ;;
    --service) service=true ;;
    *) echo "update-packages.sh: unknown option $arg" >&2; exit 2 ;;
  esac
done

if [[ "$service" == true ]]; then
  trap 's=$?; if (( s == 0 )); then echo "@yuki done"; else echo "@yuki failed system"; fi' EXIT
  echo "@yuki step 1 1 system"
fi

if ! command -v pacman > /dev/null 2>&1; then
  echo "This is not an Arch system. Update its packages the way your distribution does."
  exit 0
fi

# What gains root, to nobody to type a password at a terminal here: sudo where
# it asks for none, and polkit otherwise.
root=sudo
if [[ "$unattended" == true ]] && ! { command -v sudo > /dev/null 2>&1 && sudo -n true > /dev/null 2>&1; }; then
  root=pkexec
fi

quiet=()
if command -v yay > /dev/null 2>&1; then
  if [[ "$unattended" == true ]]; then
    quiet=(--noconfirm --answerclean None --answerdiff None --answeredit None --answerupgrade None --sudo "$root")
  fi
  if [[ "$unattended" == true ]]; then
    # The repositories first, and what the AUR cannot build after them: one
    # package that does not build is no reason to leave the rest as it was, or
    # to stop what the update does next. yay names those it could not build.
    yay -Syu --repo "${quiet[@]}" || exit
    if [[ "$aur" == true ]] && ! yay -Sua "${quiet[@]}"; then echo "@yuki aur-failed"; fi
  else
    if [[ "$aur" != true ]]; then quiet+=(--repo); fi
    yay -Syu "${quiet[@]}"
  fi
elif command -v paru > /dev/null 2>&1; then
  if [[ "$unattended" == true ]]; then
    quiet=(--noconfirm --skipreview --sudo "$root")
    paru -Syu --repo "${quiet[@]}" || exit
    if [[ "$aur" == true ]] && ! paru -Sua "${quiet[@]}"; then echo "@yuki aur-failed"; fi
  else
    if [[ "$aur" != true ]]; then quiet+=(--repo); fi
    paru -Syu "${quiet[@]}"
  fi
elif [[ "$unattended" == true ]]; then
  "$root" pacman -Syu --noconfirm
else
  sudo pacman -Syu
fi
