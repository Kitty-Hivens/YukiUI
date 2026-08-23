# This script is meant to be sourced.
# It's not for directly running.
printf "${STY_CYAN}[$0]: 3. Copying config files\n${STY_RST}"

# shellcheck shell=bash

function warning_overwrite(){
  printf "${STY_YELLOW}"
  printf "The command below overwrites the destination.\n"
  printf "${STY_RST}"
}
function auto_backup_configs(){
  local backup=false
  # A directory of its own for every run. The copy below merges rather than
  # replaces, so running twice into one place wrote the files just installed over
  # the untouched originals saved the first time -- the only copy worth keeping.
  local run_dir="${BACKUP_DIR}/$(date +%Y-%m-%d_%H-%M-%S)"
  case $ask in
    # There is nobody to ask, so the safe answer is taken. It used to depend on
    # whether a backup directory happened to exist already, which meant every run
    # after the first went without one, and without a word to that effect -- while
    # the step this guards still removed whatever the dotfiles do not carry.
    false)
      local backup=true
      printf "${STY_BLUE}Backing up clashing dirs/files to \"$run_dir\"...${STY_RST}\n"
      ;;
    *)
      printf "${STY_RED}"
      printf "Would you like to backup clashing dirs/files to \"$run_dir\"?\n"
      printf "${STY_RST}"
      while true;do
        echo "  y = Yes, backup"
        echo "  n/s = No, skip to next"
        local p; read -p "====> " p
        case $p in
          [yY]) echo -e "${STY_BLUE}OK, doing backup...${STY_RST}"
            local backup=true;break ;;
          [nNsS]) echo -e "${STY_BLUE}Alright, skipping...${STY_RST}"
            local backup=false;break ;;
          *) echo -e "${STY_RED}Please enter [y/n/s].${STY_RST}";;
        esac
      done
      ;;
  esac
  if $backup;then
    backup_clashing_targets dots/.config "$XDG_CONFIG_HOME" "${run_dir}/.config"
    backup_clashing_targets dots/.local/share "$XDG_DATA_HOME" "${run_dir}/.local/share"
    printf "${STY_BLUE}Backup into \"${run_dir}\" finished.${STY_RST}\n"
  else
    printf "${STY_YELLOW}"
    printf "No backup is being made. Copying config files replaces what is already there,\n"
    printf "and for the directories it keeps in step with the dotfiles it also removes files\n"
    printf "those do not carry.\n"
    printf "${STY_RST}"
  fi
}
function gen_firstrun(){
  x mkdir -p "$(dirname ${FIRSTRUN_FILE})"
  x touch "${FIRSTRUN_FILE}"
  x mkdir -p "$(dirname ${INSTALLED_LISTFILE})"
  realpath -se "${FIRSTRUN_FILE}" >> "${INSTALLED_LISTFILE}"
}
cp_file(){
  # NOTE: This function is only for using in other functions
  x mkdir -p "$(dirname $2)"
  x cp -f "$1" "$2"
  x mkdir -p "$(dirname ${INSTALLED_LISTFILE})"
  realpath -se "$2" >> "${INSTALLED_LISTFILE}"
}
rsync_dir(){
  # NOTE: This function is only for using in other functions
  x mkdir -p "$2"
  local dest="$(realpath -se $2)"
  x mkdir -p "$(dirname ${INSTALLED_LISTFILE})"
  rsync -a --out-format='%i %n' "$1"/ "$2"/ | awk -v d="$dest" '$1 ~ /^>/{ sub(/^[^ ]+ /,""); printf "%s/%s\n", d, $0 }' >> "${INSTALLED_LISTFILE}"
}
rsync_dir__ignore_existing(){
  # NOTE: This function is only for using in other functions
  x mkdir -p "$2"
  local dest="$(realpath -se $2)"
  x mkdir -p "$(dirname ${INSTALLED_LISTFILE})"
  rsync -a --ignore-existing --out-format='%i %n' "$1"/ "$2"/ | awk -v d="$dest" '$1 ~ /^>/{ sub(/^[^ ]+ /,""); printf "%s/%s\n", d, $0 }' >> "${INSTALLED_LISTFILE}"
}
rsync_dir__sync(){
  # NOTE: This function is only for using in other functions
  # `--delete' for rsync to make sure that
  # original dotfiles and new ones in the SAME DIRECTORY
  # (eg. in ~/.config/hypr) won't be mixed together
  x mkdir -p "$2"
  local dest="$(realpath -se $2)"
  x mkdir -p "$(dirname ${INSTALLED_LISTFILE})"
  rsync -a --delete --out-format='%i %n' "$1"/ "$2"/ | awk -v d="$dest" '$1 ~ /^>/{ sub(/^[^ ]+ /,""); printf "%s/%s\n", d, $0 }' >> "${INSTALLED_LISTFILE}"
}
rsync_dir__sync_exclude(){
  # NOTE: This function is only for using in other functions
  # Same as rsync_dir__sync but with exclude patterns support
  # Usage: rsync_dir__sync_exclude <src> <dest> <exclude_pattern1> [<exclude_pattern2> ...]
  local src="$1"
  local dest_dir="$2"
  shift 2
  local excludes=()
  for pattern in "$@"; do
    excludes+=(--exclude "$pattern")
  done
  x mkdir -p "$dest_dir"
  local dest="$(realpath -se $dest_dir)"
  x mkdir -p "$(dirname ${INSTALLED_LISTFILE})"
  rsync -a --delete "${excludes[@]}" --out-format='%i %n' "$src"/ "$dest_dir"/ | awk -v d="$dest" '$1 ~ /^>/{ sub(/^[^ ]+ /,""); printf "%s/%s\n", d, $0 }' >> "${INSTALLED_LISTFILE}"
}
function install_file(){
  # NOTE: Do not add prefix `v` or `x` when using this function
  local s=$1
  local t=$2
  if [ -f $t ];then
    warning_overwrite
  fi
  v cp_file $s $t
}
function install_file__auto_backup(){
  # NOTE: Do not add prefix `v` or `x` when using this function
  local s=$1
  local t=$2
  if [ -f $t ];then
    echo -e "${STY_YELLOW}[$0]: \"$t\" already exists.${STY_RST}"
    if ${INSTALL_FIRSTRUN};then
      echo -e "${STY_BLUE}[$0]: It seems to be the firstrun.${STY_RST}"
      v mv $t $t.old
      v cp_file $s $t
    else
      echo -e "${STY_BLUE}[$0]: It seems not a firstrun.${STY_RST}"
      v cp_file $s $t.new
    fi
  else
    echo -e "${STY_GREEN}[$0]: \"$t\" does not exist yet.${STY_RST}"
    v cp_file $s $t
  fi
}
function install_dir(){
  # NOTE: Do not add prefix `v` or `x` when using this function
  local s=$1
  local t=$2
  if [ -d $t ];then
    warning_overwrite
  fi
  v rsync_dir $s $t
}
function install_dir__sync(){
  # NOTE: Do not add prefix `v` or `x` when using this function
  local s=$1
  local t=$2
  if [ -d $t ];then
    warning_overwrite
  fi
  v rsync_dir__sync $s $t
}
function install_dir__skip_ifexist(){
  # NOTE: Do not add prefix `v` or `x` when using this function
  local s=$1
  local t=$2
  if [ -d $t ];then
    echo -e "${STY_BLUE}[$0]: \"$t\" already exists, will not do anything.${STY_RST}"
  else
    echo -e "${STY_YELLOW}[$0]: \"$t\" does not exist yet.${STY_RST}"
    v rsync_dir $s $t
  fi
}
function install_dir__ignore_existing(){
  # NOTE: Do not add prefix `v` or `x` when using this function
  local s=$1
  local t=$2
  if [ -d $t ];then
    echo -e "${STY_BLUE}[$0]: \"$t\" already exists, will not do anything.${STY_RST}"
  else
    echo -e "${STY_YELLOW}[$0]: \"$t\" does not exist yet.${STY_RST}"
    v rsync_dir__ignore_existing $s $t
  fi
}
function install_dir__sync_exclude(){
  # NOTE: Do not add prefix `v` or `x` when using this function
  # Sync directory with exclude patterns
  # Usage: install_dir__sync_exclude <src> <dest> <exclude_pattern1> [<exclude_pattern2> ...]
  local s=$1
  local t=$2
  shift 2
  if [ -d $t ];then
    warning_overwrite
  fi
  v rsync_dir__sync_exclude $s $t "$@"
}
function install_wallpaper_portal_service(){
  # D-Bus activation of the wallpaper portal backend. Written rather than copied
  # because Exec takes an absolute path and expands nothing.
  local target="${XDG_DATA_HOME}/dbus-1/services/org.freedesktop.impl.portal.desktop.yuki.service"
  local exec_path="${XDG_CONFIG_HOME}/quickshell/yuki/scripts/portal/wallpaper-portal.py"
  x mkdir -p "$(dirname "$target")"
  sed "s|@EXEC@|${exec_path}|" sdata/files/org.freedesktop.impl.portal.desktop.yuki.service.in > "$target"
  x mkdir -p "$(dirname ${INSTALLED_LISTFILE})"
  realpath -se "$target" >> "${INSTALLED_LISTFILE}"
}
function install_session_entry(){
  # The Wayland session YukiUI is entered through. Written rather than copied for
  # the same reason as the service above: Exec takes an absolute path and expands
  # nothing, and the launcher it points at lives under the user's config.
  #
  # That launcher is the whole point of shipping a session of our own. Hyprland's
  # own entry runs start-hyprland bare, and start-hyprland answers a crash by
  # restarting the compositor in safe mode, which comes up on a generated stock
  # config with none of the session's autostart. Naming the launcher with --path
  # puts that decision where every login screen and every login shell reads it,
  # instead of in one shell profile.
  #
  # A pair, the way Hyprland ships one: the plain entry is what uwsm is pointed
  # at, the uwsm one is what a login screen has to offer, because a session
  # started outside uwsm comes up without the units the shell is launched into.
  local exec_path="${XDG_CONFIG_HOME}/hypr/hyprland/scripts/launch_compositor.sh"
  local target_dir="${XDG_DATA_HOME}/wayland-sessions"
  x mkdir -p "$target_dir"
  sed "s|@EXEC@|${exec_path}|" sdata/files/yuki.desktop.in > "${target_dir}/yuki.desktop"
  x cp -f sdata/files/yuki-uwsm.desktop "${target_dir}/yuki-uwsm.desktop"
  x mkdir -p "$(dirname ${INSTALLED_LISTFILE})"
  realpath -se "${target_dir}/yuki.desktop" >> "${INSTALLED_LISTFILE}"
  realpath -se "${target_dir}/yuki-uwsm.desktop" >> "${INSTALLED_LISTFILE}"
}
function install_shell_cli(){
  # A command on PATH for managing the shell's environments and plugins.
  # Linked rather than copied: the script reads the config name off its own
  # location, so a copy elsewhere would have to be told that name a second time
  # and would then be free to disagree with it.
  local source="${XDG_CONFIG_HOME}/quickshell/yuki/scripts/yukictl"
  local target="${HOME}/.local/bin/yukictl"
  if [ ! -e "$source" ]; then return 0; fi
  x mkdir -p "$(dirname "$target")"
  x ln -sf "$source" "$target"
  x mkdir -p "$(dirname ${INSTALLED_LISTFILE})"
  realpath -se "$target" >> "${INSTALLED_LISTFILE}"
}
function install_shell_completions(){
  # Completions for the command above, one file per shell. Linked for the same
  # reason it is: they ask `yukictl` for the names rather than reading the
  # directories themselves, so they answer for whichever config is installed.
  #
  # After the copying step rather than before it, because that step keeps
  # ~/.config/fish in step with the dotfiles and takes with it whatever they do
  # not carry -- a link written there first would not survive it.
  local source_dir="${XDG_CONFIG_HOME}/quickshell/yuki/scripts/completions"
  if [ ! -d "$source_dir" ]; then return 0; fi
  x mkdir -p "$(dirname ${INSTALLED_LISTFILE})"
  local pair source target
  for pair in \
    "yukictl.fish:${XDG_CONFIG_HOME}/fish/completions/yukictl.fish" \
    "yukictl.bash:${XDG_DATA_HOME}/bash-completion/completions/yukictl" \
    "_yukictl:${XDG_DATA_HOME}/zsh/site-functions/_yukictl"; do
    source="${source_dir}/${pair%%:*}"
    target="${pair#*:}"
    if [ ! -e "$source" ]; then continue; fi
    x mkdir -p "$(dirname "$target")"
    x ln -sf "$source" "$target"
    realpath -se "$target" >> "${INSTALLED_LISTFILE}"
  done
  # bash and fish read the directories above on their own; zsh reads a list it
  # is given, and this is not on it, so the file sits there unreachable until
  # someone says the word.
  if command -v zsh > /dev/null 2>&1; then
    printf "${STY_BLUE}[$0]: For completion in zsh, add this line to your .zshrc:${STY_RST}\n"
    printf "${STY_BLUE}  fpath=(${XDG_DATA_HOME}/zsh/site-functions \$fpath)${STY_RST}\n"
  fi
}
function install_google_sans_flex(){
  local font_name="Google Sans Flex"
  local src_name="google-sans-flex"
  local src_url="https://github.com/end-4/google-sans-flex"
  local src_dir="$REPO_ROOT/cache/$src_name"
  local target_dir="${XDG_DATA_HOME}/fonts/illogical-impulse-$src_name"
  if fc-list | grep -qi "$font_name"; then return; fi
  x mkdir -p $src_dir
  x cd $src_dir
  try git init -b main
  try git remote add origin $src_url
  x git pull origin main 
  x git submodule update --init --recursive
  warning_overwrite
  rsync_dir "$src_dir" "$target_dir"
  # The whole upstream repo is pulled, so its .git rides along -- useless in a fonts dir and fontconfig walks it every scan.
  x rm -rf "$target_dir/.git"
  x fc-cache -fv
  x cd $REPO_ROOT
  x mkdir -p "$(dirname ${INSTALLED_LISTFILE})"
  realpath -se "$target_dir" >> "${INSTALLED_LISTFILE}"
}

