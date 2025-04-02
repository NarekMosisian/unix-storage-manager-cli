#!/usr/bin/env zsh
# ===================================================================================
# Mac Storage Manager - Cross-Platform Version (macOS/Linux)
#
# For more information, visit: https://github.com/NarekMosisian/mac-storage-manager
# © 2024 Narek Mosisian. All rights reserved.
# ===================================================================================

LOG_FILE="application_size_checker.log"

# OS detection
OS_TYPE=$(uname)
if [ "$OS_TYPE" != "Darwin" ] && [ "$OS_TYPE" != "Linux" ]; then
    echo "This script currently only supports macOS and Linux." >&2
    exit 1
fi

if [ "$1" = "--test-run" ]; then
  if [ "$OS_TYPE" = "Darwin" ]; then
    echo "Dummy.app"
  else
    echo "dummy.desktop"
  fi
  echo "DEBUG: SOUND_PATH=$MAC_STORAGE_MANAGER_SHARE/sounds" > application_size_checker.log
  ls -l "$MAC_STORAGE_MANAGER_SHARE/sounds" >> application_size_checker.log 2>&1
  exit 0
fi

# For Linux: Set XDG variables (if not already set)
if [ "$OS_TYPE" = "Linux" ]; then
    XDG_DATA=${XDG_DATA_HOME:-"$HOME/.local/share"}
    XDG_CONFIG=${XDG_CONFIG_HOME:-"$HOME/.config"}
    XDG_CACHE=${XDG_CACHE_HOME:-"$HOME/.cache"}
fi

SOUND_PATH="./sounds"

# If the environment variable is set (by Homebrew), use it to set the sound path
if [ -n "$MAC_STORAGE_MANAGER_SHARE" ]; then
    SOUND_PATH="$MAC_STORAGE_MANAGER_SHARE/sounds"
fi

# Initialize log file and record start time
if [ ! -f "$LOG_FILE" ]; then
    touch "$LOG_FILE"
fi
echo "Script started at $(date)" >> "$LOG_FILE"

# Sound check: Only log success or failure for sound check
if [ -f "$SOUND_PATH/switch.wav" ]; then
    echo "Sound check successful" >> "$LOG_FILE"
else
    echo "Sound check failed: switch.wav not found in $SOUND_PATH" >> "$LOG_FILE"
fi

# Sound player command depending on OS
if [ "$OS_TYPE" = "Linux" ]; then
    SOUND_PLAYER="paplay"
else
    SOUND_PLAYER="afplay"
fi

# Initialize sudo password
sudo_password=""

display_error() {
    local message="$1"
    whiptail --title "Critical Error" --msgbox "$message" 8 60
}

play_key_sound() {
    if [ -f "$SOUND_PATH/switch.wav" ]; then
        $SOUND_PLAYER "$SOUND_PATH/switch.wav" &
    else
        echo "Sound file not found: $SOUND_PATH/switch.wav" >> "$LOG_FILE"
        display_error "Sound file not found: $SOUND_PATH/switch.wav"
    fi
}

request_sudo_password() {
    sudo_password=$(whiptail --passwordbox "Please enter your sudo password:" 8 60 3>&1 1>&2 2>&3)
    retcode=$?
    if [ $retcode -ne 0 ] || [ -z "$sudo_password" ]; then
        echo "Sudo password not provided or canceled." >> "$LOG_FILE"
        display_error "Sudo password not provided or canceled."
        sudo_password=""
        return 1
    fi
    play_key_sound
    return 0
}

ensure_sudo_valid() {
    local attempts=0
    while true; do
        if sudo -n true 2>/dev/null; then
            return 0
        fi

        if [ $attempts -ge 3 ]; then
            echo "Failed to obtain valid sudo credentials after 3 attempts." >> "$LOG_FILE"
            display_error "Failed to obtain valid sudo credentials after 3 attempts. Exiting."
            exit 1
        fi

        request_sudo_password
        if [ $? -ne 0 ]; then
            attempts=$((attempts + 1))
            echo "Sudo password input failed. Attempt $attempts of 3." >> "$LOG_FILE"
            display_error "Sudo password input failed. Attempt $attempts of 3."
            continue
        fi

        echo "$sudo_password" | sudo -S -v 2>/dev/null
        if [ $? -eq 0 ]; then
            return 0
        else
            attempts=$((attempts + 1))
            echo "Invalid sudo password. Attempt $attempts of 3 failed." >> "$LOG_FILE"
            display_error "Invalid sudo password. Attempt $attempts of 3 failed."
            sudo_password=""
        fi
    done
}

