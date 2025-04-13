#!/usr/bin/env bash
# config.sh

# ------------------------------------------------------------------------------------------------------
# Mac Storage Manager - Cross-Platform Version (macOS/Linux)
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

export LANG=en_US.UTF-8
export LC_ALL=en_US.UTF-8
export NCURSES_NO_UTF8_ACS=1

LANG_CONF_FILE="language.conf"
CURRENT_LANG="English"

LOG_FILE="mac_storage_manager.log"
if [ ! -f "$LOG_FILE" ]; then
    touch "$LOG_FILE"
fi
echo "Script started at $(date)" >> "$LOG_FILE"

OS_TYPE=$(uname)
if [ "$OS_TYPE" != "Darwin" ] && [ "$OS_TYPE" != "Linux" ]; then
    echo "This script currently only supports macOS and Linux." >&2
    exit 1
fi

if [ "$OS_TYPE" = "Linux" ]; then
    XDG_DATA=${XDG_DATA_HOME:-"$HOME/.local/share"}
    XDG_CONFIG=${XDG_CONFIG_HOME:-"$HOME/.config"}
    XDG_CACHE=${XDG_CACHE_HOME:-"$HOME/.cache"}
fi

SOUND_PATH="./sounds"
if [ -n "$MAC_STORAGE_MANAGER_SHARE" ]; then
    SOUND_PATH="$MAC_STORAGE_MANAGER_SHARE/sounds"
fi

load_language() {
    if [ -f "$LANG_CONF_FILE" ]; then
        CURRENT_LANG=$(<"$LANG_CONF_FILE")
    else
        CURRENT_LANG="English"
        echo "$CURRENT_LANG" > "$LANG_CONF_FILE"
    fi
}
load_language

save_language() {
    echo "$CURRENT_LANG" > "$LANG_CONF_FILE"
}

cleanup() {
    log_message "Cleaning up temporary files..."
    rm -f brew_formula_sizes.txt brew_cask_sizes.txt applications_sizes.txt home_applications_sizes.txt sudo_find_results.txt
}