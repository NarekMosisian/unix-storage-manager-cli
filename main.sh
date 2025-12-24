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

source config.sh
set +u
source translations.sh
set -u
source logging.sh
source sudo_utils.sh
source size_calculations.sh
source deletion.sh
source menu.sh
source delete_history.sh
source sound.sh

trap cleanup EXIT

if [ "$OS_TYPE" = "Linux" ]; then
    SOUND_PLAYER="paplay"
else
    SOUND_PLAYER="afplay"
fi

if [ -f "$SOUND_PATH/switch.wav" ]; then
    log_message "Sound check successful"
else
    log_message "Sound check failed: switch.wav not found in $SOUND_PATH"
fi

if [ "${1:-}" = "--test-run" ]; then
    if [ "$OS_TYPE" = "Darwin" ]; then
        echo "Dummy.app"
    else
        echo "dummy.desktop"
    fi
    echo "DEBUG: SOUND_PATH=$SOUND_PATH" > "$LOG_FILE"
    ls -l "$SOUND_PATH" >> "$LOG_FILE" 2>&1
    exit 0
fi

handle_sudo_find() {
    local include_sudo_find=false
    local scan_type=""
    local prev=""
    if [ -f "$FIND_METHOD_FILE" ]; then
        prev=$(<"$FIND_METHOD_FILE")
    fi

    if whiptail --title "$(get_text include_sudo_find)" \
                --yesno "$(get_text do_you_want_sudo_find)" 8 78 \
                --yes-button "$(get_yes_button)" \
                --no-button "$(get_no_button)"; then
        play_key_sound
        include_sudo_find=true

        if whiptail --title "$(get_text select_scan_type_title)" --defaultno \
           --yesno "$(get_text select_scan_type_message)" \
           16 70 \
           --yes-button "full" \
           --no-button "optimized"; then
            scan_type="full"
        else
            scan_type="optimized"
        fi

        echo "$scan_type" > "$FIND_METHOD_FILE"
        play_key_sound
    fi

    local ts
    ts=$(date '+%Y-%m-%d %H:%M:%S')
    if [ "$include_sudo_find" = false ]; then
        log_message "[$ts] Normal scan executed"
    fi

    gather_application_sizes "$include_sudo_find" "$scan_type"
}

gather_application_sizes() {
    local include_sudo_find="$1"
    local scan_type="${2:-optimized}"

    if [ "$include_sudo_find" = true ]; then
        ensure_sudo_valid
        local ts
        ts=$(date '+%Y-%m-%d %H:%M:%S')
        if [ "$scan_type" = "full" ]; then
            log_message "[$ts] sudo-find scan (full) executed"
        else
            log_message "[$ts] sudo-find scan (optimized) executed"
        fi
    fi

    local pipe pid
    pipe=$(mktemp -u)
    mkfifo "$pipe"
    (
      whiptail --gauge "$(get_text gathering_application_sizes...)" 6 60 0 \
               --ok-button "$(get_ok_button)" \
               --cancel-button "$(get_cancel_button)" < "$pipe"
    ) &
    pid=$!
    exec 3> "$pipe"

    {
        update_progress 0 "$(get_text starting_homebrew_formula_size_calc)"
        if command -v brew &>/dev/null; then
            brew list --formula | while read -r formula; do
                size=$(calculate_brew_formula_size "$formula")
                echo "$formula:$size"
            done > brew_formula_sizes.txt
        fi

        update_progress 20 "$(get_text starting_homebrew_cask_size_calc)"
        if command -v brew &>/dev/null; then
            brew list --cask | while read -r cask; do
                size=$(calculate_brew_cask_size "$cask")
                echo "$cask:$size"
            done > brew_cask_sizes.txt
        fi

        > applications_sizes.txt
        for dir in "${APP_DIRS[@]}"; do
            find "$dir" -maxdepth 1 -iname "*.${extension}" -print0 2>/dev/null \
            | while IFS= read -r -d '' app; do
                size=$(du -sk "$app" 2>/dev/null | cut -f1)
                echo "$(basename "$app"):$size"
            done
        done >> applications_sizes.txt

        if [ "$OS_TYPE" = "Linux" ]; then
            > home_applications_sizes.txt
            find "$HOME/.local/share/applications" -maxdepth 1 -iname "*.desktop" -print0 2>/dev/null \
            | while IFS= read -r -d '' app; do
                size=$(du -sk "$app" 2>/dev/null | cut -f1)
                echo "$(basename "$app"):$size"
            done > home_applications_sizes.txt
        fi

        if [ "$include_sudo_find" = true ]; then
            if [ "$scan_type" = "full" ]; then
                update_progress 85 "$(get_text running_sudo_find_full)"
                sudo -n find / -iname "*.${extension}" -type d -maxdepth 5 -print0 2>/dev/null \
                  | sort -z -u \
                  | xargs -0 du -sk --files0-from=- 2>/dev/null \
                  | awk -F'\t' '{print $2 ":" $1}' \
                  > sudo_find_results.txt || true
            else
                update_progress 85 "$(get_text running_sudo_find_optimized)"
                sudo -n find / -mount \
                  \( -path /dev -o -path /proc -o -path /sys -o -path /var \) -prune -o \
                  -iname "*.${extension}" -type d -maxdepth 5 -print0 2>/dev/null \
                  | xargs -0 du -sk --files0-from=- 2>/dev/null \
                  | awk -F'\t' '{print $2 ":" $1}' \
                  > sudo_find_results.txt || true
            fi
        fi

        update_progress 100 "$(get_text process_completed)"
        exec 3>&-
    } > /dev/null 2>&1

    rm "$pipe"
    wait $pid
    sleep 0.5
}

start_collection() {
    handle_sudo_find
    combine_results
    reconstruct_log_entries

    if [ ${#sorted_items[@]} -eq 0 ]; then
        whiptail --title "$(get_text no_applications_found)" \
                 --msgbox "$(get_text no_applications_found_for_selection)" 8 60 \
                 --ok-button "$(get_ok_button)"
        return
    fi

    interactive_app_selection
}

check_homebrew() {
    if ! command -v brew &>/dev/null; then
        whiptail --title "$(get_text error)" \
                 --msgbox "$(get_text homebrew_not_installed_msg)" 8 60 \
                 --ok-button "$(get_ok_button)" \
                 --cancel-button "$(get_cancel_button)"
        log_message "Critical error: Homebrew is not installed."
        exit 1
    fi
}
check_homebrew

while true; do
    main_menu
done