#####################################################################################
# In case some dirs does not exists
for i in "$XDG_BIN_HOME" "$XDG_CACHE_HOME" "$XDG_CONFIG_HOME" "$XDG_DATA_HOME"; do
  if ! test -e "$i"; then
    v mkdir -p "$i"
  fi
done
case "${INSTALL_FIRSTRUN}" in
  # When specify --firstrun
  true) sleep 0 ;;
  # When not specify --firstrun
  *)
    if test -f "${FIRSTRUN_FILE}"; then
      INSTALL_FIRSTRUN=false
    else
      INSTALL_FIRSTRUN=true
    fi
    ;;
esac


showfun auto_update_git_submodule
v auto_update_git_submodule

# Backup
if [[ ! "${SKIP_BACKUP}" == true ]]; then auto_backup_configs; fi

case "${EXPERIMENTAL_FILES_SCRIPT}" in
  true)source sdata/subcmd-install/3.files-exp.sh;;
  *)source sdata/subcmd-install/3.files-legacy.sh;;
esac

showfun install_wallpaper_portal_service
v install_wallpaper_portal_service

showfun install_session_entry
v install_session_entry

showfun install_shell_cli
v install_shell_cli

showfun install_shell_completions
v install_shell_completions

if [[ ! "$OS_GROUP_ID" == "fedora" ]]; then
  showfun install_google_sans_flex
  v install_google_sans_flex
