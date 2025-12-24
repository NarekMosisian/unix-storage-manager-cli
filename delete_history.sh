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

show_delete_history() {
    local tmpfile
    tmpfile=$(mktemp)
    if ! grep -F "Deleted application" "$LOG_FILE" | tac > "$tmpfile"; then
        echo "$(get_text delete_history_not_found)" > "$tmpfile"
    fi

    whiptail --title "$(get_text delete_history_title) ($(get_text delete_history_only_by_this_script))" \
             --textbox "$tmpfile" 20 78 \
             --ok-button "$(get_ok_button)"
    rm -f "$tmpfile"

    main_menu
}