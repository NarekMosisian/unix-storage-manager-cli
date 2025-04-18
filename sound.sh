#!/usr/bin/env bash
# sound.sh

# ------------------------------------------------------------------------------------------------------
# Mac Storage Manager - Cross-Platform internationalized Version (macOS/Linux)
#
#  This script was created by Narek Mosisian. For more information, visit:
#      https://github.com/NarekMosisian/mac-storage-manager
#  © 2024 Narek Mosisian. All rights reserved.
#
#  This script is licensed under the AGPL-3.0 license.
# ------------------------------------------------------------------------------------------------------
#  NOTICE:
#  If you distribute, modify, or incorporate any parts of this code, you must ensure that
#  the original author's name, "Narek Mosisian", is clearly attributed in all copies and
#  derivative works. Additionally, any derivative work must be distributed under the AGPL-3.0 license.
#  This requirement is mandated by the terms of the AGPL-3.0 license.
# ------------------------------------------------------------------------------------------------------

play_key_sound() {
    if [ "$SOUND_ENABLED" = "on" ]; then
        if [ -f "$SOUND_PATH/switch.wav" ]; then
            $SOUND_PLAYER "$SOUND_PATH/switch.wav" &
        else
            log_message "Sound file not found: $SOUND_PATH/switch.wav"
        fi
    fi
}

toggle_sound() {
    if [ "$SOUND_ENABLED" = "on" ]; then
        btn_label="$(get_text sound_off_button)"
    else
        btn_label="$(get_text sound_on_button)"
    fi

    whiptail --title "$(get_text sound_title)" \
             --msgbox "$(printf "$(get_text sound_status_message)" "$SOUND_ENABLED")" 8 60 \
             --ok-button "$btn_label"

    if [ "$SOUND_ENABLED" = "on" ]; then
        SOUND_ENABLED="off"
    else
        SOUND_ENABLED="on"
    fi
    save_sound_setting

    play_key_sound

    main_menu
}

