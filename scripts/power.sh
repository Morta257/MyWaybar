#!/usr/bin/env bash

main() {
    local list=(
        "󰌾 Lock"
        "󰐥 Shutdown"
        "󰜉 Reboot"
        "󰍃 Logout"
        "󰤄 Hibernate"
        "󰤄 Suspend"
    )

    local options=(
        "--border=rounded"
        "--border-label= Power "
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
        *Lock*)      hyprlock ;;
        *Shutdown*)  systemctl poweroff ;;
        *Reboot*)    systemctl reboot ;;
        *Logout*)    uwsm stop ;;
        *Hibernate*) systemctl hibernate ;;
        *Suspend*)   systemctl suspend ;;
    esac
}

main