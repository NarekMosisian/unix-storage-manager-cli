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

export LANG=en_US.UTF-8
export LC_ALL=en_US.UTF-8
export NCURSES_NO_UTF8_ACS=1

# XDG Base Directories (available on both macOS and Linux)
XDG_DATA="${XDG_DATA_HOME:-"$HOME/.local/share"}"
XDG_CONFIG="${XDG_CONFIG_HOME:-"$HOME/.config"}"
XDG_CACHE="${XDG_CACHE_HOME:-"$HOME/.cache"}"

FIND_METHOD_FILE="find_method.conf"

LANG_CONF_FILE="language.conf"
CURRENT_LANG="English"

LOG_FILE="unix_storage_manager.log"
if [ ! -f "$LOG_FILE" ]; then
    touch "$LOG_FILE"
fi
echo "Script started at $(date)" >> "$LOG_FILE"

OS_TYPE=$(uname)
if [ "$OS_TYPE" != "Darwin" ] && [ "$OS_TYPE" != "Linux" ]; then
    echo "This script currently only supports macOS and Linux." >&2
    exit 1
fi

APP_DIRS=()
if [ "$OS_TYPE" = "Darwin" ]; then
    APP_DIRS+=( "/Applications" "$HOME/Applications" )
else
    APP_DIRS+=( "/usr/share/applications" "$HOME/.local/share/applications" )
fi

if [ "$OS_TYPE" = "Darwin" ]; then
    extension="app"
else
    extension="desktop"
fi

[ -n "${CUSTOM_APP_DIR:-}" ] && APP_DIRS+=( "${CUSTOM_APP_DIR}" )

SOUND_PATH="./sounds"
if [ -n "${MAC_STORAGE_MANAGER_SHARE:-}" ]; then
    SOUND_PATH="${MAC_STORAGE_MANAGER_SHARE}/sounds"
fi

load_language() {
    if [ -f "$LANG_CONF_FILE" ]; then
        CURRENT_LANG=$(<"$LANG_CONF_FILE")
    else
        CURRENT_LANG="English"
        echo "$CURRENT_LANG" > "$LANG_CONF_FILE"
    fi
}

if [ -f "sound.conf" ]; then
    SOUND_ENABLED=$(<sound.conf)
else
    SOUND_ENABLED="on"
    echo "$SOUND_ENABLED" > sound.conf
fi

save_sound_setting() {
    echo "$SOUND_ENABLED" > "sound.conf"
}

load_language

save_language() {
    echo "$CURRENT_LANG" > "$LANG_CONF_FILE"
}

cleanup() {
    log_message "Cleaning up temporary files..."
    rm -f brew_formula_sizes.txt brew_cask_sizes.txt applications_sizes.txt home_applications_sizes.txt sudo_find_results.txt
}
