#!/bin/bash

action=$1
target=$2
amount=$3

case $action in
    output)
        case $target in
            raise)
                wpctl set-volume -l 1.0 @DEFAULT_AUDIO_SINK@ 5%+
                vol=$(wpctl get-volume @DEFAULT_AUDIO_SINK@ | awk '{print int($2 * 100)}')
                notify-send -h string:x-canonical-private-synchronous:volume_notif "Volumen" "Nivel: $vol%" -t 1000
                ;;
            lower)
                wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%-
                vol=$(wpctl get-volume @DEFAULT_AUDIO_SINK@ | awk '{print int($2 * 100)}')
                notify-send -h string:x-canonical-private-synchronous:volume_notif "Volumen" "Nivel: $vol%" -t 1000
                ;;
            mute)
                wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle
                # Opcional: Notificación para el mute
                status=$(wpctl get-mute @DEFAULT_AUDIO_SINK@ | awk '{print $2}')
                [ "$status" == "[MUTED]" ] && notify-send -h string:x-canonical-private-synchronous:volume_notif "Audio" "Silenciado" -t 1000 || notify-send -h string:x-canonical-private-synchronous:volume_notif "Audio" "Desilenciado" -t 1000
                ;;
        esac
        ;;
esac