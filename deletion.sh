#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

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

display_error() {
    local message="$1"
    whiptail --title "$(get_text critical_error)" \
             --msgbox "$message" 8 60 \
             --ok-button "$(get_ok_button)" \
             --cancel-button "$(get_cancel_button)"
}

delete_via_package_manager() {
    local pkg="$1"

    # Debian/Ubuntu
    if command -v dpkg &>/dev/null; then
        if dpkg -l | grep -qi -F -- "$pkg"; then
            if whiptail --title "$(get_text warning)" \
                        --yesno "$(printf "$(get_text pkgmgr_remove_confirm)" "$pkg")" 10 60 \
                        --yes-button "$(get_text yes)" \
                        --no-button "$(get_text no)"; then
                ensure_sudo_valid
                sudo apt-get remove --purge -y -- "$pkg"
                return $?
            fi
        fi
    fi

    # Fedora/RHEL/CentOS (dnf or yum)
    if command -v rpm &>/dev/null; then
        if rpm -q --quiet "$pkg"; then
            if whiptail --title "$(get_text warning)" \
                        --yesno "$(printf "$(get_text pkgmgr_remove_confirm)" "$pkg")" 10 60 \
                        --yes-button "$(get_text yes)" \
                        --no-button "$(get_text no)"; then
                ensure_sudo_valid
                if command -v dnf &>/dev/null; then
                    sudo dnf remove -y -- "$pkg"
                else
                    sudo yum remove -y -- "$pkg"
                fi
                return $?
            fi
        fi
    fi

    # Arch Linux (pacman)
    if command -v pacman &>/dev/null; then
        if pacman -Qi "$pkg" &>/dev/null; then
            if whiptail --title "$(get_text warning)" \
                        --yesno "$(printf "$(get_text pkgmgr_remove_confirm)" "$pkg")" 10 60 \
                        --yes-button "$(get_text yes)" \
                        --no-button "$(get_text no)"; then
                ensure_sudo_valid
                sudo pacman -Rs --noconfirm "$pkg"
                return $?
            fi
        fi
    fi

    return 1
}

