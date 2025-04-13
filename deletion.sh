#!/usr/bin/env bash
# deletion.sh

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
# ------------------------------------------------------------------------------------------------------

display_error() {
    local message="$1"
    whiptail --title "$(get_text critical_error)" \
    --msgbox "$message" 8 60 \
    --ok-button "$(get_ok_button)" \
    --cancel-button "$(get_cancel_button)"
}

delete_application() {
    local app_name="$1"
    local app_path=""
    log_message "$(printf "$(get_text attempting_to_delete)" "$app_name")"

    local normalized_name
    normalized_name=$(echo "$app_name" | sed 's/\.app$//I; s/\.desktop$//I' | tr '[:upper:]' '[:lower:]')

    if [ "$app_name" = "Docker.app" ] || [ "$app_name" = "Docker.desktop" ]; then
        if command -v brew &>/dev/null && brew list --cask | grep -qi "^docker\$"; then
            log_message "$(printf "$(get_text homebrew_cask_uninstalling)" "$app_name")"
            if brew uninstall --cask docker >> "$LOG_FILE" 2>&1; then
                log_message "$(get_text docker_uninstall_success_homebrew)"
            else
                log_message "$(get_text docker_uninstall_failed_homebrew)"
                display_error "$(get_text docker_uninstall_failed_homebrew)"
                whiptail --title "$(get_text log_file_status_title)" --msgbox "$(get_text log_file_updated_message)" 8 60 \
                    --ok-button "$(get_ok_button)" --cancel-button "$(get_cancel_button)"
                interactive_app_selection "${sorted_items[@]}"
                return
            fi
        else
            log_message "$(get_text docker_not_installed_brew_manual)"
            if [ "$OS_TYPE" = "Darwin" ]; then
                app_path="/Applications/Docker.app"
            else
                app_path=""
            fi
            if [ -n "$app_path" ] && [ -d "$app_path" ]; then
                log_message "$(printf "$(get_text found_docker_at)" "$app_path")"
                echo "$SUDO_PASSWORD" | sudo -k -S rm -rf -- "$app_path" >> "$LOG_FILE" 2>&1
                if [ $? -eq 0 ]; then
                    log_message "$(printf "$(get_text successfully_deleted_path)" "$app_path")"
                else
                    log_message "$(printf "$(get_text failed_to_delete_path)" "$app_path")"
                    display_error "$(printf "$(get_text failed_to_delete_path)" "$app_path")"
                    whiptail --title "$(get_text log_file_status_title)" --msgbox "$(get_text log_file_updated_message)" 8 60 \
                        --ok-button "$(get_ok_button)" --cancel-button "$(get_cancel_button)"
                    interactive_app_selection "${sorted_items[@]}"
                    return
                fi
            else
                log_message "$(get_text docker_app_not_found_standard)"
                display_error "$(get_text docker_app_not_found_standard)"
            fi
        fi
        return
    fi

    if command -v brew &>/dev/null && brew list --cask | grep -qi "^$normalized_name\$"; then
        log_message "$(printf "$(get_text homebrew_cask_uninstalling)" "$app_name")"
        if brew uninstall --cask "$normalized_name" >> "$LOG_FILE" 2>&1; then
            log_message "$(printf "$(get_text homebrew_cask_uninstall_success)" "$normalized_name")"
        else
            log_message "$(printf "$(get_text homebrew_cask_uninstall_failure)" "$normalized_name")"
            display_error "$(printf "$(get_text homebrew_cask_uninstall_failure)" "$app_name")"
            whiptail --title "$(get_text log_file_status_title)" --msgbox "$(get_text log_file_updated_message)" 8 60 \
                --ok-button "$(get_ok_button)" --cancel-button "$(get_cancel_button)"
            interactive_app_selection "${sorted_items[@]}"
            return
        fi
        return
    fi

    if command -v brew &>/dev/null && brew list --formula | grep -qi "^$normalized_name\$"; then
        log_message "$(printf "$(get_text homebrew_formula_uninstalling)" "$app_name")"
        if brew uninstall --formula "$normalized_name" >> "$LOG_FILE" 2>&1; then
            log_message "$(printf "$(get_text homebrew_formula_uninstall_success)" "$normalized_name")"
            brew cleanup "$normalized_name" >> "$LOG_FILE" 2>&1
        else
            log_message "$(printf "$(get_text homebrew_formula_uninstall_failure)" "$normalized_name")"
            display_error "$(printf "$(get_text homebrew_formula_uninstall_failure)" "$app_name")"
            whiptail --title "$(get_text log_file_status_title)" --msgbox "$(get_text log_file_updated_message)" 8 60 \
                --ok-button "$(get_ok_button)" --cancel-button "$(get_cancel_button)"
            interactive_app_selection "${sorted_items[@]}"
            return
        fi
        return
    fi

    if [ "$OS_TYPE" = "Darwin" ]; then
        app_path=$(find /Applications "$HOME/Applications" -maxdepth 1 -iname "$app_name" 2>/dev/null | head -n 1)
    elif [ "$OS_TYPE" = "Linux" ]; then
        app_path=$(find /usr/share/applications "$HOME/.local/share/applications" -maxdepth 1 -iname "$app_name" 2>/dev/null | head -n 1)
    fi

    if [ -z "$app_path" ]; then
        log_message "$(printf "$(get_text app_not_found_standard)" "$app_name")"
        app_path=$(echo "$SUDO_PASSWORD" | sudo -k -S find / -iname "$app_name" -type d -maxdepth 3 2>/dev/null | head -n 1)
    fi

    if [ -n "$app_path" ]; then
        log_message "$(printf "$(get_text found_docker_at)" "$app_path")"
        echo "$SUDO_PASSWORD" | sudo -k -S rm -rf -- "$app_path" >> "$LOG_FILE" 2>&1
        if [ $? -eq 0 ]; then
            log_message "$(printf "$(get_text successfully_deleted_path)" "$app_path")"
        else
            log_message "$(printf "$(get_text failed_to_delete_path)" "$app_path")"
            display_error "$(printf "$(get_text failed_to_delete_path)" "$app_path")"
            whiptail --title "$(get_text log_file_status_title)" --msgbox "$(get_text log_file_updated_message)" 8 60 \
                --ok-button "$(get_ok_button)" --cancel-button "$(get_cancel_button)"
            interactive_app_selection "${sorted_items[@]}"
            return
        fi
    else
        log_message "$(printf "$(get_text app_not_found_on_system)" "$app_name")"
        whiptail --title "$(get_text log_file_status_title)" --msgbox "$(get_text log_file_updated_message)" 8 60 \
            --ok-button "$(get_ok_button)" --cancel-button "$(get_cancel_button)"
        display_error "$(printf "$(get_text app_not_found_on_system)" "$app_name")"
    fi
}

