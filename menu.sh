#!/usr/bin/env bash
# menu.sh

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

calculate_actual_size() {
    local app_name="$1"
    local app_path=""
    if [ "$OS_TYPE" = "Darwin" ]; then
        app_path=$(find /Applications "$HOME/Applications" -maxdepth 1 -iname "${app_name}" 2>/dev/null | head -n 1)
    elif [ "$OS_TYPE" = "Linux" ]; then
        app_path=$(find /usr/share/applications "$HOME/.local/share/applications" -maxdepth 1 -iname "${app_name}" 2>/dev/null | head -n 1)
    fi
    if [ -n "$app_path" ]; then
        local size
        size=$(calculate_size "$app_path")
        echo "$size"
    else
        echo 0
    fi
}

format_and_sort_results() {
    local items=("$@")
    local formatted_items=()
    local item app_name app_size_kb formatted_size recalculated_size

    for item in "${items[@]}"; do
        app_name=$(echo "$item" | cut -d':' -f1)
        app_size_kb=$(echo "$item" | cut -d':' -f2)
        if [[ -z "$app_size_kb" ]] || ! [[ "$app_size_kb" =~ ^[0-9]+$ ]]; then
            app_size_kb=0
        fi

        formatted_size=$(format_size "$app_size_kb")
        if ! [[ "$formatted_size" =~ (B|K|M|G)$ ]]; then
            recalculated_size=$(calculate_actual_size "$app_name")
            if [[ "$recalculated_size" =~ ^[0-9]+$ ]] && [ "$recalculated_size" -gt 0 ]; then
                app_size_kb="$recalculated_size"
                formatted_size=$(format_size "$app_size_kb")
            fi
        fi
        formatted_items+=( "$app_name:$formatted_size:$app_size_kb" )
    done

    printf "%s\n" "${formatted_items[@]}" | sort -t':' -k3nr
}

combine_results() {
    local items=()
    local file
    for file in brew_formula_sizes.txt brew_cask_sizes.txt applications_sizes.txt home_applications_sizes.txt sudo_find_results.txt; do
        if [ -f "$file" ]; then
            while IFS= read -r line; do
                items+=( "$line" )
            done < "$file"
        fi
    done

    declare -A name_to_size
    declare -A name_to_display
    local raw_name raw_size numeric_size unified_name

    for entry in "${items[@]}"; do
        raw_name=$(echo "$entry" | cut -d':' -f1)
        raw_size=$(echo "$entry" | cut -d':' -f2)
        numeric_size=$(parse_size "$raw_size")
        if ! [[ "$numeric_size" =~ ^[0-9]+$ ]]; then
            numeric_size=0
        fi
        unified_name=$(echo "$raw_name" | sed 's/\.app$//I; s/\.desktop$//I' | tr '[:upper:]' '[:lower:]')
        if [[ -z "${name_to_size[$unified_name]}" ]]; then
            name_to_size[$unified_name]="$numeric_size"
            name_to_display[$unified_name]="$raw_name"
        else
            local existing_size="${name_to_size[$unified_name]}"
            if (( numeric_size > existing_size )); then
                name_to_size[$unified_name]="$numeric_size"
                name_to_display[$unified_name]="$raw_name"
            fi
        fi
    done

    local deduped_items=()
    for unified in "${!name_to_size[@]}"; do
        deduped_items+=( "${name_to_display[$unified]}:${name_to_size[$unified]}" )
    done

    sorted_items=( $(format_and_sort_results "${deduped_items[@]}") )
    {
      echo "===== Combined & Deduplicated Results ====="
      for item in "${sorted_items[@]}"; do
          local app_name formatted_size
          app_name=$(echo "$item" | cut -d':' -f1)
          formatted_size=$(echo "$item" | cut -d':' -f2)
          if ! [[ "$formatted_size" =~ (B|K|M|G)$ ]]; then
              formatted_size="0B"
          fi
          echo "$app_name size: $formatted_size"
      done
    } >> "$LOG_FILE"
}

interactive_app_selection() {
    local preselect="$1" 
    local options=()
    local item app_name app_size display_name
    for item in "${sorted_items[@]}"; do
        app_name=$(echo "$item" | cut -d':' -f1)
        app_size=$(echo "$item" | cut -d':' -f2)
        if ! [[ "$app_size" =~ ^[0-9]+(\.[0-9]+)?[BKMGT]?$ ]]; then
            continue
        fi
        display_name="$(echo "$app_name" | sed 's/ /_/g')"
        if [ "$display_name" = "$preselect" ]; then
            options+=("$display_name" "$app_size" "ON")
        else
            options+=("$display_name" "$app_size" "OFF")
        fi
    done
    if [ ${#options[@]} -eq 0 ]; then
        whiptail --title "$(get_text no_applications_found)" --msgbox "$(get_text no_applications_found_for_selection)" 8 60 \
            --ok-button "$(get_ok_button)" --cancel-button "$(get_cancel_button)"
        exit 0
    fi
    while true; do
        selected_apps=$(whiptail --title "$(get_text select_apps_to_delete)" --checklist "$(get_text select_the_apps_to_delete)" 20 78 10 \
            --ok-button "$(get_ok_button)" --cancel-button "$(get_cancel_button)" "${options[@]}" \
            3>&1 1>&2 2>&3)
        if [ $? -eq 0 ]; then
            if [[ -z "$selected_apps" ]]; then
                break
            else
                confirm_deletion "$selected_apps"
            fi
            break
        else
            break
        fi
    done
}

main_menu() {
    local CHOICE
    CHOICE=$(whiptail --title "$(get_text main_menu_title)" \
        --menu "$(get_text main_menu_prompt)" 15 60 2 \
        --default-item "* " \
        --ok-button "$(get_ok_button)" \
        --cancel-button "$(get_text exit_button)" \
        "°" "$(get_text menu_option_start)" \
        "°°" "$(get_text menu_option_language)" \
        3>&1 1>&2 2>&3)
    local RETVAL=$?
    play_key_sound

    if [ "$RETVAL" -ne 0 ]; then
        whiptail --title "$(get_text about_title)" \
                 --msgbox "$(get_text about_message)" 15 70 \
                 --ok-button "$(get_ok_button)" \
                 --cancel-button "$(get_cancel_button)"
        play_key_sound
        exit 0
    fi

    case "$CHOICE" in
        "°")
            start_collection
            ;;
        "°°")
            select_language
            ;;
        *)
            exit 0
            ;;
    esac
}
