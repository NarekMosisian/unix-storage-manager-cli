#!/bin/zsh

# Define output file paths
SOUND_PATH="./sounds"
LOG_FILE="application_size_checker.log"

# Function to play sound for any key press event
play_key_sound() {
    if [ -f "$SOUND_PATH/switch.wav" ]; then
        afplay "$SOUND_PATH/switch.wav" &
    else
        echo "Sound file not found: $SOUND_PATH/switch.wav" >> "$LOG_FILE"
    fi
}

# Function to request sudo privileges only when required
request_sudo_password() {
    if [ -z "$sudo_password" ]; then  # Only request password if not already entered
        sudo_password=$(whiptail --passwordbox "Please enter your sudo password:" 8 60 3>&1 1>&2 2>&3)
        play_key_sound  # Play sound after entering the password
        if [ $? -ne 0 ]; then
            sudo_password=""
        fi
    fi
}

# Function to ensure sudo permissions are valid before execution
ensure_sudo_valid() {
    if sudo -n true 2>/dev/null; then
        return 0  # Sudo is already available without password
    else
        request_sudo_password
        if [ -n "$sudo_password" ]; then
            echo "$sudo_password" | sudo -S -v 2>/dev/null  # Validate the password
            if [ $? -ne 0 ]; then
                echo "Invalid sudo password" >> "$LOG_FILE"
                return 1
            fi
        else
            echo "Sudo password not entered" >> "$LOG_FILE"
            return 1
        fi
    fi
}

# Function to format file sizes to the appropriate unit (MB, GB, KB, B)
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

# Function to calculate and format application size in kilobytes
calculate_size() {
    local app_path="$1"
    local size_in_kb
    size_in_kb=$(du -sk "$app_path" 2>/dev/null | cut -f1)
    if [ -n "$size_in_kb" ]; then
        echo "$size_in_kb"
    else
        echo "?"  # Return ? if size is not available
    fi
}

# Function to calculate Brew formula size using 'du' and handle symlinks
calculate_brew_formula_size() {
    local formula_path
    formula_path=$(brew --cellar "$1" 2>/dev/null)
    if [ -d "$formula_path" ]; then
        calculate_size "$formula_path"
    else
        echo "?"
    fi
}

# Function to calculate Brew cask size
calculate_brew_cask_size() {
    local cask_name="$1"
    local brew_prefix
    local caskroom_path
    local size

    # Determine the Homebrew prefix
    brew_prefix=$(brew --prefix)

    # Define the path to the Caskroom directory
    caskroom_path="$brew_prefix/Caskroom/$cask_name"

    if [ -d "$caskroom_path" ]; then
        # Calculate the total size of the Cask installation directory
        size=$(du -sk "$caskroom_path" 2>/dev/null | cut -f1)
        if [ -n "$size" ] && [ "$size" -gt 0 ]; then
            echo "$size"
            echo "Cask '$cask_name' size: $size KB" >> "$LOG_FILE"
        else
            echo "?"  # Return ? if size is not available
            echo "Size could not be determined for Cask: $cask_name." >> "$LOG_FILE"
        fi
    else
        echo "?"  # Return ? if Caskroom path does not exist
        echo "Caskroom path does not exist for Cask: $cask_name." >> "$LOG_FILE"
    fi
}

# Function to update progress bar
update_progress() {
    local pipe="$1"
    local percent="$2"
    local message="$3"
    echo "$percent" > "$pipe"
    echo "# $message"  # Send message to stdout
    sleep 0.5  # Adjust the delay to smooth progress bar updates
}

