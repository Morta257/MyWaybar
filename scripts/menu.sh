#!/usr/bin/env bash
main() {
    local list=(
        "󰐥 Menú de Energía"
        "󰄛 Monitor de Sistema (btop)"
        "󰹑 Capturar Área (Pantalla)"
        "󰍉 Lanzador de Apps (Rofi)"
    )
    local options=(
        "--border=rounded"
        "--border-label= Menú Principal "
        "--cycle"
        "--height=40%"
        "--highlight-line"
        "--layout=reverse"
        "--info=hidden"
        "--margin=1,2"
        "--pointer=▶"
        "--reverse"
    )
    local selected
    selected=$(printf "%s\n" "${list[@]}" | fzf "${options[@]}")

    case "$selected" in
        *Energía*)
            exec bash "$HOME/.config/waybar/scripts/power.sh"
            ;;

        *btop*)
            setsid -f kitty --class menu \
                -o initial_window_width=800c \
                -o initial_window_height=600c \
                -e btop &> /dev/null &
            disown
            sleep 0.3
            kill -9 "$PPID"
            ;;

        *Capturar*)
            setsid -f bash -c '
                grim -g "$(slurp -b 59595966 -c 121212 -s 00000000)" - | wl-copy
            ' &> /dev/null &
            disown
            sleep 0.3
            kill -9 "$PPID"
            ;;

        *Rofi*)
            setsid -f rofi -show drun -show-icons &> /dev/null &
            disown
            sleep 0.3
            kill -9 "$PPID"
            ;;

        *)
            kill -9 "$PPID"
            ;;
    esac
}
main