fi

#####################################################################################

v gen_firstrun
v dedup_and_sort_listfile "${INSTALLED_LISTFILE}" "${INSTALLED_LISTFILE}"

# Prevent hyprland from not fully loaded
sleep 1
try hyprctl reload

#####################################################################################
printf "\n"
printf "\n"
printf "\n"
printf "${STY_CYAN}[$0]: Finished${STY_RST}\n"
printf "\n"
printf "${STY_CYAN}When starting from your display manager (login screen) ${STY_RED} SELECT \"YukiUI (uwsm-managed)\" ${STY_RST}\n"
printf "${STY_CYAN}The shell is started as a uwsm unit, so a plain session leaves you without it. The YukiUI${STY_RST}\n"
printf "${STY_CYAN}sessions also carry the launcher that keeps a crash restart on your own config.${STY_RST}\n"
printf "\n"
printf "${STY_CYAN}If you are already running Hyprland,${STY_RST}\n"
printf "${STY_CYAN}Press ${STY_INVERT} Ctrl+Super+T ${STY_RST}${STY_CYAN} to select a wallpaper${STY_RST}\n"
printf "${STY_CYAN}Press ${STY_INVERT} Super+/ ${STY_RST}${STY_CYAN} for a list of keybinds${STY_RST}\n"
printf "\n"
printf "${STY_CYAN}For suggestions/hints after installation:${STY_RST}\n"
printf "${STY_CYAN}${STY_UNDERLINE} https://github.com/Kitty-Hivens/YukiUI#configuration ${STY_RST}\n"
printf "\n"

if [[ -z "${ILLOGICAL_IMPULSE_VIRTUAL_ENV}" ]]; then
  printf "\n${STY_RED}[$0]: \!! Important \!! : Please ensure environment variable ${STY_RST} \$ILLOGICAL_IMPULSE_VIRTUAL_ENV ${STY_RED} is set to proper value (by default \"~/.local/state/quickshell/.venv\"), or Quickshell config will not work. We have already provided this configuration in ~/.config/hypr/hyprland/env.conf, but you need to ensure it is included in hyprland.conf, and also a restart is needed for applying it.${STY_RST}\n"
fi