# Function to gather application sizes and display progress bar
gather_application_sizes() {
    local include_sudo_find="$1"
    local pipe pid

    # Create a named pipe to send progress updates
    pipe=$(mktemp -u)
    mkfifo "$pipe"

    # Show the progress bar in the background
    (whiptail --gauge "Gathering application sizes..." 6 60 0 < "$pipe") &
    pid=$!

    exec 3> "$pipe"

    # Start gathering information with progress updates
    {
        update_progress "$pipe" 0 "Starting the process..."

        # Step 1: Homebrew formulas
        update_progress "$pipe" 10 "Calculating Homebrew formula sizes..."
        brew list --formula | while read -r formula; do
            size=$(calculate_brew_formula_size "$formula")
            echo "$formula:$size"
        done > brew_formula_sizes.txt

        # Step 2: Homebrew casks
        update_progress "$pipe" 20 "Calculating Homebrew cask sizes..."
        brew list --cask | while read -r cask; do
            size=$(calculate_brew_cask_size "$cask")
            echo "$cask:$size"
        done > brew_cask_sizes.txt

        # Step 3: Applications in /Applications
        update_progress "$pipe" 30 "Calculating sizes in /Applications folder..."
        find /Applications -maxdepth 1 -name "*.app" -print0 | while IFS= read -r -d '' app; do
            size=$(calculate_size "$app")
            echo "$(basename "$app"):$size"
        done > applications_sizes.txt

        # Step 4: Applications in ~/Applications
        update_progress "$pipe" 40 "Calculating sizes in ~/Applications folder..."
        find "$HOME/Applications" -maxdepth 1 -name "*.app" -print0 2>/dev/null | while IFS= read -r -d '' app; do
            size=$(calculate_size "$app")
            echo "$(basename "$app"):$size"
        done > home_applications_sizes.txt

        # Optional Task: sudo find
        if [ "$include_sudo_find" = true ]; then
            update_progress "$pipe" 85 "Running 'sudo find'..."
            ensure_sudo_valid  # Ensure sudo is available
            if [ $? -eq 0 ]; then
                sudo find / -iname "*.app" -type d -print0 2>/dev/null | while IFS= read -r -d '' app; do
                    size=$(calculate_size "$app")
                    # Extract application name without path
                    app_basename=$(basename "$app")
                    echo "$app_basename:$size"
                done > sudo_find_results.txt
            else
                echo "User canceled the sudo password prompt." >> "$LOG_FILE"
            fi
        fi

        update_progress "$pipe" 100 "Process completed."

        # Close the pipe and remove it
        exec 3>&-
    } > /dev/null 2>&1

    rm "$pipe"  # Remove the pipe after completion

    # Wait for the progress bar to finish displaying before showing the list
    wait $pid
    sleep 0.5  # Small delay to ensure the progress bar is fully closed
}

# Function to handle sudo find based on user's choice
handle_sudo_find() {
    local include_sudo_find=false

    # Ask user whether to include 'sudo find'
    if whiptail --title "Include sudo find?" --yesno "Do you want to include application search via 'sudo find'? This process may take several hours." 8 78; then
        play_key_sound  # Play sound after 'Yes'
        include_sudo_find=true
    else
        play_key_sound  # Play sound after 'No'
    fi

    # Gather application sizes with progress bar
    gather_application_sizes "$include_sudo_find"
}

# Function to format and sort results by size
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

    # Sort by the raw kilobyte values (third field) in descending order
    printf "%s\n" "${formatted_items[@]}" | sort -t':' -k3nr
}

