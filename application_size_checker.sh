#!/bin/zsh

# Define output file
OUTPUT=~/Desktop/application_size_sorted.txt
echo "Determining application sizes on your Mac" > $OUTPUT
echo "Created on: $(date)" >> $OUTPUT
echo "--------------------------------------------" >> $OUTPUT

# Function to add sections
add_section() {
    echo -e "\n$1" >> $OUTPUT
    echo "--------------------------------------------" >> $OUTPUT
    shift
    for line in "$@"; do
        echo "$line" >> $OUTPUT
    done
}

# 1. Homebrew Formulas
brew list --formula | parallel -j4 '
    formula_path=$(brew --prefix {})
    if [ -d "$formula_path" ]; then
        size=$(du -sh "$formula_path" 2>/dev/null | awk "{print \"{}: \"$1}")
    else
        size="{}: Path not found"
    fi
    echo "$size"
' | sort -hr > brew_formula_sizes.txt

brew_formula_sizes=$(cat brew_formula_sizes.txt)
add_section "Homebrew Formulas:" "${(@f)brew_formula_sizes}"

# 2. Homebrew Casks
brew list --cask | parallel -j4 '
    app_path="/Applications/{}.app"
    if [ -d "$app_path" ]; then
        size=$(du -sh "$app_path" 2>/dev/null | awk "{print \"{}: \"$1}")
    else
        # Alternative paths for Casks
        app_path="$(brew --prefix)/Caskroom/{}/latest/{}.app"
        if [ -d "$app_path" ]; then
            size=$(du -sh "$app_path" 2>/dev/null | awk "{print \"{}: \"$1}")
        else
            size="{}: Application not found"
        fi
    fi
    echo "$size"
' | sort -hr > brew_cask_sizes.txt

brew_cask_sizes=$(cat brew_cask_sizes.txt)
add_section "Homebrew Casks:" "${(@f)brew_cask_sizes}"

# 3. Applications in /Applications Folder
ls /Applications | grep ".app" | parallel -j4 '
    size=$(du -sh "/Applications/{}" 2>/dev/null | awk "{print \"{}: \"$1}")
    echo "$size"
' | sort -hr > applications_sizes.txt

applications_sizes=$(cat applications_sizes.txt)
add_section "Applications in /Applications Folder:" "${(@f)applications_sizes}"

# 4. Applications in ~/Applications Folder
if [ -d ~/Applications ]; then
    ls ~/Applications | grep ".app" | parallel -j4 '
        size=$(du -sh "~/Applications/{}" 2>/dev/null | awk "{print \"{}: \"$1}")
        echo "$size"
    ' | sort -hr > user_applications_sizes.txt
    user_applications_sizes=$(cat user_applications_sizes.txt)
else
    user_applications_sizes="No user-specific applications found."
fi

add_section "Applications in ~/Applications Folder:" "${(@f)user_applications_sizes}"

# 5. Applications Found via sudo find
# Warning: This step can take a long time
echo "Determining sizes of applications found via sudo find... (this may take some time)" >> $OUTPUT
found_apps_sizes=$(sudo find / -iname "*.app" -type d 2>/dev/null | parallel -j4 '
    app_name=$(basename "{}")
    size=$(du -sh "{}" 2>/dev/null | awk "{print \"${app_name}: \"$1}")
    echo "$size"
' | sort -hr)

add_section "Applications Found via sudo find:" "${(@f)found_apps_sizes}"

# 6. Packages Installed via pkgutil
pkgutil --pkgs | parallel -j4 '
    pkg_info=$(pkgutil --pkg-info "{}" 2>/dev/null)
    if [ $? -eq 0 ]; then
        install_location=$(echo "$pkg_info" | grep "volume:" | awk "{print \$2}")
        if [ -d "$install_location" ]; then
            size=$(du -sh "$install_location" 2>/dev/null | awk "{print \"{}: \"$1}")
        else
            size="{}: Installation location not found"
        fi
    else
        size="{}: Information not available"
    fi
    echo "$size"
' | sort -hr > pkgutil_pkgs_sizes.txt

pkgutil_pkgs_sizes=$(cat pkgutil_pkgs_sizes.txt)
add_section "Packages Installed via pkgutil:" "${(@f)pkgutil_pkgs_sizes}"

# 7. Applications Listed via system_profiler
system_profiler SPApplicationsDataType -json | jq -r '.SPApplicationsDataType[] | "\(.name): \(.size)"' | sort -hr > system_profiler_apps_sizes.txt
system_profiler_apps_sizes=$(cat system_profiler_apps_sizes.txt)
add_section "Applications Listed via system_profiler:" "${(@f)system_profiler_apps_sizes}"

# Completion message
echo "The sizes of the applications have been saved to $OUTPUT."

