#!/usr/bin/env bash
# size_calculations.sh

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

parse_size() {
    local raw="$1"
    if [[ -z "$raw" ]]; then
        echo 0
        return
    fi
    raw="$(echo "$raw" | tr '[:upper:]' '[:lower:]')"
    if [[ "$raw" =~ ^[0-9]+$ ]]; then
        echo "$raw"
        return
    fi
    if [[ "$raw" =~ ^([0-9]*\.?[0-9]+)([gmkb]+)$ ]]; then
        local num="${BASH_REMATCH[1]}"
        local unit="${BASH_REMATCH[2]}"
        case "$unit" in
            g)
                awk "BEGIN {printf \"%d\", $num * 1048576}"
                return
                ;;
            m)
                awk "BEGIN {printf \"%d\", $num * 1024}"
                return
                ;;
            k)
                awk "BEGIN {printf \"%d\", $num}"
                return
                ;;
            b)
                awk "BEGIN {printf \"%d\", $num / 1024}"
                return
                ;;
        esac
    fi
    echo 0
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

calculate_actual_size() {
    local app_name="$1"
    local app_path=""
    if [ "$OS_TYPE" = "Darwin" ]; then
        app_path=$(find /Applications "$HOME/Applications" -maxdepth 1 -iname "${app_name}" 2>/dev/null | head -n 1)
    elif [ "$OS_TYPE" = "Linux" ]; then
        app_path=$(find /usr/share/applications "$HOME/.local/share/applications" -maxdepth 1 -iname "${app_name}" 2>/dev/null | head -n 1)
    fi
    if [ -n "$app_path" ]; then
        calculate_size "$app_path"
    else
        echo 0
    fi
}

calculate_size() {
    local app_path="$1"
    local size_in_kb
    size_in_kb=$(du -sk "$app_path" 2>/dev/null | cut -f1)
    if [ -n "$size_in_kb" ]; then
        echo "$size_in_kb"
    else
        echo 0
    fi
}

calculate_brew_formula_size() {
    if command -v brew &>/dev/null; then
        local formula_path
        formula_path=$(brew --cellar "$1" 2>/dev/null)
        if [ -d "$formula_path" ]; then
            calculate_size "$formula_path"
        else
            echo 0
        fi
    else
        echo 0
    fi
}

calculate_brew_cask_size() {
    if command -v brew &>/dev/null; then
        local cask_name="$1"
        local brew_prefix
        local caskroom_path
        brew_prefix=$(brew --prefix)
        caskroom_path="$brew_prefix/Caskroom/$cask_name"
        if [ -d "$caskroom_path" ]; then
            local size
            size=$(du -sk "$caskroom_path" 2>/dev/null | cut -f1)
            if [ -n "$size" ] && [ "$size" -gt 0 ]; then
                echo "$size"
            else
                echo 0
            fi
        else
            echo 0
        fi
    else
        echo 0
    fi
}