run_sudo_command() {
    echo "$sudo_password" | sudo -S "$@" 2>/dev/null
}

format_size() {
    local size_in_kb="$1"
    if (( size_in_kb >= 1048576 )); then
        awk "BEGIN {printf \"%.2fG\", $size_in_kb / 1048576}"
    elif (( size_in_kb >= 1024 )); then
        awk "BEGIN {printf \"%.2fM\", $size_in_kb / 1024}"
    elif (( size_in_kb > 0 )); then
        echo "${size_in_kb}K"
    else
        echo "0B"
    fi
}

calculate_size() {
    local app_path="$1"
    local size_in_kb
    size_in_kb=$(du -sk "$app_path" 2>/dev/null | cut -f1)
    if [ -n "$size_in_kb" ]; then
        echo "$size_in_kb"
    else
        echo "?"
        echo "Size not available for $app_path" >> "$LOG_FILE"
    fi
}

calculate_brew_formula_size() {
    if command -v brew &>/dev/null; then
        local formula_path
        formula_path=$(brew --cellar "$1" 2>/dev/null)
        if [ -d "$formula_path" ]; then
            calculate_size "$formula_path"
        else
            echo "?"
            echo "Brew formula '$1' size could not be determined (cellar path not found)." >> "$LOG_FILE"
        fi
    else
        echo "?"
    fi
}

calculate_brew_cask_size() {
    if command -v brew &>/dev/null; then
        local cask_name="$1"
        local brew_prefix
        local caskroom_path
        local size

        brew_prefix=$(brew --prefix)
        caskroom_path="$brew_prefix/Caskroom/$cask_name"

        if [ -d "$caskroom_path" ]; then
            size=$(du -sk "$caskroom_path" 2>/dev/null | cut -f1)
            if [ -n "$size" ] && [ "$size" -gt 0 ]; then
                echo "$size"
            else
                echo "?"
                echo "Size could not be determined for Cask: $cask_name." >> "$LOG_FILE"
            fi
        else
            echo "?"
            echo "Caskroom path does not exist for Cask: $cask_name." >> "$LOG_FILE"
        fi
    else
        echo "?"
    fi
}

update_progress() {
    local percent="$1"
    local message="$2"
    echo -e "$percent\n# $message" >&3
    sleep 0.5
}

gather_application_sizes() {
    local include_sudo_find="$1"
    local pipe pid

    if [ "$include_sudo_find" = true ]; then
        ensure_sudo_valid
        if [ $? -ne 0 ]; then
            echo "User canceled the sudo password prompt." >> "$LOG_FILE"
            display_error "User canceled the sudo password prompt."
            include_sudo_find=false
        fi
    fi

    pipe=$(mktemp -u)
    mkfifo "$pipe"

    (whiptail --gauge "Gathering application sizes..." 6 60 0 < "$pipe") &
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

        if [ "$OS_TYPE" = "Darwin" ]; then
            update_progress 40 "Calculating sizes in /Applications..."
            find /Applications -maxdepth 1 -name "*.app" -print0 | while IFS= read -r -d '' app; do
                size=$(calculate_size "$app")
                echo "$(basename "$app"):$size"
            done > applications_sizes.txt

            update_progress 60 "Calculating sizes in ~/Applications..."
            find "$HOME/Applications" -maxdepth 1 -name "*.app" -print0 2>/dev/null | while IFS= read -r -d '' app; do
                size=$(calculate_size "$app")
                echo "$(basename "$app"):$size"
            done > home_applications_sizes.txt
        elif [ "$OS_TYPE" = "Linux" ]; then
            update_progress 40 "Calculating sizes in /usr/share/applications..."
            if [ -d "/usr/share/applications" ]; then
                find /usr/share/applications -maxdepth 1 -name "*.desktop" -print0 | while IFS= read -r -d '' app; do
                    size=$(calculate_size "$app")
                    echo "$(basename "$app"):$size"
                done > applications_sizes.txt
            fi

            update_progress 60 "Calculating sizes in ~/.local/share/applications..."
            if [ -d "$HOME/.local/share/applications" ]; then
                find "$HOME/.local/share/applications" -maxdepth 1 -name "*.desktop" -print0 2>/dev/null | while IFS= read -r -d '' app; do
                    size=$(calculate_size "$app")
                    echo "$(basename "$app"):$size"
                done > home_applications_sizes.txt
            fi
        fi

        if [ "$include_sudo_find" = true ]; then
            update_progress 85 "Running 'sudo find'..."
            if [ "$OS_TYPE" = "Darwin" ]; then
                extension="app"
            else
                # For Linux, we also search for .desktop files
                extension="desktop"
            fi

            # Make paths unique and output only the basename with size.
            echo "$sudo_password" | sudo -S find / -iname "*.${extension}" -type d -maxdepth 5 -print0 2>/dev/null \
                | sort -z -u \
                | while IFS= read -r -d '' app; do
                    size=$(calculate_size "$app")
                    app_basename=$(basename "$app")
                    echo "$app_basename:$size"
                done \
                | sort -t':' -k1,1 -u \
                > sudo_find_results.txt
        fi

        update_progress 100 "Process completed."
        exec 3>&-
    } > /dev/null 2>&1

    rm "$pipe"
    wait $pid
    sleep 0.5
}

