#!/bin/zsh

# Define output file paths
SOUND_PATH=./sounds

# Function to play sound for any key press event
play_key_sound() {
    afplay "$SOUND_PATH/switch.wav" &
}

# Function to gather application sizes and freeze the progress bar until the list is ready
gather_application_sizes() {
    # Create a named pipe to send progress updates
    pipe=$(mktemp -u)
    mkfifo "$pipe"
    
    # Show the progress bar in the background and keep it open
    (whiptail --gauge "Gathering Application Sizes..." 6 60 0 < "$pipe") &
    pid=$!

    exec 3> "$pipe"

    {
        echo 0 > "$pipe"
        sleep 0.5  # Small delay to start the gauge smoothly

        echo "# Calculating Homebrew Formulas sizes..." >&3
        brew list --formula >/dev/null 2>&1 | parallel -j4 '
            formula_path=$(brew --prefix {} 2>/dev/null)
            if [ -d "$formula_path" ]; then
                size=$(du -sh "$formula_path" 2>/dev/null | cut -f1)
            else
                size="?"
            fi
            echo "{}: $size"
        ' | sort -hr > brew_formula_sizes.txt
        echo 25 > "$pipe"
        sleep 0.5  # Sleep to show the gauge

        echo "# Calculating Homebrew Casks sizes..." >&3
        brew list --cask >/dev/null 2>&1 | parallel -j4 '
            app_path="/Applications/{}.app"
            if [ -d "$app_path" ]; then
                size=$(du -sh "$app_path" 2>/dev/null | cut -f1)
            else
                size="?"
            fi
            echo "{}: $size"
        ' | sort -hr > brew_cask_sizes.txt
        echo 50 > "$pipe"
        sleep 0.5  # Sleep to show the gauge

        echo "# Calculating Applications in /Applications folder..." >&3
        ls /Applications >/dev/null 2>&1 | grep ".app" | parallel -j4 '
            size=$(du -sh "/Applications/{}" 2>/dev/null | cut -f1)
            echo "{}: $size"
        ' | sort -hr > applications_sizes.txt
        echo 100 > "$pipe"
        sleep 1  # Keep the gauge on screen for a bit longer to make the transition smooth

        exec 3>&-  # Close the pipe
    } > /dev/null 2>&1

    rm "$pipe"  # Remove the pipe after completion

    # Wait for the progress bar to finish displaying before showing the list
    wait $pid
    sleep 0.5  # Add a small delay to ensure the gauge is fully closed
}

# Function to format and sort results
format_and_sort_results() {
    local items=("$@")
    formatted_items=()
    for item in "${items[@]}"; do
        formatted_item=$(echo "$item" | sed -e "s/'//g" -e 's/: */: /g')
        formatted_items+=("$formatted_item")
    done
    sorted_items=$(printf "%s\n" "${formatted_items[@]}" | sort -hk2 -r)
    echo "$sorted_items"
}

