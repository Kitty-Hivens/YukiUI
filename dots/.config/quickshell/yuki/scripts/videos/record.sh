#!/usr/bin/env bash

CONFIG_FILE="${XDG_CONFIG_HOME:-$HOME/.config}/illogical-impulse/config.json"
JSON_PATH=".screenRecord.savePath"

# jq prints the string "null" for a key that is not there, and that is not an
# empty answer, so the fallback below was unreachable and recordings landed in a
# directory called "null" next to wherever the shell happened to be.
CUSTOM_PATH=$(jq -r "$JSON_PATH" "$CONFIG_FILE" 2>/dev/null)

RECORDING_DIR=""

if [[ -n "$CUSTOM_PATH" && "$CUSTOM_PATH" != "null" ]]; then
    RECORDING_DIR="$CUSTOM_PATH"
else
    RECORDING_DIR="$HOME/Videos" # Use default path
fi

# Which recording this script started, so stopping one never reaches a
# wf-recorder somebody else is running.
PIDFILE="${XDG_RUNTIME_DIR:-/tmp}/yuki-recorder.pid"

getdate() {
    date '+%Y-%m-%d_%H.%M.%S'
}
# The monitor of the sink sound is going to. Listing every source and grepping
# for "monitor" returns one line per sink, and with a headset and built in
# speakers both present the lines were pasted into a single --audio= that names
# no device that exists.
getaudiooutput() {
    local sink
    sink="$(pactl get-default-sink 2>/dev/null)"
    [[ -n "$sink" ]] && printf '%s.monitor' "$sink"
}
getactivemonitor() {
    hyprctl monitors -j | jq -r '.[] | select(.focused == true) | .name'
}

mkdir -p "$RECORDING_DIR"
cd "$RECORDING_DIR" || exit

# parse --region <value> without modifying $@ so other flags like --fullscreen still work
ARGS=("$@")
MANUAL_REGION=""
SOUND_FLAG=0
FULLSCREEN_FLAG=0
for ((i=0;i<${#ARGS[@]};i++)); do
    if [[ "${ARGS[i]}" == "--region" ]]; then
        if (( i+1 < ${#ARGS[@]} )); then
            MANUAL_REGION="${ARGS[i+1]}"
        else
            notify-send "Recording cancelled" "No region specified for --region" -a 'Recorder' & disown
            exit 1
        fi
    elif [[ "${ARGS[i]}" == "--sound" ]]; then
        SOUND_FLAG=1
    elif [[ "${ARGS[i]}" == "--fullscreen" ]]; then
        FULLSCREEN_FLAG=1
    fi
done

# One timestamp for the name and the notification alike. Asking twice put a
# different second in each of them whenever the call straddled one.
record() {
    local file="./recording_$(getdate).mp4"
    local args=("$@" --pixel-format yuv420p -f "$file" -t)
    if [[ $SOUND_FLAG -eq 1 ]]; then
        local monitor
        monitor="$(getaudiooutput)"
        if [[ -n "$monitor" ]]; then
            args+=(--audio="$monitor")
        else
            notify-send "Recording without sound" "No default sink to record from" -a 'Recorder' & disown
        fi
    fi

    notify-send "Starting recording" "${file#./}" -a 'Recorder' & disown
    wf-recorder "${args[@]}" &
    local pid=$!
    printf '%s\n' "$pid" > "$PIDFILE"
    wait "$pid"
    local status=$?
    rm -f "$PIDFILE"
    # 130 is the interrupt the stop path sends, which is how a recording ends.
    if (( status != 0 && status != 130 )); then
        notify-send "Recording failed" "wf-recorder gave up with status $status" -a 'Recorder' & disown
    fi
}

if [[ -s "$PIDFILE" ]] && kill -0 "$(<"$PIDFILE")" 2>/dev/null; then
    notify-send "Recording Stopped" "Stopped" -a 'Recorder' & disown
    # Interrupt rather than terminate: wf-recorder finishes writing the file it
    # has open when it is interrupted.
    kill -INT "$(<"$PIDFILE")"
    exit 0
fi

if [[ $FULLSCREEN_FLAG -eq 1 ]]; then
    record -o "$(getactivemonitor)"
else
    # If a manual region was provided via --region, use it; otherwise run slurp as before.
    if [[ -n "$MANUAL_REGION" ]]; then
        region="$MANUAL_REGION"
    else
        if ! region="$(slurp 2>&1)"; then
            notify-send "Recording cancelled" "Selection was cancelled" -a 'Recorder' & disown
            exit 1
        fi
    fi

    record --geometry "$region"
fi