confirm_deletion() {
    local selected_apps="$1"
    log_message "Selected apps: $selected_apps"
    eval "apps_to_delete=($selected_apps)"
    if [ ${#apps_to_delete[@]} -eq 0 ]; then
        whiptail --title "$(get_text error)" --msgbox "$(get_text no_applications_found_for_selection)" 8 60 \
            --ok-button "$(get_ok_button)" --cancel-button "$(get_cancel_button)"
        exit 0
    fi
    local deletion_message
    deletion_message="$(get_text are_you_sure_permanently_delete)"
    for app in "${apps_to_delete[@]}"; do
        deletion_message+="$app\n"
    done
    deletion_message+="$(get_text this_action_cannot_be_undone)"
    if whiptail --title "$(get_text confirm_deletion)" \
        --yesno "$deletion_message" 15 60 \
        --yes-button "$(get_yes_button)" \
        --no-button "$(get_no_button)"; then
            play_key_sound
            log_message "Confirmed deletion"
            ensure_sudo_valid
            if [ $? -ne 0 ]; then
                whiptail --title "$(get_text error)" --msgbox "$(get_text critical_error_sudo_failed_deletion)" 8 60 \
                    --ok-button "$(get_ok_button)" --cancel-button "$(get_cancel_button)"
                log_message "Critical error: Sudo authentication failed during deletion."
                whiptail --title "$(get_text log_file_status_title)" --msgbox "$(get_text log_file_updated_message)" 8 60 \
                    --ok-button "$(get_ok_button)" --cancel-button "$(get_cancel_button)"
                return
            fi
            for app in "${apps_to_delete[@]}"; do
                play_key_sound
                delete_application "$app"
                if [ $? -ne 0 ]; then
                    log_message "Deletion failed for $app."
                    interactive_app_selection "$(echo "$app" | sed 's/ /_/g')"
                    return
                fi
                sleep 1
            done
            whiptail --title "$(get_text log_file_status_title)" --msgbox "$(get_text log_file_updated_message)" 8 60 \
                --ok-button "$(get_ok_button)" --cancel-button "$(get_cancel_button)"
            SUDO_PASSWORD=""
            main_menu
    else
        play_key_sound
        whiptail --title "$(get_text confirm_deletion)" --msgbox "$(get_text no_applications_were_deleted)" 8 60 \
            --ok-button "$(get_ok_button)" --cancel-button "$(get_cancel_button)"
        log_message "User canceled deletion"
    fi
    main_menu
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
        whiptail --title "$(get_text error)" --msgbox "$(get_text critical_error_sudo_failed_associated)" 8 60 \
            --ok-button "$(get_ok_button)" --cancel-button "$(get_cancel_button)"
        log_message "$(get_text critical_error_sudo_failed_associated)"
        return
    fi

    if [ "$OS_TYPE" = "Darwin" ]; then
        if whiptail --title "$(get_text delete_application_support_title)" \
            --yesno "$(get_text delete_application_support_title)" 8 78 \
            --ok-button "$(get_ok_button)" --cancel-button "$(get_cancel_button)"; then
                play_key_sound
                delete_app_files=true
        fi
        if whiptail --title "$(get_text delete_preferences_title)" \
            --yesno "$(get_text delete_preferences_title)" 8 78 \
            --ok-button "$(get_ok_button)" --cancel-button "$(get_cancel_button)"; then
                play_key_sound
                delete_config_files=true
        fi
        if whiptail --title "$(get_text delete_caches_title)" \
            --yesno "$(get_text delete_caches_title)" 8 78 \
            --ok-button "$(get_ok_button)" --cancel-button "$(get_cancel_button)"; then
                play_key_sound
                delete_cache_files=true
        fi
        if whiptail --title "$(get_text delete_logs_title)" \
            --yesno "$(get_text delete_logs_title)" 8 78 \
            --ok-button "$(get_ok_button)" --cancel-button "$(get_cancel_button)"; then
                play_key_sound
                delete_log_files=true
        fi
        if whiptail --title "$(get_text delete_saved_state_title)" \
            --yesno "$(get_text delete_saved_state_title)" 8 78 \
            --ok-button "$(get_ok_button)" --cancel-button "$(get_cancel_button)"; then
                play_key_sound
                delete_saved_state=true
        fi
    elif [ "$OS_TYPE" = "Linux" ]; then
        if whiptail --title "$(get_text delete_application_data_title)" \
            --yesno "$(get_text delete_application_data_title)" 8 78 \
            --ok-button "$(get_ok_button)" --cancel-button "$(get_cancel_button)"; then
                play_key_sound
                delete_app_files=true
        fi
        if whiptail --title "$(get_text delete_configuration_title)" \
            --yesno "$(get_text delete_configuration_title)" 8 78 \
            --ok-button "$(get_ok_button)" --cancel-button "$(get_cancel_button)"; then
                play_key_sound
                delete_config_files=true
        fi
        if whiptail --title "$(get_text delete_cache_files_title)" \
            --yesno "$(get_text delete_cache_files_title)" 8 78 \
            --ok-button "$(get_ok_button)" --cancel-button "$(get_cancel_button)"; then
                play_key_sound
                delete_cache_files=true
        fi
        if whiptail --title "$(get_text delete_log_files_title)" \
            --yesno "$(get_text delete_log_files_title)" 8 78 \
            --ok-button "$(get_ok_button)" --cancel-button "$(get_cancel_button)"; then
                play_key_sound
                delete_log_files=true
        fi
    fi

    for app in "${apps[@]}"; do
        local app_clean
        app_clean=$(echo "$app" | tr -d '"')
        log_message "$(printf "$(get_text deleting_associated_files_for)" "$app_clean")"
        if [ "$OS_TYPE" = "Darwin" ]; then
            if [ "$delete_app_files" = true ]; then
                sudo rm -rf "/Library/Application Support/$app_clean" >> "$LOG_FILE" 2>&1
                rm -rf "$HOME/Library/Application Support/$app_clean" >> "$LOG_FILE" 2>&1
            fi
            if [ "$delete_config_files" = true ]; then
                sudo find "/Library/Preferences" -name "*$app_clean*" -exec rm -f {} \; >> "$LOG_FILE" 2>&1
                find "$HOME/Library/Preferences" -name "*$app_clean*" -exec rm -f {} \; >> "$LOG_FILE" 2>&1
            fi
            if [ "$delete_cache_files" = true ]; then
                sudo rm -rf "/Library/Caches/$app_clean" >> "$LOG_FILE" 2>&1
                sudo rm -rf "/Library/Caches/com.$app_clean.*" >> "$LOG_FILE" 2>&1
                rm -rf "$HOME/Library/Caches/$app_clean" >> "$LOG_FILE" 2>&1
                rm -rf "$HOME/Library/Caches/com.$app_clean.*" >> "$LOG_FILE" 2>&1
            fi
            if [ "$delete_log_files" = true ]; then
                sudo rm -rf "/Library/Logs/$app_clean" >> "$LOG_FILE" 2>&1
                rm -rf "$HOME/Library/Logs/$app_clean" >> "$LOG_FILE" 2>&1
            fi
            if [ "$delete_saved_state" = true ]; then
                sudo rm -rf "/Library/Saved Application State/com.$app_clean.*" >> "$LOG_FILE" 2>&1
                rm -rf "$HOME/Library/Saved Application State/com.$app_clean.*" >> "$LOG_FILE" 2>&1
            fi
        elif [ "$OS_TYPE" = "Linux" ]; then
            if [ "$delete_app_files" = true ]; then
                rm -rf "$XDG_DATA/$app_clean" >> "$LOG_FILE" 2>&1
            fi
            if [ "$delete_config_files" = true ]; then
                rm -rf "$XDG_CONFIG/$app_clean" >> "$LOG_FILE" 2>&1
            fi
            if [ "$delete_cache_files" = true ]; then
                rm -rf "$XDG_CACHE/$app_clean" >> "$LOG_FILE" 2>&1
            fi
            if [ "$delete_log_files" = true ]; then
                rm -rf "$XDG_CACHE/$app_clean-logs" >> "$LOG_FILE" 2>&1
                rm -rf "$HOME/.local/share/$app_clean-logs" >> "$LOG_FILE" 2>&1
            fi
        fi
    done
}