delete_application() {
    local app_name_raw="$1"
    local app_name="${app_name_raw//_/ }"
    app_name="${app_name#\"}"
    app_name="${app_name%\"}"
    local app_path=""

    log_message "$(printf "$(get_text attempting_to_delete)" "$app_name")"

    # Block deletion of critical system apps
    local CRITICAL_APPS
    if [ "$OS_TYPE" = "Darwin" ]; then
        CRITICAL_APPS=("Finder.app" "Safari.app" "System Preferences.app" "Terminal.app" "Dock.app")
    else
        CRITICAL_APPS=("gnome-terminal.desktop" "org.gnome.Nautilus.desktop")
    fi
    for crit in "${CRITICAL_APPS[@]}"; do
        if [ "$app_name" = "$crit" ]; then
            display_error "$(printf "$(get_text critical_app_blocked)" "$app_name")"
            log_message "Deletion of critical application $app_name blocked."
            return 1
        fi
    done

    local normalized_name
    normalized_name=$(echo "$app_name" | sed 's/\.app$//I; s/\.desktop$//I' | tr '[:upper:]' '[:lower:]')

    if delete_via_package_manager "$normalized_name"; then
        log_message "Removed $normalized_name via package manager."
        log_message "Deleted application $app_name at $(date)"
        return 0
    fi

    if [ "$app_name" = "Docker.app" ] || [ "$app_name" = "Docker.desktop" ]; then
        if command -v brew &>/dev/null && brew list --cask | grep -qi -F -- "^docker\$"; then
            log_message "$(printf "$(get_text homebrew_cask_uninstalling)" "$app_name")"
            ensure_sudo_valid
            if brew uninstall --cask docker >> "$LOG_FILE" 2>&1; then
                log_message "$(get_text docker_uninstall_success_homebrew)"
                log_message "Deleted application $app_name at $(date)"
            else
                log_message "$(get_text docker_uninstall_failed_homebrew)"
                display_error "$(get_text docker_uninstall_failed_homebrew)"
                interactive_app_selection "${sorted_items[@]}"
                return 1
            fi
        fi
        for dir in "${APP_DIRS[@]}"; do
            if [ -d "$dir/Docker.app" ]; then
                app_path="$dir/Docker.app"
                break
            fi
        done
        if [ -n "$app_path" ]; then
            ensure_sudo_valid
            sudo rm -rf -- "$app_path" >> "$LOG_FILE" 2>&1
            if [ $? -eq 0 ]; then
                log_message "$(printf "$(get_text successfully_deleted_path)" "$app_path")"
                log_message "Deleted application $app_name at $(date)"
            else
                log_message "$(printf "$(get_text failed_to_delete_path)" "$app_path")"
                display_error "$(printf "$(get_text failed_to_delete_path)" "$app_path")"
                return 1
            fi
            return 0
        fi
    fi

    if command -v brew &>/dev/null && brew list --cask | grep -qi -F -- "^$normalized_name\$"; then
        log_message "$(printf "$(get_text homebrew_cask_uninstalling)" "$app_name")"
        ensure_sudo_valid
        if brew uninstall --cask "$normalized_name" >> "$LOG_FILE" 2>&1; then
            log_message "$(printf "$(get_text homebrew_cask_uninstall_success)" "$normalized_name")"
            log_message "Deleted application $app_name at $(date)"
        else
            log_message "$(printf "$(get_text homebrew_cask_uninstall_failure)" "$normalized_name")"
            display_error "$(printf "$(get_text homebrew_cask_uninstall_failure)" "$app_name")"
            interactive_app_selection "${sorted_items[@]}"
            return 1
        fi
        return 0
    fi

    if command -v brew &>/dev/null && brew list --formula --versions | awk '{print $1}' | grep -xq "$normalized_name"; then
        log_message "$(printf "$(get_text homebrew_formula_uninstalling)" "$app_name")"
        ensure_sudo_valid

        if brew uninstall --formula "$normalized_name" >>"$LOG_FILE" 2>&1; then
            brew cleanup "$normalized_name" >> "$LOG_FILE" 2>&1
            log_message "$(printf "$(get_text homebrew_formula_uninstall_success)" "$normalized_name")"
            log_message "Deleted application $app_name at $(date)"
            return 0
        fi

        log_message "Normal uninstall failed, retrying with --ignore-dependencies"
        if brew uninstall --formula --ignore-dependencies "$normalized_name" >>"$LOG_FILE" 2>&1; then
            brew cleanup "$normalized_name" >> "$LOG_FILE" 2>&1
            log_message "$(printf "$(get_text homebrew_formula_uninstall_success_ignore_deps)" "$normalized_name")"
            log_message "Deleted application $app_name at $(date)"
            return 0
        else
            log_message "$(printf "$(get_text homebrew_formula_uninstall_failure)" "$normalized_name")"
            display_error "$(printf "$(get_text homebrew_formula_uninstall_failure)" "$app_name")"
            return 1
        fi
    fi

    local find_type
    if [[ "$app_name" == *.desktop ]]; then
        find_type="f"
    else
        find_type="d"
    fi
    for dir in "${APP_DIRS[@]}"; do
        candidate=$(find "$dir" -maxdepth 1 -iname "$app_name" -type "$find_type" 2>/dev/null | head -n1)
        if [ -z "$candidate" ] && [[ "$app_name" != *.* ]]; then
            candidate=$(find "$dir" -maxdepth 1 -iname "*${app_name}*.${extension}" -type "$find_type" 2>/dev/null | head -n1)
        fi
        if [ -n "$candidate" ]; then
            app_path="$candidate"
            break
        fi
    done

    if [ -z "$app_path" ]; then
        display_error "$(printf "$(get_text app_not_found_on_system)" "$app_name")"
        log_message "Deletion failed: $app_name not found."
        return 1
    fi

    ensure_sudo_valid
    sudo rm -rf -- "$app_path" >> "$LOG_FILE" 2>&1
    if [ $? -eq 0 ]; then
        log_message "$(printf "$(get_text successfully_deleted_path)" "$app_path")"
        log_message "Deleted application $app_name at $(date)"
        return 0
    else
        log_message "$(printf "$(get_text failed_to_delete_path)" "$app_path")"
        display_error "$(printf "$(get_text failed_to_delete_path)" "$app_path")"
        return 1
    fi
}