# Function for interactive selection using whiptail/dialog with real-time feedback
interactive_app_selection() {
    local items=("$@")
    local options=()

    for item in "${items[@]}"; do
        app_name=$(echo "$item" | cut -d':' -f1)
        app_size=$(echo "$item" | cut -d':' -f2)
        if [ -z "$app_size" ]; then
            app_size="?"  # Assign ? if the size is missing
        fi
        options+=("$app_name" "$app_size" "OFF")
    done
    
    # Infinite loop to play sound on every SPACE press and refresh whiptail
    while true; do
        selected_apps=$(whiptail --title "Select Apps for Deletion" --checklist \
            "Choose the apps to delete:\n\nSPACE: Select/Deselect\nTAB: Switch to <Ok>, <Cancel>, or <About>" 20 78 10 "${options[@]}" 3>&1 1>&2 2>&3)

        exitstatus=$?
        play_key_sound  # Play sound after pressing any key (including SPACE, OK, and Cancel)

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

# Function to confirm deletion of selected apps and ask whether to delete caches
confirm_deletion() {
    local apps=("$@")

    if [[ -z "$apps" ]]; then
        echo "No apps selected for deletion."
        return
    fi

    echo "You have selected the following apps for deletion:"
    for app in "${apps[@]}"; do
        app_clean=$(echo "$app" | sed 's/^"\(.*\)"$/\1/')  # Remove surrounding quotes if any
        echo " - $app_clean"
    done

    echo "Are you sure you want to delete these apps? (Y/N)"
    read confirmation
    if [[ "$confirmation" =~ ^[Yy]$ ]]; then
        for app in "${apps[@]}"; do
            app_clean=$(echo "$app" | sed 's/^"\(.*\)"$/\1/')  # Remove surrounding quotes if any
            if [[ -n "$app_clean" ]]; then  # Ensure app is not an empty string
                echo "*** Deleting $app_clean ***"
                # Deleting the app from /Applications
                sudo rm -rf "/Applications/$app_clean"

                echo "*** Deleted $app_clean ***"
            fi
        done
        
        # Ask if caches should also be deleted
        ask_to_delete_caches "$apps"

    else
        echo "Deletion canceled."
    fi
}

# Function to ask whether to delete caches
ask_to_delete_caches() {
    local apps=("$@")
    if whiptail --title "Delete Application Caches?" --yesno "Do you also want to delete the application caches?\nThis can free up additional space." 8 78; then
        play_key_sound  # Play sound after pressing "Yes"
        for app in "${apps[@]}"; do
            app_clean=$(echo "$app" | sed 's/^"\(.*\)"$/\1/')  # Remove surrounding quotes if any
            if [[ -n "$app_clean" ]]; then  # Ensure app is not an empty string
                echo "*** Deleting cache for $app_clean ***"
                # Delete the app caches (assuming it stores cache in /Library/Caches)
                sudo rm -rf "/Library/Caches/$app_clean"

                # If it's a Homebrew app, cleanup will remove its dependencies and cache
                if brew list --formula "$app_clean" >/dev/null 2>&1; then
                    brew cleanup "$app_clean"
                elif brew list --cask "$app_clean" >/dev/null 2>&1; then
                    brew cleanup "$app_clean"
                fi

                echo "*** Deleted cache for $app_clean ***"
            fi
        done
    else
        play_key_sound  # Play sound after pressing "No"
        echo "Cache deletion skipped."
    fi
}

# Show "About" dialog
show_about() {
    whiptail --title "About this Application" --msgbox "This script was created by Narek Mosisian.
It helps you manage and delete Mac applications easily.

For more information, visit: https://github.com/NarekMosisian/mac-storage-manager

(c) 2024 Narek Mosisian. All rights reserved." 15 70
    play_key_sound  # Play sound after pressing OK in About dialog
}

# GUI prompt to ask if user wants the two additional questions
if whiptail --title "Prompt Options" --yesno "Do you want to answer the sudo find and pkgutil questions?" 8 78; then
    play_key_sound  # Play sound after 'Yes' is selected

    # Ask user whether to include 'sudo find'
    if whiptail --title "Include sudo find?" --yesno "Do you want to include application search via 'sudo find'? This process can take several hours." 8 78; then
        play_key_sound  # Play sound after 'Yes' is selected
        echo "You chose to include the 'sudo find' step."
    else
        play_key_sound  # Play sound after 'No' is selected
    fi

    # Ask user whether to include pkgutil packages
    if whiptail --title "Include pkgutil?" --yesno "Do you want to include packages installed via pkgutil? This can take a significant amount of time depending on the number of packages installed." 8 78; then
        play_key_sound  # Play sound after 'Yes' is selected
        echo "You chose to include the 'pkgutil' step."
    else
        play_key_sound  # Play sound after 'No' is selected
    fi
else
    play_key_sound  # Play sound after 'No' is selected
fi

# Main program execution with loading bar until list is ready
gather_application_sizes

# Combine results into a single array
items=()
while read -r line; do
    items+=("$line")
done < brew_formula_sizes.txt
while read -r line; do
    items+=("$line")
done < brew_cask_sizes.txt
while read -r line; do
    items+=("$line")
done < applications_sizes.txt

# Format and sort results by size in descending order
sorted_items=("${(f)$(format_and_sort_results "${items[@]}")}")

# Start interactive app selection after sizes are gathered
interactive_app_selection "${sorted_items[@]}"
