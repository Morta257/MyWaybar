#!/usr/bin/env bash

# ========================================================
#   CONFIGURACIÓN DE WAYBAR
#   Hecho por: Morta
# ========================================================

# -- Configuración Inicial --
set -uo pipefail

FG_RED="\e[31m"
FG_GREEN="\e[32m"
FG_RESET="\e[39m"

TIMEOUT=10

STATE_FILE="${XDG_CACHE_HOME:-$HOME/.cache}/waybar-bluetooth-prev-sink"

# -- Funciones Auxiliares --
printf() {
    command printf "$@" >&2
}

restore_cursor() {
    printf "\e[?25h"
}

check_deps() {
    local dep missing=()
    for dep in bluetoothctl fzf notify-send rfkill awk pactl pw-cli; do
        command -v "$dep" &> /dev/null || missing+=("$dep")
    done

    if ((${#missing[@]} > 0)); then
        notify-send "Bluetooth" "Faltan dependencias: ${missing[*]}" -i "package-broken"
        exit 1
    fi
}

# -- Gestión de Energía y Escaneo --
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
                printf "\rDesbloqueando Bluetooth... (%d/%d)" "$i" "$TIMEOUT"

                new_state=$(bluetoothctl show | awk '/PowerState/ {print $2}')
                [[ $new_state == on ]] && break

                sleep 1
            done

            if [[ $new_state != on ]]; then
                notify-send "Bluetooth" "Error al desbloquear" -i "package-purge"
                exit 1
            fi
            ;;
        *)
            return 0
            ;;
    esac

    notify-send "Bluetooth Encendido" -i "network-bluetooth-activated" \
        -h string:x-canonical-private-synchronous:bluetooth
}

get_devices() {
    bluetoothctl -t "$TIMEOUT" scan on > /dev/null &
    local scan_pid=$!

    local num i
    for ((i = 1; i <= TIMEOUT; i++)); do
        printf "\rBuscando dispositivos... (%d/%d)" "$i" "$TIMEOUT"
        printf "\n%bPresiona [q] para detener%b\n" "$FG_RED" "$FG_RESET"

        num=$(bluetoothctl devices | grep -c "^Device")
        printf "\nDispositivos: %d" "$num"

        printf "\e[3F"

        read -rsn 1 -t 1
        if [[ $REPLY == [Qq] ]]; then
            break
        fi
    done

    bluetoothctl scan off > /dev/null 2>&1
    kill "$scan_pid" 2> /dev/null

    printf "\n%bBúsqueda detenida.%b\n\n" "$FG_RED" "$FG_RESET"

    LIST=$(bluetoothctl devices | sed "s/^Device //")
    if [[ -z $LIST ]]; then
        notify-send "Bluetooth" "No se encontraron dispositivos" -i "package-broken"
        exit 1
    fi
}

# -- Selección e Interfaz --
annotate_connected() {
    local connected
    connected=$(bluetoothctl devices Connected | sed "s/^Device //" | awk '{print $1}')

    local line address display=""
    while IFS= read -r line; do
        address=${line%% *}
        if grep -qx "$address" <<< "$connected"; then
            display+="${line} [conectado]"$'\n'
        else
            display+="${line}"$'\n'
        fi
    done <<< "$LIST"

    printf -v DISPLAY_LIST '%s' "$display"
}

select_device() {
    annotate_connected

    local header
    printf -v header "%-17s %s" "Dirección" "Nombre"

    local options=(
        "--border=sharp"
        "--border-label= Dispositivos Bluetooth "
        "--cycle"
        "--ghost=Buscar"
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

# -- Gestión de Audio --
find_bt_sink() {
    local mac_us="${ADDRESS//:/_}"
    local sink i
    for ((i = 1; i <= 5; i++)); do
        sink=$(pactl list sinks short | awk -v m="bluez_output.$mac_us" '$2 ~ m {print $2; exit}')
        [[ -n $sink ]] && { printf '%s' "$sink"; return 0; }
        sleep 1
    done
    return 1
}

get_node_id() {
    local name=$1
    pw-cli ls Node 2> /dev/null | awk -v pat="$name" '
        /^[[:space:]]*id [0-9]+,/ {
            n = split($0, a, " ")
            id = a[2]
            sub(/,$/, "", id)
        }
        $0 ~ ("node\\.name = \"" pat "\"") {
            print id
            exit
        }
    '
}

switch_to_bt_sink() {
    local sink_name
    if ! sink_name=$(find_bt_sink); then
        return 0
    fi

    local sink_id i
    for ((i = 1; i <= 5; i++)); do
        sink_id=$(get_node_id "$sink_name")
        [[ -n $sink_id ]] && break
        sleep 1
    done
    [[ -z $sink_id ]] && return 0

    local current_default
    current_default=$(pactl get-default-sink 2> /dev/null)

    if [[ -n $current_default && $current_default != bluez_output.* ]]; then
        printf '%s' "$current_default" > "$STATE_FILE"
    fi

    wpctl set-default "$sink_id"

    local input_id
    while read -r input_id; do
        [[ -n $input_id ]] && pactl move-sink-input "$input_id" "$sink_name" 2> /dev/null
    done < <(pactl list sink-inputs short | awk '{print $1}')
}

restore_previous_sink() {
    [[ -f $STATE_FILE ]] || return 0

    local prev prev_id
    prev=$(< "$STATE_FILE")
    rm -f "$STATE_FILE"
    [[ -z $prev ]] && return 0

    prev_id=$(get_node_id "$prev")
    if [[ -n $prev_id ]]; then
        wpctl set-default "$prev_id"

        local input_id
        while read -r input_id; do
            [[ -n $input_id ]] && pactl move-sink-input "$input_id" "$prev" 2> /dev/null
        done < <(pactl list sink-inputs short | awk '{print $1}')
    fi
}

# -- Conexión y Desconexión --
pair_and_connect() {
    local paired
    paired=$(bluetoothctl info "$ADDRESS" | awk '/Paired/ {print $2}')

    if [[ $paired == no ]]; then
        printf "Emparejando..."

        if ! timeout "$TIMEOUT" bluetoothctl pair "$ADDRESS" > /dev/null; then
            notify-send "Bluetooth" "Error al emparejar" -i "package-purge"
            exit 1
        fi
    fi

    printf "\nConectando..."

    if ! timeout "$TIMEOUT" bluetoothctl connect "$ADDRESS" > /dev/null; then
        notify-send "Bluetooth" "Error al conectar" -i "package-purge"
        exit 1
    fi

    switch_to_bt_sink

    notify-send "Bluetooth" "Conectado con éxito" -i "package-install"
}

disconnect_device() {
    local name
    name=$(bluetoothctl info "$ADDRESS" | awk -F ': ' '/Name/ {print $2}')

    printf "Desconectando..."

    if ! timeout "$TIMEOUT" bluetoothctl disconnect "$ADDRESS" > /dev/null; then
        notify-send "Bluetooth" "Error al desconectar" -i "package-purge"
        exit 1
    fi

    if ! pactl list sinks short | awk '{print $2}' | grep -q '^bluez_output\.'; then
        restore_previous_sink
    fi

    notify-send "Bluetooth" "Desconectado de ${name:-dispositivo}" -i "network-bluetooth-disconnected"
}

# -- Función Principal --
main() {
    trap 'restore_cursor; kill -9 $PPID 2>/dev/null' EXIT

    check_deps

    if [[ ${1-} == off ]]; then
        bluetoothctl power off
        restore_previous_sink
        notify-send 'Bluetooth Apagado' -i 'network-bluetooth-inactive' \
            -h string:x-canonical-private-synchronous:bluetooth
        exit 0
    fi

    printf "\e[?25l"
    power_on
    get_devices

    printf "\e[?25h"
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