confirm_deletion() {
    local selected_apps="$1"
    log_message "Selected apps: $selected_apps"

    read -r -a apps_to_delete <<< "$selected_apps"
    if [ ${#apps_to_delete[@]} -eq 0 ]; then
        whiptail --title "$(get_text error)" \
                 --msgbox "$(get_text no_applications_found_for_selection)" 8 60 \
                 --ok-button "$(get_ok_button)" \
                 --cancel-button "$(get_cancel_button)"
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

        for app in "${apps_to_delete[@]}"; do
            delete_application "$app" || { log_message "Deletion failed for $app."; return; }
            sleep 1
        done

        ask_to_delete_associated_files "${apps_to_delete[@]}"

        whiptail --title "$(get_text selected_apps_processed)" \
                 --msgbox "$(get_text selected_apps_processed)" 8 60 \
                 --ok-button "$(get_ok_button)"

        whiptail --title "$(get_text log_file_status_title)" \
                 --msgbox "$(get_text log_file_updated_message)" 8 60 \
                 --ok-button "$(get_ok_button)" \
                 --cancel-button "$(get_cancel_button)"
    else
        play_key_sound
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

    ensure_sudo_valid || return

    if [ "$OS_TYPE" = "Darwin" ]; then
        if whiptail --title "$(get_text short_delete_app_support_title)" \
                    --yesno "$(get_text delete_application_support_title)" 8 78 \
                    --ok-button "$(get_ok_button)" \
                    --no-button "$(get_cancel_button)"; then
            play_key_sound
            delete_app_files=true
        fi
        if whiptail --title "$(get_text short_delete_preferences_title)" \
                    --yesno "$(get_text delete_preferences_title)" 8 78 \
                    --ok-button "$(get_ok_button)" \
                    --no-button "$(get_cancel_button)"; then
            play_key_sound
            delete_config_files=true
        fi
        if whiptail --title "$(get_text short_delete_caches_title)" \
                    --yesno "$(get_text delete_caches_title)" 8 78 \
                    --ok-button "$(get_ok_button)" \
                    --no-button "$(get_cancel_button)"; then
            play_key_sound
            delete_cache_files=true
        fi
        if whiptail --title "$(get_text short_delete_logs_title)" \
                    --yesno "$(get_text delete_logs_title)" 8 78 \
                    --ok-button "$(get_ok_button)" \
                    --no-button "$(get_cancel_button)"; then
            play_key_sound
            delete_log_files=true
        fi
        if whiptail --title "$(get_text short_delete_saved_state_title)" \
                    --yesno "$(get_text delete_saved_state_title)" 8 78 \
                    --ok-button "$(get_ok_button)" \
                    --no-button "$(get_cancel_button)"; then
            play_key_sound
            delete_saved_state=true
        fi
    else
        if whiptail --title "$(get_text short_delete_app_data_title)" \
                    --yesno "$(get_text delete_application_data_title)" 8 78 \
                    --ok-button "$(get_ok_button)" \
                    --no-button "$(get_cancel_button)"; then
            play_key_sound
            delete_app_files=true
        fi
        if whiptail --title "$(get_text short_delete_configuration_title)" \
                    --yesno "$(get_text delete_configuration_title)" 8 78 \
                    --ok-button "$(get_ok_button)" \
                    --no-button "$(get_cancel_button)"; then
            play_key_sound
            delete_config_files=true
        fi
        if whiptail --title "$(get_text short_delete_cache_files_title)" \
                    --yesno "$(get_text delete_cache_files_title)" 8 78 \
                    --ok-button "$(get_ok_button)" \
                    --no-button "$(get_cancel_button)"; then
            play_key_sound
            delete_cache_files=true
        fi
        if whiptail --title "$(get_text short_delete_log_files_title)" \
                    --yesno "$(get_text delete_log_files_title)" 8 78 \
                    --ok-button "$(get_ok_button)" \
                    --no-button "$(get_cancel_button)"; then
            play_key_sound
            delete_log_files=true
        fi
    fi

    for app in "${apps[@]}"; do
        local app_clean="${app//\"/}"
        log_message "$(printf "$(get_text deleting_associated_files_for)" "$app_clean")"
        if [ "$OS_TYPE" = "Darwin" ]; then
            [ "$delete_app_files" = true ] && (sudo rm -rf "/Library/Application Support/$app_clean" >> "$LOG_FILE" 2>&1; \
                                              rm -rf "$HOME/Library/Application Support/$app_clean" >> "$LOG_FILE" 2>&1)
            [ "$delete_config_files" = true ] && (sudo find "/Library/Preferences" -name "*$app_clean*" -exec rm -f {} \; >> "$LOG_FILE" 2>&1; \
                                                  find "$HOME/Library/Preferences" -name "*$app_clean*" -exec rm -f {} \; >> "$LOG_FILE" 2>&1)
            [ "$delete_cache_files" = true ] && (sudo rm -rf "/Library/Caches/$app_clean" >> "$LOG_FILE" 2>&1; \
                                                 sudo rm -rf "/Library/Caches/com.$app_clean.*" >> "$LOG_FILE" 2>&1; \
                                                 rm -rf "$HOME/Library/Caches/$app_clean" >> "$LOG_FILE" 2>&1; \
                                                 rm -rf "$HOME/Library/Caches/com.$app_clean.*" >> "$LOG_FILE" 2>&1)
            [ "$delete_log_files" = true ] && (sudo rm -rf "/Library/Logs/$app_clean" >> "$LOG_FILE" 2>&1; \
                                                rm -rf "$HOME/Library/Logs/$app_clean" >> "$LOG_FILE" 2>&1)
            [ "$delete_saved_state" = true ] && (sudo rm -rf "/Library/Saved Application State/com.$app_clean.*" >> "$LOG_FILE" 2>&1; \
                                                  rm -rf "$HOME/Library/Saved Application State/com.$app_clean.*" >> "$LOG_FILE" 2>&1)
        else
            [ "$delete_app_files" = true ] && rm -rf "$XDG_DATA/$app_clean" >> "$LOG_FILE" 2>&1
            [ "$delete_config_files" = true ] && rm -rf "$XDG_CONFIG/$app_clean" >> "$LOG_FILE" 2>&1
            [ "$delete_cache_files" = true ] && rm -rf "$XDG_CACHE/$app_clean" >> "$LOG_FILE" 2>&1
            [ "$delete_log_files" = true ] && (rm -rf "$XDG_CACHE/$app_clean-logs" >> "$LOG_FILE" 2>&1; \
                                              rm -rf "$HOME/.local/share/$app_clean-logs" >> "$LOG_FILE" 2>&1)
        fi
    done
}