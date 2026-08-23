#!/usr/bin/env bash

XDG_CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"
XDG_CACHE_HOME="${XDG_CACHE_HOME:-$HOME/.cache}"
XDG_STATE_HOME="${XDG_STATE_HOME:-$HOME/.local/state}"
CACHE_DIR="$XDG_CACHE_HOME/quickshell"
STATE_DIR="$XDG_STATE_HOME/quickshell"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SHELL_CONFIG_FILE="$XDG_CONFIG_HOME/illogical-impulse/config.json"
MATUGEN_DIR="$XDG_CONFIG_HOME/matugen"
terminalscheme="$SCRIPT_DIR/terminal/scheme-base.json"
SHELL_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# Whose theming to apply. This script runs on its own -- from a keybind, from the
# installer, before the shell is up at all -- so the environment is read from the
# config rather than asked of a running shell. An environment that declares none
# leaves both empty and the defaults below stand, which is what every environment
# did before any of them could declare anything.
family_id=""
family_theming_matugen=""
family_theming_apply=""
family_stamp="$STATE_DIR/user/generated/themed-family.txt"
resolve_family_theming() {
    local family manifest base rel
    family=$(jq -r '.panelFamily // empty' "$SHELL_CONFIG_FILE" 2>/dev/null)
    [[ -n "$family" ]] || return 0
    family_id="$family"
    base="$SHELL_ROOT/environments/$family"
    manifest="$base/manifest.json"
    [[ -f "$manifest" ]] || return 0
    # Read the same way the shell reads `entry`: a path inside the environment's
    # own directory, with no ".." in it.
    rel=$(jq -r '.theming.matugen // empty' "$manifest" 2>/dev/null)
    if [[ -n "$rel" && "$rel" != *..* && -f "$base/$rel" ]]; then
        family_theming_matugen="$base/$rel"
    fi
    rel=$(jq -r '.theming.apply // empty' "$manifest" 2>/dev/null)
    if [[ -n "$rel" && "$rel" != *..* && -f "$base/$rel" ]]; then
        family_theming_apply="$base/$rel"
    fi
    return 0
}

# Whether the world already wears this environment's theming. Asked by the shell
# on every settle, including the first of the session, so that a shell coming up
# on an environment the files were not written for repaints once -- and so that
# holding the cycle key costs one matugen run rather than one per press.
family_theming_is_current() {
    [[ -f "$family_stamp" ]] || return 1
    [[ "$(cat "$family_stamp" 2>/dev/null)" == "$family_id" ]]
}

stamp_family_theming() {
    [[ -n "$family_id" ]] || return 0
    mkdir -p "$(dirname "$family_stamp")"
    printf '%s\n' "$family_id" > "$family_stamp"
}

# matugen wants concrete paths and the shell's own path is not fixed, so the
# environment states its templates relative to itself and the config is rendered
# per run.
render_matugen_config() {
    local source="$1" rendered
    rendered="${XDG_RUNTIME_DIR:-/tmp}/quickshell/matugen.toml"
    mkdir -p "$(dirname "$rendered")"
    sed "s|@THEMING@|$(dirname "$source")|g" "$source" > "$rendered"
    printf '%s' "$rendered"
}

