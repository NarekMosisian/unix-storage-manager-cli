#!/usr/bin/env bash
# main.sh

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

source config.sh
source translations.sh
source logging.sh
source sudo_utils.sh
source size_calculations.sh
source deletion.sh
source menu.sh
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

if [ "$1" = "--test-run" ]; then
    if [ "$OS_TYPE" = "Darwin" ]; then
        echo "Dummy.app"
    else
        echo "dummy.desktop"
    fi
    echo "DEBUG: SOUND_PATH=$MAC_STORAGE_MANAGER_SHARE/sounds" > "$LOG_FILE"
    ls -l "$MAC_STORAGE_MANAGER_SHARE/sounds" >> "$LOG_FILE" 2>&1
    exit 0
fi

handle_sudo_find() {
    local include_sudo_find=false
    if whiptail --title "$(get_text include_sudo_find)" \
        --yesno "$(get_text do_you_want_sudo_find)" 8 78 \
        --yes-button "$(get_yes_button)" \
        --no-button  "$(get_no_button)"; then
        play_key_sound
        include_sudo_find=true
    else
        play_key_sound
    fi
    gather_application_sizes "$include_sudo_find"
}

gather_application_sizes() {
    local include_sudo_find="$1"
    local pipe pid
    if [ "$include_sudo_find" = true ]; then
        ensure_sudo_valid
        if [ $? -ne 0 ]; then
            log_message "User canceled the sudo password prompt."
            display_error "Sudo password not provided or canceled."
            include_sudo_find=false
        fi
    fi
    pipe=$(mktemp -u)
    mkfifo "$pipe"
    ( whiptail --gauge "$(get_text gathering_application_sizes...)" 6 60 0 \
        --ok-button "$(get_ok_button)" --cancel-button "$(get_cancel_button)" < "$pipe" ) &
    pid=$!
    exec 3> "$pipe"
    {
        update_progress 0 "Starting Homebrew formula size calculation..."
        if command -v brew &>/dev/null; then
            brew list --formula | while read -r formula; do
                size=$(calculate_brew_formula_size "$formula")
                echo "$formula:$size"
            done > brew_formula_sizes.txt
        fi
        update_progress 20 "Starting Homebrew cask size calculation..."
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
        if [ "$include_sudo_find" = true ]; then
            update_progress 85 "Running 'sudo find'..."
            local password
            password=$(ensure_sudo_valid)
            echo "$password" | sudo -k -S find / -iname "*.${extension}" -type d -maxdepth 5 -print0 2>/dev/null \
                | sort -z -u \
                | while IFS= read -r -d '' app; do
                    size=$(calculate_size "$app")
                    app_basename=$(basename "$app")
                    echo "$app_basename:$size"
                done | sort -t':' -k1,1 -u > sudo_find_results.txt
            unset password
        fi
        update_progress 100 "Process completed."
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

    interactive_app_selection "${sorted_items[@]}"
    main_menu
}

check_homebrew() {
    if ! command -v brew &> /dev/null; then
        whiptail --title "$(get_text error)" --msgbox "$(get_text homebrew_not_installed_msg)" 8 60 \
            --ok-button "$(get_ok_button)" --cancel-button "$(get_cancel_button)"
        log_message "Critical error: Homebrew is not installed."
        exit 1
    fi
}
check_homebrew

main_menu

log_end