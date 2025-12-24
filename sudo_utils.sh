#!/usr/bin/env bash
# SPDX-License-Identifier: AGPL-3.0-or-later
set -euo pipefail
IFS=$'\n\t'

# ------------------------------------------------------------------------------------------------------
# Unix Storage Manager - Cross-Platform internationalized Version (macOS/Linux)
#
#  This script was created by Narek Mosisian. For more information, visit:
#      https://github.com/NarekMosisian/unix-storage-manager-cli
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
    local password
    while true; do
        if ! password=$(whiptail --passwordbox "$(get_text please_enter_your_sudo_password)" 8 60 3>&1 1>&2 2>&3); then
            log_message "Sudo password dialog canceled."
            main_menu
            return 1
        fi
        if [ -z "$password" ]; then
            display_error "$(get_text critical_error_sudo_failed_associated)"
            main_menu
            return 1
        fi

        if echo "$password" | sudo -S -v >/dev/null 2>&1; then
            unset password
            return 0
        fi

        attempts=$((attempts + 1))
        display_error "$(printf "$(get_text invalid_sudo_password_attempts)" "$attempts")"

        if [ $attempts -ge 3 ]; then
            display_error "$(get_text failed_obtain_sudo_after_3_exiting)"
            main_menu
            return 1
        fi
    done
}
