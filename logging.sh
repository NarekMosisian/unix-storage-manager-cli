#!/usr/bin/env bash
# logging.sh

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

log_message() {
    echo "$1" >> "$LOG_FILE"
}

log_start() {
    log_message "Script started at $(date)"
}

log_end() {
    log_message "Script ended at $(date)"
}

update_progress() {
    local percent="$1"
    local message="$2"
    echo -e "$percent\n# $message" >&3
    sleep 0.5
}

reconstruct_log_entries() {
    local infile="$LOG_FILE"
    local outfile="fixed_${LOG_FILE}"

    if [ "$OS_TYPE" = "Darwin" ]; then
        if command -v gawk >/dev/null 2>&1; then
            gawk '
            BEGIN { prev = "" }
            {
                if (match($0, /^(.*)[[:space:]]+size:[[:space:]]+(.*)$/, arr)) {
                    name = arr[1]
                    size = arr[2]
                    if (size == "0B") {
                        if (prev == "")
                            prev = name
                        else
                            prev = prev " " name
                        next
                    } else {
                        if (prev != "" && name ~ /\.app$/) {
                            print prev " " name " size: " size
                            prev = ""
                        } else {
                            if (prev != "") {
                                print prev " size: 0B"
                                prev = ""
                            }
                            print $0
                        }
                    }
                } else {
                    if (prev != "") {
                        print prev " size: 0B"
                        prev = ""
                    }
                    print $0
                }
            }
            END {
                if (prev != "")
                    print prev " size: 0B"
            }
            ' "$infile" > "$outfile"
        else
            awk '
            BEGIN { prev = "" }
            {
                if (match($0, /^(.*)[[:blank:]]+size:[[:blank:]]+(.*)$/, arr)) {
                    name = arr[1]
                    size = arr[2]
                    if (size == "0B") {
                        if (prev == "")
                            prev = name
                        else
                            prev = prev " " name
                        next
                    } else {
                        if (prev != "" && name ~ /\.app$/) {
                            print prev " " name " size: " size
                            prev = ""
                        } else {
                            if (prev != "") {
                                print prev " size: 0B"
                                prev = ""
                            }
                            print $0
                        }
                    }
                } else {
                    if (prev != "") {
                        print prev " size: 0B"
                        prev = ""
                    }
                    print $0
                }
            }
            END {
                if (prev != "")
                    print prev " size: 0B"
            }
            ' "$infile" > "$outfile"
        fi
    elif [ "$OS_TYPE" = "Linux" ]; then
        awk '
        BEGIN { prev = "" }
        {
            if (match($0, /^(.*)[[:space:]]+size:[[:space:]]+(.*)$/, arr)) {
                name = arr[1]
                size = arr[2]
                if (size == "0B") {
                    if (prev == "")
                        prev = name
                    else
                        prev = prev " " name
                    next
                } else {
                    if (prev != "" && name ~ /\.app$/) {
                        print prev " " name " size: " size
                        prev = ""
                    } else {
                        if (prev != "") {
                            print prev " size: 0B"
                            prev = ""
                        }
                        print $0
                    }
                }
            } else {
                if (prev != "") {
                    print prev " size: 0B"
                    prev = ""
                }
                print $0
            }
        }
        END {
            if (prev != "")
                print prev " size: 0B"
        }
        ' "$infile" > "$outfile"
    fi

    mv "$outfile" "$infile"
}
