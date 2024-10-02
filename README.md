
# Mac Storage Manager

The Mac Storage Manager is a shell script designed to help you manage disk space by identifying large applications on your Mac. It allows you to see the size of various installed applications, including Homebrew packages, and interactively select which ones to delete. It also provides options to delete associated caches and configuration files to free up additional space.

![Mac Storage Manager Logo](./images/logo.png)

## Features

- **Size Calculation**: The script calculates the size of:
  - Homebrew formulas (installed via `brew list --formula`)
  - Homebrew casks (installed via `brew list --cask`)
  - Applications in `/Applications` and `~/Applications` directories
  - Optionally, applications found across the entire system via `sudo find`

![Sudo Find Prompt](./images/screenshot_sudo_find.png)

- **Interactive Deletion**: After collecting the application sizes, the script allows you to interactively select applications for deletion using a graphical dialog (`whiptail`).

- **Selective Deletion**: The script prompts you for each category of associated files (Application Support, Preferences, Caches, Logs, Saved Application State) whether you want to delete them.

- **Comprehensive Removal**: The script not only deletes the main application files but also associated files, including:
  - **Homebrew Files**:
    - Uninstalls associated Homebrew formulas and casks.
  - **Application Support files** (optional)
  - **Preferences** (optional)
  - **Caches** (optional)
  - **Logs** (optional)
  - **Saved Application State** (optional)
  - **Other files matching the application name found via `sudo find`** (optional)

- **User Confirmation**: Before deleting any files, the script prompts for confirmation, displaying exactly which files and directories will be removed.

- **Progress Bar and Sound Effects**: The script displays a progress bar during long-running tasks and provides audio feedback for key actions (e.g., when interacting with the GUI).

- **Logging**: The script creates a log file `application_size_checker.log` where errors and warnings are recorded. Check this file if you encounter issues during execution.

## How to Use

### Step 1: Clone the Repository

Clone this repository to your local machine using:

```bash
git clone https://github.com/NarekMosisian/mac-storage-manager.git
```

### Step 2: Make the Script Executable

Navigate to the cloned directory and make the script executable by running:

```bash
chmod +x ./application_size_checker.sh
```

### Step 3: Install Dependencies

The script relies on several tools. Install them via Homebrew:

```bash
brew install jq whiptail
```

    jq: Parses JSON output from system commands.
    whiptail: Provides terminal-based GUI dialogs (for interactive selection and progress bars).

### Step 4: Run the Script

Run the script with the following command:

```bash
./application_size_checker.sh
```

Note: The script uses zsh. Ensure that zsh is installed and set as your default shell, or run the script explicitly with zsh:

```bash
zsh ./application_size_checker.sh
```

### Step 5: Follow the Interactive Prompt

During the script's execution, you will be prompted with the following option:

    Include sudo find: This step searches for all applications across the system but may take a long time to complete.

Once the script has gathered the sizes of all applications, a graphical interface will appear, allowing you to select the applications you wish to delete. After selection, the script will:

    Prompt for confirmation before deleting each application and its associated files.
    Display the list of files and directories that will be removed for each application.
    Prompt you for each category of associated files (Application Support, Preferences, Caches, Logs, Saved Application State) whether you want to delete them.
    Optionally delete any additional files found via sudo find that are associated with the application.

## Known Limitations and Common Issues

- **Performance**: Searching the entire system with sudo find can be very time-consuming and may strain system resources.
- **Permissions**: Ensure you have the necessary permissions to uninstall applications and delete files.
- **Security Warning**: Be cautious when deleting applications and files to avoid data loss.
- **Shell Compatibility**: The script is written for zsh. Ensure you have zsh installed.

## Dependencies

This script relies on the following tools:

- **jq**: A lightweight and flexible command-line JSON processor.
- **Homebrew**: A package manager for macOS.
- **whiptail**: A package for creating GUI dialogs in the terminal.

Make sure these dependencies are installed before running the script.

## What Exactly is Deleted

When you confirm the deletion of an application, the script attempts to thoroughly remove it by deleting:

- **Main Application Files**: The application bundle from `/Applications` and `~/Applications`.

- **Homebrew Files**:
    - Uninstalls associated Homebrew formulas and casks installed via Homebrew.

- **Associated Files and Directories**:
    - **Application Support** (optional):
        - `~/Library/Application Support/<Application Name>`
        - `/Library/Application Support/<Application Name>`
    - **Preferences** (optional):
        - `~/Library/Preferences/com.<Application Name>.*`
        - `/Library/Preferences/com.<Application Name>.*`
    - **Caches** (optional):
        - `~/Library/Caches/<Application Name>`
        - `~/Library/Caches/com.<Application Name>.*`
        - `/Library/Caches/<Application Name>`
        - `/Library/Caches/com.<Application Name>.*`
    - **Logs** (optional):
        - `~/Library/Logs/<Application Name>`
        - `/Library/Logs/<Application Name>`
    - **Saved Application State** (optional):
        - `~/Library/Saved Application State/com.<Application Name>.*`
        - `/Library/Saved Application State/com.<Application Name>.*`

- **Additional Files Found via `sudo find` (optional)**: Any files matching the application name found during the `sudo find` operation (if you chose to include this step). The script will display these files and ask for your confirmation before deletion.

## Log File

The script creates a log file `application_size_checker.log` where errors and warnings are recorded. Check this file if you encounter issues during execution.

## Warning

Please read the following carefully before using the script:

- **Data Loss Risk**: The script performs a thorough deletion of applications and their associated files. Be cautious when selecting applications to delete. Ensure that you do not remove essential system applications or files.
- **Review Before Deleting**: Before any files are deleted, the script will display a list of files and directories that will be removed. Please review this list carefully to avoid unintended deletions.
- **No Undo**: Deleting applications and files is permanent and cannot be undone. Consider backing up important data before proceeding.
- **Use at Your Own Risk**: The script is provided "as is," without warranty of any kind. The author is not responsible for any damage or data loss that may occur as a result of using this script.

## License

This project is licensed under the MIT License. See the LICENSE file for more details.
