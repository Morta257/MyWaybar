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
            # Reemplaza este proceso por power.sh, así se abre
            # en la MISMA terminal (misma ventana de kitty).
            # Cuando power.sh termine, la terminal se cerrará sola.
            exec bash "$HOME/.config/waybar/scripts/power.sh"
            ;;

        *btop*)
            # Misma clase que la terminal del menú ("menu-main") para
            # que le aplique la MISMA windowrule que ya tienes, y le
            # pedimos a kitty un tamaño inicial suficiente en celdas.
            setsid -f kitty --class menu \
                -o initial_window_width=800c \
                -o initial_window_height=600c \
                -e btop &> /dev/null &
            disown
            # Pequeña pausa para que la nueva ventana de kitty alcance
            # a crearse/mapearse antes de cerrar la terminal del menú.
            sleep 0.3
            kill -9 "$PPID"
            ;;

        *Capturar*)
            # Lanza grim/slurp totalmente desacoplado de esta terminal
            # (setsid -f) para que sobreviva aunque matemos la terminal.
            setsid -f bash -c '
                grim -g "$(slurp -b 59595966 -c 121212 -s 00000000)" - | wl-copy
            ' &> /dev/null &
            disown
            # Deja que el proceso desacoplado termine de independizarse
            # antes de cerrar esta terminal.
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