# Which mode the palette already on disk was built for, by the same test the shell
# applies to it: the background's HSL lightness. This is what is actually on screen,
# so it is the honest answer when nothing else has stated a preference. Dark when
# there is no palette to read, which matches the colours the shell ships with.
palette_mode() {
    local colors="$STATE_DIR/user/generated/colors.json"
    [[ -f "$colors" ]] || { echo dark; return; }
    local hex
    hex=$(jq -r '.background // empty' "$colors" 2>/dev/null | tr -d '#')
    [[ ${#hex} -eq 6 ]] || { echo dark; return; }
    local r=$((16#${hex:0:2})) g=$((16#${hex:2:2})) b=$((16#${hex:4:2}))
    local max=$r min=$r
    (( g > max )) && max=$g
    (( b > max )) && max=$b
    (( g < min )) && min=$g
    (( b < min )) && min=$b
    # (max + min) / 2 / 255 < 0.5 without leaving integers.
    if (( max + min < 255 )); then echo dark; else echo light; fi
}

pre_process() {
    local mode_flag="$1"
    # The toolkit theme, the icon set and the Qt style are the environment's to
    # state, so they moved to its own hook and are applied after matugen has
    # written what that hook reads. Only an environment that declares no theming
    # is answered here, and then by what the shell did before environments could
    # declare any.
    if [[ -z "$family_theming_apply" ]]; then
        if [[ "$mode_flag" == "dark" ]]; then
            gsettings set org.gnome.desktop.interface color-scheme 'prefer-dark'
            gsettings set org.gnome.desktop.interface gtk-theme 'adw-gtk3-dark'
            gsettings set org.gnome.desktop.interface icon-theme 'Material-Originals'
        elif [[ "$mode_flag" == "light" ]]; then
            gsettings set org.gnome.desktop.interface color-scheme 'prefer-light'
            gsettings set org.gnome.desktop.interface gtk-theme 'adw-gtk3'
            gsettings set org.gnome.desktop.interface icon-theme 'Material-Originals'
        fi
    fi

    if [ ! -d "$CACHE_DIR"/user/generated ]; then
        mkdir -p "$CACHE_DIR"/user/generated
    fi
}

post_process() {
    local screen_width="$1"
    local screen_height="$2"
    local wallpaper_path="$3"

    "$SCRIPT_DIR/code/material-code-set-color.sh" &
}

check_and_prompt_upscale() {
    local img="$1"

    # notify-send below blocks until the user acts; without this guard every
    # sub-resolution wallpaper switch leaks a stuck prompt process.
    local lock="${XDG_RUNTIME_DIR:-/tmp}/quickshell-upscale-prompt.lock"
    exec {lockfd}>"$lock" 2>/dev/null || return 0
    flock -n "$lockfd" || return 0

    min_width_desired="$(hyprctl monitors -j | jq '([.[].width] | max)' | xargs)" # max monitor width
    min_height_desired="$(hyprctl monitors -j | jq '([.[].height] | max)' | xargs)" # max monitor height

    if command -v identify &>/dev/null && [ -f "$img" ]; then
        local img_width img_height
        if is_video "$img"; then # Not check resolution for videos, just let em pass
            img_width=$min_width_desired
            img_height=$min_height_desired
        else
            img_width=$(identify -format "%w" "$img" 2>/dev/null)
            img_height=$(identify -format "%h" "$img" 2>/dev/null)
        fi
        if [[ "$img_width" -lt "$min_width_desired" || "$img_height" -lt "$min_height_desired" ]]; then
            action=$(timeout 30 notify-send "Upscale?" \
                "Image resolution (${img_width}x${img_height}) is lower than screen resolution (${min_width_desired}x${min_height_desired})" \
                -A "open_upscayl=Open Upscayl"\
                -a "Wallpaper switcher")
            if [[ "$action" == "open_upscayl" ]]; then
                if command -v upscayl &>/dev/null; then
                    nohup upscayl > /dev/null 2>&1 &
                else
                    action2=$(timeout 30 notify-send \
                        -a "Wallpaper switcher" \
                        -c "im.error" \
                        -A "install_upscayl=Install Upscayl (Arch)" \
                        "Install Upscayl?" \
                        "yay -S upscayl-bin")
                    if [[ "$action2" == "install_upscayl" ]]; then
                        kitty -1 yay -S upscayl-bin
                        if command -v upscayl &>/dev/null; then
                            nohup upscayl > /dev/null 2>&1 &
                        fi
                    fi
                fi
            fi
        fi
    fi
}

CUSTOM_DIR="$XDG_CONFIG_HOME/hypr/custom"
RESTORE_SCRIPT_DIR="$CUSTOM_DIR/scripts"
RESTORE_SCRIPT="$RESTORE_SCRIPT_DIR/__restore_video_wallpaper.sh"
THUMBNAIL_DIR="$RESTORE_SCRIPT_DIR/mpvpaper_thumbnails"
VIDEO_OPTS="no-audio loop hwdec=auto scale=bilinear interpolation=no video-sync=display-resample panscan=1.0 video-scale-x=1.0 video-scale-y=1.0 video-align-x=0.5 video-align-y=0.5 load-scripts=no"

is_video() {
    local extension="${1##*.}"
    [[ "$extension" == "mp4" || "$extension" == "webm" || "$extension" == "mkv" || "$extension" == "avi" || "$extension" == "mov" ]] && return 0 || return 1
}

kill_existing_mpvpaper() {
    pkill -f -9 mpvpaper || true
}

create_restore_script() {
    local video_path=$1
    cat > "$RESTORE_SCRIPT.tmp" << EOF
#!/bin/bash
# Generated by switchwall.sh - Don't modify it by yourself.
# Time: $(date)

pkill -f -9 mpvpaper

for monitor in \$(hyprctl monitors -j | jq -r '.[] | .name'); do
    mpvpaper -o "$VIDEO_OPTS" "\$monitor" "$video_path" &
    sleep 0.1
done
EOF
    mv "$RESTORE_SCRIPT.tmp" "$RESTORE_SCRIPT"
    chmod +x "$RESTORE_SCRIPT"
}

remove_restore() {
    cat > "$RESTORE_SCRIPT.tmp" << EOF
#!/bin/bash
# The content of this script will be generated by switchwall.sh - Don't modify it by yourself.
EOF
    mv "$RESTORE_SCRIPT.tmp" "$RESTORE_SCRIPT"
}

set_wallpaper_path() {
    local path="$1"
    if [ -f "$SHELL_CONFIG_FILE" ]; then
        jq --arg path "$path" '.background.wallpaperPath = $path' "$SHELL_CONFIG_FILE" > "$SHELL_CONFIG_FILE.tmp" && mv "$SHELL_CONFIG_FILE.tmp" "$SHELL_CONFIG_FILE"
    fi
}

set_thumbnail_path() {
    local path="$1"
    if [ -f "$SHELL_CONFIG_FILE" ]; then
        jq --arg path "$path" '.background.thumbnailPath = $path' "$SHELL_CONFIG_FILE" > "$SHELL_CONFIG_FILE.tmp" && mv "$SHELL_CONFIG_FILE.tmp" "$SHELL_CONFIG_FILE"
    fi
}

categorize_wallpaper() {
    img_cat=$("$SCRIPT_DIR/../ai/gemini-categorize-wallpaper.sh" "$1")
    # notify-send "Wallpaper category" "$img_cat"
    echo "$img_cat" > "$STATE_DIR/user/generated/wallpaper/category.txt"
}

switch() {
    imgpath="$1"
    mode_flag="$2"
    type_flag="$3"
    color_flag="$4"
    color="$5"

    # Start Gemini auto-categorization if enabled
    aiStylingEnabled=$(jq -r '.background.widgets.clock.cookie.aiStyling' "$SHELL_CONFIG_FILE")
    if [[ "$aiStylingEnabled" == "true" ]]; then
        categorize_wallpaper "$imgpath" &
    fi

    matugen_args=(--source-color-index 0)

    if [[ "$color_flag" == "1" ]]; then
        matugen_args+=(color hex "$color")
        generate_colors_material_args=(--color "$color")
    else
        if [[ -z "$imgpath" ]]; then
            echo 'Aborted'
            exit 0
        fi

        # A mode flip keeps the picture that is already up, and it was measured against
        # the screen when it was set. Asking again costs two more hyprctl calls and can
        # put a prompt on screen for a wallpaper the user did not just choose.
        if [[ -z "$noswitch_flag" ]]; then
            check_and_prompt_upscale "$imgpath" &
        fi
        kill_existing_mpvpaper

        if is_video "$imgpath"; then
            mkdir -p "$THUMBNAIL_DIR"

            missing_deps=()
            if ! command -v mpvpaper &> /dev/null; then
                missing_deps+=("mpvpaper")
            fi
            if ! command -v ffmpeg &> /dev/null; then
                missing_deps+=("ffmpeg")
            fi
            if [ ${#missing_deps[@]} -gt 0 ]; then
                echo "Missing deps: ${missing_deps[*]}"
                echo "Arch: sudo pacman -S ${missing_deps[*]}"
                action=$(notify-send \
                    -a "Wallpaper switcher" \
                    -c "im.error" \
                    -A "install_arch=Install (Arch)" \
                    "Can't switch to video wallpaper" \
                    "Missing dependencies: ${missing_deps[*]}")
                if [[ "$action" == "install_arch" ]]; then
                    kitty -1 sudo pacman -S "${missing_deps[*]}"
                    if command -v mpvpaper &>/dev/null && command -v ffmpeg &>/dev/null; then
                        notify-send 'Wallpaper switcher' 'Alright, try again!' -a "Wallpaper switcher"
                    fi
                fi
                exit 0
            fi

            # Set wallpaper path
            set_wallpaper_path "$imgpath"

            # Set video wallpaper. Route through the downscale cache so mpvpaper never
            # decodes more than the largest panel can show (custom/, survives ii updates).
            local video_path
            video_path="$("$CUSTOM_DIR/scripts/wallpaper-downscale.sh" "$imgpath")"
            [ -n "$video_path" ] || video_path="$imgpath"
            monitors=$(hyprctl monitors -j | jq -r '.[] | .name')
            for monitor in $monitors; do
                mpvpaper -o "$VIDEO_OPTS" "$monitor" "$video_path" &
                sleep 0.1
            done

            # Extract first frame for color generation
            thumbnail="$THUMBNAIL_DIR/$(basename "$imgpath").jpg"
            ffmpeg -y -i "$imgpath" -vframes 1 "$thumbnail" 2>/dev/null

            # Set thumbnail path
            set_thumbnail_path "$thumbnail"

            if [ -f "$thumbnail" ]; then
                matugen_args+=(image "$thumbnail")
                generate_colors_material_args=(--path "$thumbnail")
                create_restore_script "$video_path"
            else
                echo "Cannot create image to colorgen"
                remove_restore
                exit 1
            fi
        else
            matugen_args+=(image "$imgpath")
            generate_colors_material_args=(--path "$imgpath")
            # Update wallpaper path in config
            set_wallpaper_path "$imgpath"
            remove_restore
        fi
    fi

    # Determine mode if not set
    if [[ -z "$mode_flag" ]]; then
        current_mode=$(gsettings get org.gnome.desktop.interface color-scheme 2>/dev/null | tr -d "'")
        if [[ "$current_mode" == "prefer-dark" ]]; then
            mode_flag="dark"
        elif [[ "$current_mode" == "prefer-light" ]]; then
            mode_flag="light"
        else
            # Neither preference is stated -- "default" is what the setting holds until
            # something writes it, and it means the user has not said. Anything that was
            # not exactly prefer-dark used to count as light here, so the first wallpaper
            # change on such a machine quietly turned the desktop light and then wrote
            # that down, which every later run read back as the user's own choice.
            mode_flag="$(palette_mode)"
        fi
    fi

    # enforce dark mode for terminal
    if [[ -n "$mode_flag" ]]; then
        matugen_args+=(--mode "$mode_flag")
        if [[ $(jq -r '.appearance.wallpaperTheming.terminalGenerationProps.forceDarkMode' "$SHELL_CONFIG_FILE") == "true" ]]; then
            generate_colors_material_args+=(--mode "dark")
        else
            generate_colors_material_args+=(--mode "$mode_flag")
        fi
    fi
    [[ -n "$type_flag" ]] && matugen_args+=(--type "$type_flag") && generate_colors_material_args+=(--scheme "$type_flag")
    generate_colors_material_args+=(--termscheme "$terminalscheme" --blend_bg_fg)
    generate_colors_material_args+=(--cache "$STATE_DIR/user/generated/color.txt")

    pre_process "$mode_flag"

    # Check if app and shell theming is enabled in config
    if [ -f "$SHELL_CONFIG_FILE" ]; then
        enable_apps_shell=$(jq -r '.appearance.wallpaperTheming.enableAppsAndShell' "$SHELL_CONFIG_FILE")
        if [ "$enable_apps_shell" == "false" ]; then
            echo "App and shell theming disabled, skipping matugen and color generation"
            return
        fi
    fi

    # Set harmony and related properties
    if [ -f "$SHELL_CONFIG_FILE" ]; then
        harmony=$(jq -r '.appearance.wallpaperTheming.terminalGenerationProps.harmony' "$SHELL_CONFIG_FILE")
        harmonize_threshold=$(jq -r '.appearance.wallpaperTheming.terminalGenerationProps.harmonizeThreshold' "$SHELL_CONFIG_FILE")
        term_fg_boost=$(jq -r '.appearance.wallpaperTheming.terminalGenerationProps.termFgBoost' "$SHELL_CONFIG_FILE")
        [[ "$harmony" != "null" && -n "$harmony" ]] && generate_colors_material_args+=(--harmony "$harmony")
        [[ "$harmonize_threshold" != "null" && -n "$harmonize_threshold" ]] && generate_colors_material_args+=(--harmonize_threshold "$harmonize_threshold")
        [[ "$term_fg_boost" != "null" && -n "$term_fg_boost" ]] && generate_colors_material_args+=(--term_fg_boost "$term_fg_boost")
    fi

    if [[ -n "$family_theming_matugen" ]]; then
        matugen -c "$(render_matugen_config "$family_theming_matugen")" "${matugen_args[@]}"
    else
        matugen "${matugen_args[@]}"
    fi
    if [[ -n "$family_theming_apply" ]]; then
        bash "$family_theming_apply" "$mode_flag"
    fi
    stamp_family_theming
    source "$(eval echo $ILLOGICAL_IMPULSE_VIRTUAL_ENV)/bin/activate"
    python3 "$SCRIPT_DIR/generate_colors_material.py" "${generate_colors_material_args[@]}" \
        > "$STATE_DIR"/user/generated/material_colors.scss
    deactivate
    "$SCRIPT_DIR"/applycolor.sh

    # Pass screen width, height, and wallpaper path to post_process
    max_width_desired="$(hyprctl monitors -j | jq '([.[].width] | min)' | xargs)"
    max_height_desired="$(hyprctl monitors -j | jq '([.[].height] | min)' | xargs)"
    post_process "$max_width_desired" "$max_height_desired" "$imgpath"
}

main() {
    imgpath=""
    mode_flag=""
    type_flag=""
    color_flag=""
    color=""
    noswitch_flag=""
    family_guard_flag=""

    get_type_from_config() {
        jq -r '.appearance.palette.type' "$SHELL_CONFIG_FILE" 2>/dev/null || echo "auto"
    }
    get_accent_color_from_config() {
        jq -r '.appearance.palette.accentColor' "$SHELL_CONFIG_FILE" 2>/dev/null || echo ""
    }
    set_accent_color() {
        local color="$1"
        jq --arg color "$color" '.appearance.palette.accentColor = $color' "$SHELL_CONFIG_FILE" > "$SHELL_CONFIG_FILE.tmp" && mv "$SHELL_CONFIG_FILE.tmp" "$SHELL_CONFIG_FILE"
    }

    detect_scheme_type_from_image() {
        local img="$1"
        source "$(eval echo $ILLOGICAL_IMPULSE_VIRTUAL_ENV)/bin/activate"
        "$SCRIPT_DIR"/scheme_for_image.py "$img" 2>/dev/null | tr -d '\n'
        deactivate
    }

    # Which scheme a picture calls for depends on the picture and nothing else, and
    # working it out costs a Python interpreter and the better part of a second. A
    # light/dark flip does not change the picture, so the answer is kept beside the
    # palette and asked for again only when the file itself changes.
    scheme_type_cache="$STATE_DIR/user/generated/scheme_type.txt"
    scheme_cache_key() {
        printf '%s:%s' "$1" "$(stat -c %Y "$1" 2>/dev/null)"
    }
    cached_scheme_type() {
        [[ -f "$scheme_type_cache" ]] || return 1
        local cached_key cached_type
        { read -r cached_key; read -r cached_type; } < "$scheme_type_cache" || return 1
        [[ "$cached_key" == "$1" ]] || return 1
        printf '%s' "$cached_type"
    }
    store_scheme_type() {
        mkdir -p "$(dirname "$scheme_type_cache")"
        printf '%s\n%s\n' "$1" "$2" > "$scheme_type_cache"
    }

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --mode)
                mode_flag="$2"
                shift 2
                ;;
            --type)
                type_flag="$2"
                shift 2
                ;;
            --color)
                if [[ "$2" =~ ^#?[A-Fa-f0-9]{6}$ ]]; then
                    set_accent_color "$2"
                    shift 2
                elif [[ "$2" == "clear" ]]; then
                    set_accent_color ""
                    shift 2
                else
                    set_accent_color $(hyprpicker --no-fancy)
                    shift
                fi
                ;;
            --image)
                imgpath="$2"
                shift 2
                ;;
            --if-family-changed)
                family_guard_flag="1"
                shift
                ;;
            --noswitch)
                noswitch_flag="1"
                imgpath=$(jq -r '.background.wallpaperPath' "$SHELL_CONFIG_FILE" 2>/dev/null || echo "")
                shift
                ;;
            *)
                if [[ -z "$imgpath" ]]; then
                    imgpath="$1"
                fi
                shift
                ;;
        esac
    done

    resolve_family_theming
    if [[ -n "$family_guard_flag" ]] && family_theming_is_current; then
        exit 0
    fi

    # If accentColor is set in config, use it
    config_color="$(get_accent_color_from_config)"
    if [[ "$config_color" =~ ^#?[A-Fa-f0-9]{6}$ ]]; then
        color_flag="1"
        color="$config_color"
    fi

    # If type_flag is not set, get it from config
    if [[ -z "$type_flag" ]]; then
        type_flag="$(get_type_from_config)"
    fi

    # Validate type_flag (allow 'auto' as well)
    allowed_types=(scheme-content scheme-expressive scheme-fidelity scheme-fruit-salad scheme-monochrome scheme-neutral scheme-rainbow scheme-tonal-spot auto)
    valid_type=0
    for t in "${allowed_types[@]}"; do
        if [[ "$type_flag" == "$t" ]]; then
            valid_type=1
            break
        fi
    done
    if [[ $valid_type -eq 0 ]]; then
        echo "[switchwall.sh] Warning: Invalid type '$type_flag', defaulting to 'auto'" >&2
        type_flag="auto"
    fi

    if [[ -n "$imgpath" && -z "$noswitch_flag" ]]; then
        set_accent_color ""
        color_flag=""
        color=""
    fi

    # If type_flag is 'auto', detect scheme type from image (after imgpath is set)
    if [[ "$type_flag" == "auto" ]]; then
        if [[ -n "$imgpath" && -f "$imgpath" ]]; then
            scheme_key="$(scheme_cache_key "$imgpath")"
            detected_type="$(cached_scheme_type "$scheme_key")"
            detected_was_cached=1
            if [[ -z "$detected_type" ]]; then
                detected_was_cached=0
                detected_type="$(detect_scheme_type_from_image "$imgpath")"
            fi
            # Only use detected_type if it's valid
            valid_detected=0
            for t in "${allowed_types[@]}"; do
                if [[ "$detected_type" == "$t" && "$detected_type" != "auto" ]]; then
                    valid_detected=1
                    break
                fi
            done
            if [[ $valid_detected -eq 1 ]]; then
                type_flag="$detected_type"
                [[ $detected_was_cached -eq 1 ]] || store_scheme_type "$scheme_key" "$detected_type"
            else
                echo "[switchwall] Warning: Could not auto-detect a valid scheme, defaulting to 'scheme-tonal-spot'" >&2
                type_flag="scheme-tonal-spot"
            fi
        else
            echo "[switchwall] Warning: No image to auto-detect scheme from, defaulting to 'scheme-tonal-spot'" >&2
            type_flag="scheme-tonal-spot"
        fi
    fi

    # If mode_flag is dark or light, try to find a variant with that mode suffix
    if [[ "$mode_flag" == "dark" || "$mode_flag" == "light" ]]; then
        # Get directory, filename without extension, and extension
        local imgdir="$(dirname "$imgpath")"
        local imgbase="$(basename "$imgpath")"
        local imgname="${imgbase%.*}"
        local imgext="${imgbase##*.}"

        # Strip existing -dark or -light suffix
        local stripped_name="${imgname%-dark}"
        stripped_name="${stripped_name%-light}"

        # Construct the new path with the requested mode suffix
        local new_imgpath="${imgdir}/${stripped_name}-${mode_flag}.${imgext}"
        local new_stripped_imgpath="${imgdir}/${stripped_name}.${imgext}"

        # If the variant exists, use it
        if [[ -f "$new_imgpath" ]]; then
            imgpath="$new_imgpath"
        elif [[ -f "$new_stripped_imgpath" ]]; then
            imgpath="$new_stripped_imgpath"
        fi
    fi

    switch "$imgpath" "$mode_flag" "$type_flag" "$color_flag" "$color"
}

main "$@"
