#!/usr/bin/env bash
# sudo_utils.sh

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

ensure_sudo_valid() {
    local attempts=0
    while true; do
        local password
        password=$(whiptail --passwordbox "$(get_text please_enter_your_sudo_password)" 8 60 3>&1 1>&2 2>&3)
        if [ $? -ne 0 ] || [ -z "$password" ]; then
            log_message "Sudo password not provided or canceled."
            display_error "Sudo password not provided or canceled."
            exit 1
        fi
        play_key_sound
        echo "$password" | sudo -k -S -v 2>/dev/null
        if [ $? -eq 0 ]; then
            unset password
            return 0
        fi
        attempts=$((attempts + 1))
        log_message "$(printf "$(get_text invalid_sudo_password_attempts)" "$attempts")"
        display_error "$(printf "$(get_text invalid_sudo_password_attempts)" "$attempts")"
        unset password
        if [ $attempts -ge 3 ]; then
            log_message "$(get_text failed_obtain_sudo_after_3_exiting)"
            display_error "$(get_text failed_obtain_sudo_after_3_exiting)"
            exit 1
        fi
    done
}

run_sudo_command() {
    local password
    password=$(ensure_sudo_valid)
    echo "$password" | sudo -k -S "$@" 2>/dev/null
    unset password
}