handle_sudo_find() {
    local include_sudo_find=false

    if whiptail --title "Include sudo find?" --yesno "Do you want to include application search via 'sudo find'?" 8 78; then
        play_key_sound
        include_sudo_find=true
    else
        play_key_sound
    fi

    gather_application_sizes "$include_sudo_find"
}

format_and_sort_results() {
    local items=("$@")
    local formatted_items=()
    local item app_name app_size_kb formatted_size
    for item in "${items[@]}"; do
        app_name=$(echo "$item" | cut -d':' -f1)
        app_size_kb=$(echo "$item" | cut -d':' -f2)
        formatted_size=$(format_size "$app_size_kb")
        formatted_items+=("$app_name:$formatted_size:$app_size_kb")
    done
    # Sorted by third field (KB number) descending
    printf "%s\n" "${formatted_items[@]}" | sort -t':' -k3nr
}

confirm_deletion() {
    local selected_apps="$1"
    local apps_to_delete=()
    local app clean_app

    echo "Selected apps: $selected_apps" >> "$LOG_FILE"
    eval "apps_to_delete=($selected_apps)"

    if [ ${#apps_to_delete[@]} -eq 0 ]; then
        whiptail --title "Error" --msgbox "No applications were selected for deletion. Please try again." 8 60
        echo "No apps to delete, exiting." >> "$LOG_FILE"
        return
    fi

    local deletion_message="Are you sure you want to permanently delete the following applications?\n\n"
    for app in "${apps_to_delete[@]}"; do
        clean_app=$(echo "$app" | tr -d '"')
        deletion_message+="$clean_app\n"
    done
    deletion_message+="\nThis action cannot be undone."

    if whiptail --title "Confirm deletion" --yesno "$deletion_message" 15 60; then
        play_key_sound
        echo "Confirmed deletion" >> "$LOG_FILE"

        ensure_sudo_valid
        if [ $? -ne 0 ]; then
            whiptail --title "Error" --msgbox "Sudo authentication failed. Cannot proceed with deletion." 8 60
            echo "Critical error: Sudo authentication failed during deletion." >> "$LOG_FILE"
            return
        fi

        local total=${#apps_to_delete[@]}
        local count=0
        local percentage=0
        local pipe pid

        pipe=$(mktemp -u)
        mkfifo "$pipe"

        (whiptail --gauge "Deleting applications..." 6 60 0 < "$pipe") &
        pid=$!

        exec 3> "$pipe"
        {
            for app in "${apps_to_delete[@]}"; do
                clean_app=$(echo "$app" | tr -d '"')
                count=$((count + 1))
                percentage=$(( (count * 100) / total ))
                echo -e "$percentage\n# Deleting $clean_app" >&3
                echo "Deleting $clean_app..." >> "$LOG_FILE"
                delete_application "$clean_app"
                echo "$clean_app deleted." >> "$LOG_FILE"
            done
            exec 3>&-
        } > /dev/null 2>&1

        rm "$pipe"
        wait $pid
        sleep 0.5

        ask_to_delete_associated_files "${apps_to_delete[@]}"

        whiptail --title "Deletion completed" --msgbox "The selected applications and associated files have been successfully deleted." 8 60
    else
        play_key_sound
        whiptail --title "Deletion canceled" --msgbox "No applications were deleted." 8 60
        echo "User canceled deletion" >> "$LOG_FILE"
    fi
}

delete_application() {
    local app_name="$1"
    local app_path

    echo "Attempting to delete: $app_name" >> "$LOG_FILE"

    local normalized_name=$(echo "$app_name" | sed 's/\.app$//i' | sed 's/\.desktop$//i' | tr '[:upper:]' '[:lower:]')

    if command -v brew &>/dev/null && brew list --cask | grep -q "^$normalized_name\$"; then
        echo "$app_name is installed as a Homebrew cask. Uninstalling via brew..." >> "$LOG_FILE"
        if brew uninstall --cask "$normalized_name" >> "$LOG_FILE" 2>&1; then
            echo "Successfully uninstalled cask $normalized_name." >> "$LOG_FILE"
            brew cleanup "$normalized_name" >> "$LOG_FILE" 2>&1
        else
            echo "Failed to uninstall cask $normalized_name." >> "$LOG_FILE"
            display_error "Failed to uninstall cask $app_name."
        fi
        return
    fi

    if command -v brew &>/dev/null && brew list --formula | grep -q "^$normalized_name\$"; then
        echo "$app_name is installed as a Homebrew formula. Uninstalling via brew..." >> "$LOG_FILE"
        if brew uninstall --formula "$normalized_name" >> "$LOG_FILE" 2>&1; then
            echo "Successfully uninstalled formula $normalized_name." >> "$LOG_FILE"
            brew cleanup "$normalized_name" >> "$LOG_FILE" 2>&1
        else
            echo "$app_name could not be uninstalled due to dependencies. Attempting force uninstall." >> "$LOG_FILE"
            brew uninstall --formula --ignore-dependencies "$normalized_name" >> "$LOG_FILE" 2>&1
        fi
        return
    fi

    if [ "$app_name" = "Docker.app" ] || [ "$app_name" = "Docker.desktop" ]; then
        if command -v brew &>/dev/null && brew list --cask | grep -q "^docker\$"; then
            echo "Docker is installed via Homebrew. Uninstalling..." >> "$LOG_FILE"
            if brew uninstall --cask docker >> "$LOG_FILE" 2>&1; then
                echo "Docker successfully uninstalled via Homebrew." >> "$LOG_FILE"
            else
                echo "Failed to uninstall Docker via Homebrew." >> "$LOG_FILE"
                display_error "Failed to uninstall Docker via Homebrew."
            fi
        else
            echo "Docker is not installed via Homebrew. Attempting manual deletion." >> "$LOG_FILE"
            if [ "$OS_TYPE" = "Darwin" ]; then
                app_path="/Applications/Docker.app"
            else
                app_path=""
            fi
            if [ -n "$app_path" ] && [ -d "$app_path" ]; then
                echo "Found Docker at $app_path. Deleting..." >> "$LOG_FILE"
                echo "$sudo_password" | sudo -S rm -rf -- "$app_path" >> "$LOG_FILE" 2>&1
                if [ $? -eq 0 ]; then
                    echo "Successfully deleted $app_path." >> "$LOG_FILE"
                else
                    echo "Failed to delete $app_path." >> "$LOG_FILE"
                    display_error "Failed to delete $app_path."
                fi
            else
                echo "Docker application not found in standard locations." >> "$LOG_FILE"
                display_error "Docker application not found in standard locations."
            fi
        fi
        return
    fi

    if [ "$OS_TYPE" = "Darwin" ]; then
        app_path=$(find /Applications "$HOME/Applications" -maxdepth 1 -name "$app_name" 2>/dev/null | head -n 1)
    elif [ "$OS_TYPE" = "Linux" ]; then
        app_path=$(find /usr/share/applications "$HOME/.local/share/applications" -maxdepth 1 -name "$app_name" 2>/dev/null | head -n 1)
    fi

    if [ -z "$app_path" ]; then
        echo "$app_name not found in standard locations. Attempting to find via sudo find..." >> "$LOG_FILE"
        app_path=$(echo "$sudo_password" | sudo -S find / -iname "$app_name" -type d -maxdepth 5 2>/dev/null | head -n 1)
    fi

    if [ -n "$app_path" ]; then
        echo "Found $app_name at $app_path. Deleting..." >> "$LOG_FILE"
        echo "$sudo_password" | sudo -S rm -rf -- "$app_path" >> "$LOG_FILE" 2>&1
        if [ $? -eq 0 ]; then
            echo "Successfully deleted $app_path." >> "$LOG_FILE"
        else
            echo "Failed to delete $app_path." >> "$LOG_FILE"
            display_error "Failed to delete $app_path."
        fi
    else
        echo "$app_name could not be found on the system." >> "$LOG_FILE"
        display_error "$app_name could not be found on the system."
    fi
}

ask_to_delete_associated_files() {
    local apps=("$@")
    local delete_app_files=false
    local delete_config_files=false
    local delete_cache_files=false
    local delete_log_files=false
    local delete_saved_state=false

    ensure_sudo_valid
    if [ $? -ne 0 ]; then
        whiptail --title "Error" --msgbox "Sudo authentication failed. Cannot proceed with deleting associated files." 8 60
        echo "Critical error: Sudo authentication failed for associated file deletion." >> "$LOG_FILE"
        return
    fi

    if [ "$OS_TYPE" = "Darwin" ]; then
        if whiptail --title "Delete Application Support?" --yesno "Do you want to delete the Application Support files for the selected applications?" 8 78; then
            play_key_sound
            delete_app_files=true
        else
            play_key_sound
        fi
        if whiptail --title "Delete Preferences?" --yesno "Do you want to delete the Preferences files for the selected applications?" 8 78; then
            play_key_sound
            delete_config_files=true
        else
            play_key_sound
        fi
        if whiptail --title "Delete Caches?" --yesno "Do you want to delete the Caches for the selected applications?" 8 78; then
            play_key_sound
            delete_cache_files=true
        else
            play_key_sound
        fi
        if whiptail --title "Delete Logs?" --yesno "Do you want to delete the Logs for the selected applications?" 8 78; then
            play_key_sound
            delete_log_files=true
        else
            play_key_sound
        fi
        if whiptail --title "Delete Saved Application State?" --yesno "Do you want to delete the Saved Application State for the selected applications?" 8 78; then
            play_key_sound
            delete_saved_state=true
        else
            play_key_sound
        fi
    elif [ "$OS_TYPE" = "Linux" ]; then
        if whiptail --title "Delete Application Data?" --yesno "Do you want to delete the application data (in $XDG_DATA) for the selected applications?" 8 78; then
            play_key_sound
            delete_app_files=true
        else
            play_key_sound
        fi
        if whiptail --title "Delete Configuration Files?" --yesno "Do you want to delete the configuration files (in $XDG_CONFIG) for the selected applications?" 8 78; then
            play_key_sound
            delete_config_files=true
        else
            play_key_sound
        fi
        if whiptail --title "Delete Cache Files?" --yesno "Do you want to delete the cache files (in $XDG_CACHE) for the selected applications?" 8 78; then
            play_key_sound
            delete_cache_files=true
        else
            play_key_sound
        fi
        if whiptail --title "Delete Log Files?" --yesno "Do you want to delete log files (if any) for the selected applications?" 8 78; then
            play_key_sound
            delete_log_files=true
        else
            play_key_sound
        fi
    fi

    local tasks=()
    if [ "$delete_app_files" = true ]; then tasks+=("AppFiles"); fi
    if [ "$delete_config_files" = true ]; then tasks+=("ConfigFiles"); fi
    if [ "$delete_cache_files" = true ]; then tasks+=("CacheFiles"); fi
    if [ "$delete_log_files" = true ]; then tasks+=("LogFiles"); fi
    if [ "$delete_saved_state" = true ]; then tasks+=("SavedState"); fi

    if [ ${#tasks[@]} -eq 0 ]; then
        return
    fi

    local total=${#apps[@]}
    local count=0
    local percentage=0
    local pipe pid

    pipe=$(mktemp -u)
    mkfifo "$pipe"

    (whiptail --gauge "Deleting associated files..." 6 60 0 < "$pipe") &
    pid=$!

    exec 3> "$pipe"
    {
        for app in "${apps[@]}"; do
            local app_clean
            app_clean=$(echo "$app" | tr -d '"')
            count=$((count + 1))
            percentage=$(( (count * 100) / total ))
            echo -e "$percentage\n# Deleting associated files for $app_clean" >&3
            echo "Processing associated files for: $app_clean" >> "$LOG_FILE"
            if [ "$OS_TYPE" = "Darwin" ]; then
                if [ "$delete_app_files" = true ]; then
                    echo "Deleting Application Support for $app_clean" >> "$LOG_FILE"
                    echo "$sudo_password" | sudo -S rm -rf "/Library/Application Support/$app_clean" >> "$LOG_FILE" 2>&1
                    rm -rf "$HOME/Library/Application Support/$app_clean" >> "$LOG_FILE" 2>&1
                fi
                if [ "$delete_config_files" = true ]; then
                    echo "Deleting Preferences for $app_clean" >> "$LOG_FILE"
                    echo "$sudo_password" | sudo -S find "/Library/Preferences" -name "*$app_clean*" -exec rm -f {} \; >> "$LOG_FILE" 2>&1
                    find "$HOME/Library/Preferences" -name "*$app_clean*" -exec rm -f {} \; >> "$LOG_FILE" 2>&1
                fi
                if [ "$delete_cache_files" = true ]; then
                    echo "Deleting Caches for $app_clean" >> "$LOG_FILE"
                    echo "$sudo_password" | sudo -S rm -rf "/Library/Caches/$app_clean" >> "$LOG_FILE" 2>&1
                    echo "$sudo_password" | sudo -S rm -rf "/Library/Caches/com.$app_clean.*" >> "$LOG_FILE" 2>&1
                    rm -rf "$HOME/Library/Caches/$app_clean" >> "$LOG_FILE" 2>&1
                    rm -rf "$HOME/Library/Caches/com.$app_clean.*" >> "$LOG_FILE" 2>&1
                fi
                if [ "$delete_log_files" = true ]; then
                    echo "Deleting Logs for $app_clean" >> "$LOG_FILE"
                    echo "$sudo_password" | sudo -S rm -rf "/Library/Logs/$app_clean" >> "$LOG_FILE" 2>&1
                    rm -rf "$HOME/Library/Logs/$app_clean" >> "$LOG_FILE" 2>&1
                fi
                if [ "$delete_saved_state" = true ]; then
                    echo "Deleting Saved Application State for $app_clean" >> "$LOG_FILE"
                    echo "$sudo_password" | sudo -S rm -rf "/Library/Saved Application State/com.$app_clean.*" >> "$LOG_FILE" 2>&1
                    rm -rf "$HOME/Library/Saved Application State/com.$app_clean.*" >> "$LOG_FILE" 2>&1
                fi
            elif [ "$OS_TYPE" = "Linux" ]; then
                if [ "$delete_app_files" = true ]; then
                    echo "Deleting application data for $app_clean in $XDG_DATA" >> "$LOG_FILE"
                    rm -rf "$XDG_DATA/$app_clean" >> "$LOG_FILE" 2>&1
                fi
                if [ "$delete_config_files" = true ]; then
                    echo "Deleting configuration files for $app_clean in $XDG_CONFIG" >> "$LOG_FILE"
                    rm -rf "$XDG_CONFIG/$app_clean" >> "$LOG_FILE" 2>&1
                fi
                if [ "$delete_cache_files" = true ]; then
                    echo "Deleting cache files for $app_clean in $XDG_CACHE" >> "$LOG_FILE"
                    rm -rf "$XDG_CACHE/$app_clean" >> "$LOG_FILE" 2>&1
                fi
                if [ "$delete_log_files" = true ]; then
                    echo "Deleting log files for $app_clean (if any) in $XDG_CACHE or similar" >> "$LOG_FILE"
                    rm -rf "$XDG_CACHE/$app_clean-logs" >> "$LOG_FILE" 2>&1
                    rm -rf "$HOME/.local/share/$app_clean-logs" >> "$LOG_FILE" 2>&1
                fi
            fi
        done
        exec 3>&-
    } > /dev/null 2>&1

    rm "$pipe"
    wait $pid
    sleep 0.5
}

interactive_app_selection() {
    local items=("$@")
    local options=()
    local item app_name app_size

    for item in "${items[@]}"; do
        app_name=$(echo "$item" | cut -d':' -f1)
        app_size=$(echo "$item" | cut -d':' -f2)
        if [ -z "$app_size" ]; then
            app_size="?"
        fi
        options+=("$app_name" "$app_size" "OFF")
    done

    if [ ${#options[@]} -eq 0 ]; then
        whiptail --title "No Applications Found" --msgbox "No applications were found to display." 8 60
        echo "No applications found for selection." >> "$LOG_FILE"
        exit 0
    fi

    while true; do
        selected_apps=$(whiptail --title "Select apps to delete" --checklist \
            "Select the apps to delete:\n\nSPACE: Select/Deselect\nTAB: Switch to <Ok> or <Cancel>" 20 78 10 "${options[@]}" 3>&1 1>&2 2>&3)
        exitstatus=$?
        play_key_sound
        if [ $exitstatus = 0 ]; then
            if [[ -z "$selected_apps" ]]; then
                break
            else
                confirm_deletion "$selected_apps"
            fi
            break
        elif [ $exitstatus = 1 ]; then
            break
        else
            break
        fi
    done
}

combine_results() {
    local items=()
    for file in brew_formula_sizes.txt brew_cask_sizes.txt applications_sizes.txt home_applications_sizes.txt sudo_find_results.txt; do
        if [ -f "$file" ]; then
            while IFS= read -r line; do
                items+=("$line")
            done < "$file"
        fi
    done

    typeset -A name_to_size
    typeset -A name_to_display

    for entry in "${items[@]}"; do
        local raw_name=$(echo "$entry" | cut -d':' -f1)
        local raw_size=$(echo "$entry" | cut -d':' -f2)

        local unified_name=$(echo "$raw_name" | sed 's/\.app$//i' | sed 's/\.desktop$//i' | tr '[:upper:]' '[:lower:]')

        if [[ "$raw_size" == "?" ]]; then
            raw_size=0
        fi

        if [[ -z "${name_to_size[$unified_name]}" ]]; then
            name_to_size[$unified_name]="$raw_size"
            name_to_display[$unified_name]="$raw_name"
        else
            local existing_size="${name_to_size[$unified_name]}"
            if (( raw_size > existing_size )); then
                name_to_size[$unified_name]="$raw_size"
                name_to_display[$unified_name]="$raw_name"
            fi
        fi
    done

    local deduped_items=()
    for unified in "${(@k)name_to_size}"; do
        deduped_items+=("${name_to_display[$unified]}:${name_to_size[$unified]}")
    done

    sorted_items=("${(f)$(format_and_sort_results "${deduped_items[@]}")}")

    {
      echo "===== Combined & Deduplicated Results ====="
      for item in "${sorted_items[@]}"; do
          local app_name=$(echo "$item" | cut -d':' -f1)
          local app_size=$(echo "$item" | cut -d':' -f2)
          echo "$app_name size: $app_size" >> "$LOG_FILE"
      done
    } >> "$LOG_FILE"
}

show_about() {
    whiptail --title "About this application" --msgbox "This script was created by Narek Mosisian.
It helps you manage and delete Mac and Linux applications easily.

For more information, visit: https://github.com/NarekMosisian/mac-storage-manager

© 2024 Narek Mosisian. All rights reserved." 15 70
    play_key_sound
}

check_homebrew() {
    if ! command -v brew &> /dev/null; then
        whiptail --title "Error" --msgbox "Homebrew is not installed. Please install Homebrew and try again." 8 60
        echo "Critical error: Homebrew is not installed." >> "$LOG_FILE"
        exit 1
    fi
}

cleanup() {
    rm -f brew_formula_sizes.txt brew_cask_sizes.txt applications_sizes.txt home_applications_sizes.txt sudo_find_results.txt
}
trap cleanup EXIT

check_homebrew
handle_sudo_find
combine_results
interactive_app_selection "${sorted_items[@]}"

show_about

sudo_password=""
echo "===========================================" >> "$LOG_FILE"
echo "Script ended at $(date)" >> "$LOG_FILE"