# Function to handle deletion confirmations and execute deletions
confirm_deletion() {
    local selected_apps="$1"
    local apps_to_delete=()
    local app clean_app

    echo "Selected apps: $selected_apps" >> "$LOG_FILE"  # Log selected apps for debugging

    # Convert selected_apps from whiptail format to array
    for app in $selected_apps; do
        clean_app=$(echo "$app" | tr -d '"')
        echo "Adding $clean_app to apps_to_delete" >> "$LOG_FILE"  # Debugging log
        apps_to_delete+=("$clean_app")
    done

    # Verify apps_to_delete is filled
    if [ ${#apps_to_delete[@]} -eq 0 ]; then
        whiptail --title "Error" --msgbox "No applications were selected for deletion. Please try again." 8 60
        echo "No apps to delete, exiting." >> "$LOG_FILE"
        return
    fi

    # Prepare deletion confirmation message
    local deletion_message="Are you sure you want to permanently delete the following applications?\n\n"
    for app in "${apps_to_delete[@]}"; do
        deletion_message+="$app\n"
    done
    deletion_message+="\nThis action cannot be undone."

    # Ask for final confirmation
    if whiptail --title "Confirm deletion" --yesno "$deletion_message" 15 60; then
        play_key_sound  # Play sound after confirmation
        echo "Confirmed deletion" >> "$LOG_FILE"

        # Show a progress gauge for deletion
        (
            local total=${#apps_to_delete[@]}
            local count=0
            local percentage
            for app in "${apps_to_delete[@]}"; do
                count=$((count + 1))
                percentage=$(( (count * 100) / total ))
                echo "$percentage"
                echo "# Deleting $app"
                # Perform deletion
                delete_application "$app"
                echo "$percentage"
                echo "# $app deleted."
            done
        ) | whiptail --title "Deleting applications..." --gauge "Deleting applications..." 20 60 0

        # Ask if the user wants to delete associated files
        ask_to_delete_associated_files "${apps_to_delete[@]}"

        # Inform the user that deletion is complete
        whiptail --title "Deletion completed" --msgbox "The selected applications and associated files have been successfully deleted." 8 60
    else
        play_key_sound  # Play sound if user cancels deletion
        whiptail --title "Deletion canceled" --msgbox "No applications were deleted." 8 60
        echo "User canceled deletion" >> "$LOG_FILE"
    fi
}

# Function to delete an application and its associated files
delete_application() {
    local app_name="$1"
    local app_path

    echo "Attempting to delete: $app_name" >> "$LOG_FILE"

    # Docker specific handling
    if [ "$app_name" = "Docker.app" ]; then
        # Check if Docker is installed via Homebrew
        if brew list --cask | grep -q "^docker\$"; then
            echo "Docker is installed via Homebrew. Uninstalling..." >> "$LOG_FILE"
            # Uninstall Docker via Homebrew
            if brew uninstall --cask docker >> "$LOG_FILE" 2>&1; then
                echo "Docker successfully uninstalled via Homebrew." >> "$LOG_FILE"
            else
                echo "Failed to uninstall Docker via Homebrew." >> "$LOG_FILE"
            fi
        else
            # Inform user Docker is not installed via Homebrew
            echo "Docker is not installed via Homebrew. Attempting manual deletion." >> "$LOG_FILE"

            # Attempt to delete Docker.app from /Applications
            app_path="/Applications/Docker.app"
            if [ -d "$app_path" ]; then
                echo "Found Docker at $app_path. Deleting..." >> "$LOG_FILE"
                ensure_sudo_valid
                if [ $? -eq 0 ]; then
                    sudo rm -rf -- "$app_path" >> "$LOG_FILE" 2>&1
                    if [ $? -eq 0 ]; then
                        echo "Successfully deleted $app_path." >> "$LOG_FILE"
                    else
                        echo "Failed to delete $app_path." >> "$LOG_FILE"
                    fi
                else
                    echo "Sudo not available. Cannot delete $app_path." >> "$LOG_FILE"
                fi
            else
                echo "Docker.app not found in /Applications." >> "$LOG_FILE"
            fi
        fi
        return
    fi

    # Check if the app is installed as a brew cask
    if brew list --cask | grep -q "^$app_name\$"; then
        echo "$app_name is installed as a Homebrew cask. Uninstalling..." >> "$LOG_FILE"
        # Uninstall the cask (without sudo)
        if brew uninstall --cask "$app_name" >> "$LOG_FILE" 2>&1; then
            echo "Successfully uninstalled cask $app_name." >> "$LOG_FILE"
            brew cleanup "$app_name" >> "$LOG_FILE" 2>&1
        else
            echo "Failed to uninstall cask $app_name." >> "$LOG_FILE"
        fi
        return
    fi

    # Check if the app is installed as a brew formula
    if brew list --formula | grep -q "^$app_name\$"; then
        echo "$app_name is installed as a Homebrew formula. Uninstalling..." >> "$LOG_FILE"
        # Uninstall the formula (with --ignore-dependencies if needed)
        if ! brew uninstall --formula "$app_name" >> "$LOG_FILE" 2>&1; then
            echo "$app_name could not be uninstalled because of dependencies. Attempting to force uninstall with --ignore-dependencies." >> "$LOG_FILE"
            brew uninstall --formula --ignore-dependencies "$app_name" >> "$LOG_FILE" 2>&1
        else
            echo "Successfully uninstalled formula $app_name." >> "$LOG_FILE"
            brew cleanup "$app_name" >> "$LOG_FILE" 2>&1
        fi
        return
    fi

    # Else, treat as application installed in standard locations or found via sudo find
    # Attempt to find the app path
    app_path=$(find /Applications "$HOME/Applications" -maxdepth 1 -name "$app_name" 2>/dev/null | head -n 1)

    if [ -z "$app_path" ]; then
        echo "$app_name not found in standard locations. Attempting to find via sudo find..." >> "$LOG_FILE"
        # Try to find the app via sudo find with limited depth to prevent long searches
        app_path=$(sudo find / -iname "$app_name" -type d -maxdepth 5 2>/dev/null | head -n 1)
    fi

    if [ -n "$app_path" ]; then
        echo "Found $app_name at $app_path. Deleting..." >> "$LOG_FILE"
        ensure_sudo_valid
        if [ $? -eq 0 ]; then
            sudo rm -rf -- "$app_path" >> "$LOG_FILE" 2>&1
            if [ $? -eq 0 ]; then
                echo "Successfully deleted $app_path." >> "$LOG_FILE"
            else
                echo "Failed to delete $app_path." >> "$LOG_FILE"
            fi
        else
            echo "Sudo not available. Cannot delete $app_path." >> "$LOG_FILE"
        fi
    else
        echo "$app_name could not be found on the system." >> "$LOG_FILE"
    fi
}

# Function to prompt for deletion of associated files and execute deletions
ask_to_delete_associated_files() {
    local apps=("$@")
    local delete_app_support=false
    local delete_preferences=false
    local delete_caches=false
    local delete_logs=false
    local delete_saved_state=false

    # Prompt for each category
    if whiptail --title "Delete Application Support?" --yesno "Do you want to delete the Application Support files for the selected applications?" 8 78; then
        play_key_sound
        delete_app_support=true
    else
        play_key_sound
    fi

    if whiptail --title "Delete Preferences?" --yesno "Do you want to delete the Preferences files for the selected applications?" 8 78; then
        play_key_sound
        delete_preferences=true
    else
        play_key_sound
    fi

    if whiptail --title "Delete Caches?" --yesno "Do you want to delete the Caches for the selected applications?" 8 78; then
        play_key_sound
        delete_caches=true
    else
        play_key_sound
    fi

    if whiptail --title "Delete Logs?" --yesno "Do you want to delete the Logs for the selected applications?" 8 78; then
        play_key_sound
        delete_logs=true
    else
        play_key_sound
    fi

    if whiptail --title "Delete Saved Application State?" --yesno "Do you want to delete the Saved Application State for the selected applications?" 8 78; then
        play_key_sound
        delete_saved_state=true
    else
        play_key_sound
    fi

    # Perform deletions based on user choices
    for app in "${apps[@]}"; do
        app_clean=$(echo "$app" | tr -d '"')
        echo "Processing associated files for: $app_clean" >> "$LOG_FILE"

        # Delete Application Support
        if [ "$delete_app_support" = true ]; then
            echo "Deleting Application Support for $app_clean" >> "$LOG_FILE"
            sudo rm -rf "/Library/Application Support/$app_clean" >> "$LOG_FILE" 2>&1
            sudo rm -rf "$HOME/Library/Application Support/$app_clean" >> "$LOG_FILE" 2>&1
        fi

        # Delete Preferences
        if [ "$delete_preferences" = true ]; then
            echo "Deleting Preferences for $app_clean" >> "$LOG_FILE"
            sudo rm -f "/Library/Preferences/com.$app_clean.*" >> "$LOG_FILE" 2>&1
            sudo rm -f "$HOME/Library/Preferences/com.$app_clean.*" >> "$LOG_FILE" 2>&1
        fi

        # Delete Caches
        if [ "$delete_caches" = true ]; then
            echo "Deleting Caches for $app_clean" >> "$LOG_FILE"
            sudo rm -rf "/Library/Caches/$app_clean" >> "$LOG_FILE" 2>&1
            sudo rm -f "/Library/Caches/com.$app_clean.*" >> "$LOG_FILE" 2>&1
            sudo rm -rf "$HOME/Library/Caches/$app_clean" >> "$LOG_FILE" 2>&1
            sudo rm -f "$HOME/Library/Caches/com.$app_clean.*" >> "$LOG_FILE" 2>&1
        fi

        # Delete Logs
        if [ "$delete_logs" = true ]; then
            echo "Deleting Logs for $app_clean" >> "$LOG_FILE"
            sudo rm -rf "/Library/Logs/$app_clean" >> "$LOG_FILE" 2>&1
            sudo rm -rf "$HOME/Library/Logs/$app_clean" >> "$LOG_FILE" 2>&1
        fi

        # Delete Saved Application State
        if [ "$delete_saved_state" = true ]; then
            echo "Deleting Saved Application State for $app_clean" >> "$LOG_FILE"
            sudo rm -rf "/Library/Saved Application State/com.$app_clean.*" >> "$LOG_FILE" 2>&1
            sudo rm -rf "$HOME/Library/Saved Application State/com.$app_clean.*" >> "$LOG_FILE" 2>&1
        fi
    done
}

# Function for interactive selection using whiptail/dialog with real-time feedback
interactive_app_selection() {
    local items=("$@")
    local options=()
    local item app_name app_size

    for item in "${items[@]}"; do
        app_name=$(echo "$item" | cut -d':' -f1)
        app_size=$(echo "$item" | cut -d':' -f2)
        if [ -z "$app_size" ]; then
            app_size="?"  # Assign ? if the size is missing
        fi
        options+=("$app_name" "$app_size" "OFF")
    done

    # Check if options are empty
    if [ ${#options[@]} -eq 0 ]; then
        whiptail --title "No Applications Found" --msgbox "No applications were found to display." 8 60
        exit 0
    fi

    # Infinite loop to allow re-selection if needed
    while true; do
        selected_apps=$(whiptail --title "Select apps to delete" --checklist \
            "Select the apps to delete:\n\nSPACE: Select/Deselect\nTAB: Switch to <Ok> or <Cancel>" 20 78 10 "${options[@]}" 3>&1 1>&2 2>&3)

        exitstatus=$?
        play_key_sound  # Play sound after pressing any key (SPACE, OK, or Cancel)

        if [ $exitstatus = 0 ]; then
            # Check if no applications were selected
            if [[ -z "$selected_apps" ]]; then
                show_about  # Show About dialog if no apps were selected
            else
                confirm_deletion "$selected_apps"  # Proceed with deletion if apps were selected
            fi
            break
        elif [ $exitstatus = 1 ]; then
            show_about  # Show About dialog when Cancel is pressed
            break  # Exit loop after canceling
        else
            show_about  # Show About dialog for any unexpected input
            break
        fi
    done
}

# Function to combine and format the results after all searches are complete
combine_results() {
    local items=()

    # Add the results from brew_formula_sizes.txt, brew_cask_sizes.txt, applications_sizes.txt, home_applications_sizes.txt, sudo_find_results.txt
    for file in brew_formula_sizes.txt brew_cask_sizes.txt applications_sizes.txt home_applications_sizes.txt sudo_find_results.txt; do
        if [ -f "$file" ]; then
            while read -r line; do
                items+=("$line")
            done < "$file"
        fi
    done

    # Format and sort the results by size in descending order
    sorted_items=("${(f)$(format_and_sort_results "${items[@]}")}")
}

# Show "About" dialog
show_about() {
    whiptail --title "About this application" --msgbox "This script was created by Narek Mosisian.
It helps you manage and delete Mac applications easily.

For more information, visit: https://github.com/NarekMosisian/mac-storage-manager

© 2024 Narek Mosisian. All rights reserved." 15 70
    play_key_sound  # Play sound after pressing OK in About dialog
}

# Function to check if Homebrew is installed
check_homebrew() {
    if ! command -v brew &> /dev/null; then
        whiptail --title "Error" --msgbox "Homebrew is not installed. Please install Homebrew and try again." 8 60
        exit 1
    fi
}

# Function to initialize log file
initialize_log() {
    if [ ! -f "$LOG_FILE" ]; then
        touch "$LOG_FILE"
    fi
}

# Function to clean up temporary files
cleanup() {
    rm -f brew_formula_sizes.txt brew_cask_sizes.txt applications_sizes.txt home_applications_sizes.txt sudo_find_results.txt
}
trap cleanup EXIT

# Main program execution
initialize_log
check_homebrew
handle_sudo_find
combine_results
interactive_app_selection "${sorted_items[@]}"
