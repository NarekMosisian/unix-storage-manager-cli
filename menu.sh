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
#  the original author's name, "Narek Mosisian", is clearly indicated in all copies and
#  derivative works, and that all derivative works are licensed under AGPL-3.0. This requirement
#  is mandated by the license.
# ------------------------------------------------------------------------------------------------------

calculate_actual_size() {
    local app_name="$1"
    for dir in "${APP_DIRS[@]}"; do
        local candidate
        candidate=$(find "$dir" -maxdepth 1 -iname "$app_name" -print -quit 2>/dev/null)
        if [ -n "$candidate" ]; then
            du -sk "$candidate" 2>/dev/null | cut -f1
            return
        fi
    done
    echo 0
}

format_and_sort_results() {
    local items=("$@") formatted=()
    for item in "${items[@]}"; do
        local name=${item%%:*} raw=${item#*:}
        [[ "$raw" =~ ^[0-9]+$ ]] || raw=0
        local pretty=$(format_size "$raw")
        if [[ ! "$pretty" =~ (B|K|M|G)$ ]]; then
            raw=$(calculate_actual_size "$name")
            pretty=$(format_size "$raw")
        fi
        formatted+=( "$name:$pretty:$raw" )
    done
    printf "%s\n" "${formatted[@]}" | sort -t: -k3nr
}

combine_results() {
    local all=() file
    for file in brew_formula_sizes.txt brew_cask_sizes.txt applications_sizes.txt home_applications_sizes.txt sudo_find_results.txt; do
        [[ -f $file ]] || continue
        while read -r line; do all+=( "$line" ); done <"$file"
    done
    declare -A best_size best_name
    for entry in "${all[@]}"; do
        local name=${entry%%:*} size=${entry#*:}
        local num=$(parse_size "$size")
        [[ "$num" =~ ^[0-9]+$ ]] || num=0
        local key=$(echo "$name" | sed 's/\.app$//I; s/\.desktop$//I' | tr '[:upper:]' '[:lower:]')
        if [[ -z ${best_size[$key]:-} || $num -gt ${best_size[$key]} ]]; then
            best_size[$key]=$num
            best_name[$key]=$name
        fi
    done
    local pairs=()
    for k in "${!best_size[@]}"; do
        pairs+=( "${best_name[$k]}:${best_size[$k]}" )
    done
    mapfile -t sorted_items < <(format_and_sort_results "${pairs[@]}")
    {
        echo "===== Combined & Deduplicated Results ====="
        for line in "${sorted_items[@]}"; do
            IFS=':' read -r app pretty _ <<<"$line"
            [[ $pretty =~ (B|K|M|G)$ ]] || pretty="0B"
            echo "$app size: $pretty"
        done
    } >>"$LOG_FILE"
}

interactive_app_selection() {
    local opts=() line app pretty
    for line in "${sorted_items[@]}"; do
        IFS=':' read -r app pretty _ <<<"$line"
        [[ $pretty =~ ^[0-9]+(\.[0-9]+)?[BKMGT]$ ]] || continue
        opts+=( "${app// /_}" "$pretty" OFF )
    done

    if [ ${#opts[@]} -eq 0 ]; then
        whiptail --title "$(get_text no_applications_found)" \
                 --msgbox "$(get_text no_applications_found_for_selection)" 8 60 \
                 --ok-button "$(get_ok_button)"
        main_menu; return
    fi

    local sel
    if ! sel=$(whiptail --title "$(get_text select_apps_to_delete)" \
                       --checklist "$(get_text select_the_apps_to_delete)" 20 78 10 \
                       --ok-button "$(get_ok_button)" \
                       --cancel-button "$(get_cancel_button)" \
                       "${opts[@]}" 3>&1 1>&2 2>&3); then
        main_menu; return
    fi

    [[ -z $sel ]] && { main_menu; return; }

    confirm_deletion "$sel"
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

show_delete_history() {
    local tmp
    tmp=$(mktemp)
    {
        echo "$(get_text delete_history_warning)"
        grep '^Deleted application ' "$LOG_FILE" | sort -r
    } >"$tmp"
    whiptail --title "$(get_text delete_history_title)" --scrolltext "$(cat "$tmp")" 20 80 \
             --ok-button "$(get_ok_button)"
    rm "$tmp"
    main_menu
}

main_menu() {
    local choice ret
    if choice=$(whiptail --title "$(get_text main_menu_title)" \
                         --menu "$(get_text main_menu_prompt)" 20 70 4 \
                         --ok-button "$(get_ok_button)" \
                         --cancel-button "$(get_text exit_button)" \
                         "°"    "$(get_text menu_option_start)" \
                         "°°"   "$(get_text menu_option_language)" \
                         "°°°"  "$(get_text menu_option_sound)" \
                         "°°°°" "$(get_text menu_option_delete_history)" 3>&1 1>&2 2>&3); then
        ret=0
    else
        ret=$?
    fi

    case $ret in
      0)
        case $choice in
          "°")  start_collection   ;;
          "°°") select_language    ;;
          "°°°") toggle_sound      ;;
          "°°°°") show_delete_history ;;
        esac
        ;;
      1|255)
        trap - EXIT; cleanup; log_end
        whiptail --title "$(get_text about_title)" \
                 --msgbox "$(get_text about_message)" 15 70 \
                 --ok-button "$(get_ok_button)"
        exit 0
        ;;
    esac
}