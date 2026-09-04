#!/usr/bin/env bash
#
  # ========================================================
  #   CONFIGURACIÓN DE WAYBAR
  #   Hecho por: Morta
  # ========================================================

set -uo pipefail

FG_RED="\e[31m"
FG_GREEN="\e[32m"
FG_RESET="\e[39m"

TIMEOUT=10

printf() {
    command printf "$@" >&2
}

restore_cursor() {
    printf "\e[?25h"
}

check_deps() {
    local dep missing=()
    for dep in bluetoothctl fzf notify-send rfkill awk; do
        command -v "$dep" &> /dev/null || missing+=("$dep")
    done

    if ((${#missing[@]} > 0)); then
        notify-send "Bluetooth" "Missing dependencies: ${missing[*]}" -i "package-broken"
        exit 1
    fi
}

power_on() {
    local state
    state=$(bluetoothctl show | awk '/PowerState/ {print $2}')

    case $state in
        off)
            bluetoothctl power on > /dev/null
            ;;
        off-blocked)
            rfkill unblock bluetooth

            local new_state i
            for ((i = 1; i <= TIMEOUT; i++)); do
                printf "\rUnblocking Bluetooth... (%d/%d)" "$i" "$TIMEOUT"

                new_state=$(bluetoothctl show | awk '/PowerState/ {print $2}')
                [[ $new_state == on ]] && break

                sleep 1
            done

            if [[ $new_state != on ]]; then
                notify-send "Bluetooth" "Failed to unblock" -i "package-purge"
                exit 1
            fi
            ;;
        *)
            return 0
            ;;
    esac

    notify-send "Bluetooth On" -i "network-bluetooth-activated" \
        -h string:x-canonical-private-synchronous:bluetooth
}

get_devices() {
    bluetoothctl -t "$TIMEOUT" scan on > /dev/null &
    local scan_pid=$!

    local num i
    for ((i = 1; i <= TIMEOUT; i++)); do
        printf "\rScanning for devices... (%d/%d)" "$i" "$TIMEOUT"
        printf "\n%bPress [q] to stop%b\n" "$FG_RED" "$FG_RESET"

        num=$(bluetoothctl devices | grep -c "^Device")
        printf "\nDevices: %d" "$num"

        # move cursor 3 lines up
        printf "\e[3F"

        read -rsn 1 -t 1
        if [[ $REPLY == [Qq] ]]; then
            break
        fi
    done

    # make sure the scan actually stops, even if it hasn't timed out yet
    bluetoothctl scan off > /dev/null 2>&1
    kill "$scan_pid" 2> /dev/null

    printf "\n%bScanning stopped.%b\n\n" "$FG_RED" "$FG_RESET"

    LIST=$(bluetoothctl devices | sed "s/^Device //")
    if [[ -z $LIST ]]; then
        notify-send "Bluetooth" "No devices found" -i "package-broken"
        exit 1
    fi
}

# Builds a display-only copy of $LIST with a marker on connected devices.
# The marker is appended at the end of the line so `awk '{print $1}'`
# still extracts a clean MAC address later on.
annotate_connected() {
    local connected
    connected=$(bluetoothctl devices Connected | sed "s/^Device //" | awk '{print $1}')

    local line address display=""
    while IFS= read -r line; do
        address=${line%% *}
        if grep -qx "$address" <<< "$connected"; then
            display+="${line} [connected]"$'\n'
        else
            display+="${line}"$'\n'
        fi
    done <<< "$LIST"

    printf -v DISPLAY_LIST '%s' "$display"
}

select_device() {
    annotate_connected

    local header
    printf -v header "%-17s %s" "Address" "Name"

    local options=(
        "--border=sharp"
        "--border-label= Bluetooth Devices "
        "--cycle"
        "--ghost=Search"
        "--header=$header"
        "--height=~100%"
        "--highlight-line"
        "--info=inline-right"
        "--pointer="
        "--reverse"
    )

    ADDRESS=$(fzf "${options[@]}" <<< "$DISPLAY_LIST" | awk '{print $1}')
    if [[ -z $ADDRESS ]]; then
        exit 1
    fi
}

pair_and_connect() {
    local paired
    paired=$(bluetoothctl info "$ADDRESS" | awk '/Paired/ {print $2}')

    if [[ $paired == no ]]; then
        printf "Pairing..."

        if ! timeout "$TIMEOUT" bluetoothctl pair "$ADDRESS" > /dev/null; then
            notify-send "Bluetooth" "Failed to pair" -i "package-purge"
            exit 1
        fi
    fi

    printf "\nConnecting..."

    if ! timeout "$TIMEOUT" bluetoothctl connect "$ADDRESS" > /dev/null; then
        notify-send "Bluetooth" "Failed to connect" -i "package-purge"
        exit 1
    fi

    notify-send "Bluetooth" "Successfully connected" -i "package-install"
}

disconnect_device() {
    local name
    name=$(bluetoothctl info "$ADDRESS" | awk -F ': ' '/Name/ {print $2}')

    printf "Disconnecting..."

    if ! timeout "$TIMEOUT" bluetoothctl disconnect "$ADDRESS" > /dev/null; then
        notify-send "Bluetooth" "Failed to disconnect" -i "package-purge"
        exit 1
    fi

    notify-send "Bluetooth" "Disconnected from ${name:-device}" -i "network-bluetooth-disconnected"
}

main() {
    trap 'restore_cursor; kill -9 $PPID 2>/dev/null' EXIT

    check_deps

    if [[ ${1-} == off ]]; then
        bluetoothctl power off
        notify-send 'Bluetooth Off' -i 'network-bluetooth-inactive' \
            -h string:x-canonical-private-synchronous:bluetooth
        exit 0
    fi

    printf "\e[?25l" # make cursor invisible
    power_on
    get_devices

    printf "\e[?25h" # make cursor visible
    select_device

    local connected
    connected=$(bluetoothctl info "$ADDRESS" | awk '/Connected/ {print $2}')

    if [[ $connected == yes ]]; then
        disconnect_device
    else
        pair_and_connect
    fi
}

main "$@"