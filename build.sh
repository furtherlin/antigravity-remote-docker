#!/bin/bash
#
# Build the antigravity docker contianer Script
#
#

set -euo pipefail

# 1. Default Setup & Constants
Antigravity_Base_Url="https://antigravity-hub-auto-updater-974169037036.us-central1.run.app"
Antigravity_IDE_Base_Url="https://antigravity-ide-auto-updater-974169037036.us-central1.run.app"
Antigravity_cli_Base_Url="https://antigravity-cli-auto-updater-974169037036.us-central1.run.app"


echo "⠋ Detecting system environment..."

# 2. Detect Platform
case "$(uname -s)" in
    Darwin) os="darwin" ;;
    Linux) os="linux" ;;
    *) echo "Fatal: Unsupported operating system: $(uname -s). Antigravity CLI currently supports 64-bit Windows, macOS, and Linux." >&2; exit 1 ;;
esac

case "$(uname -m)" in
    x86_64|amd64) arch="amd64" ;;
    arm64|aarch64) arch="arm64" ;;
    *) echo "Fatal: Unsupported architecture: $(uname -m). Antigravity CLI currently supports 64-bit Windows, macOS, and Linux." >&2; exit 1 ;;
esac

# musl libc detection on Linux
platform=""
if [ "$os" = "linux" ]; then
    if [ -f /lib/libc.musl-x86_64.so.1 ] || [ -f /lib/libc.musl-aarch64.so.1 ] || ldd /bin/ls 2>&1 | grep -q musl; then
        platform="linux_${arch}_musl"
    else
        platform="linux_${arch}"
    fi
else
    platform="${os}_${arch}"
fi

echo "✓ Platform detected: $platform"

# 4. Manifest Query & JSON Parsing (POSIX-Compliant)
echo "⠋ Querying release repository..."

PS3='Please enter your choice (1-4): '

# Array of available choices
options=(
    "Antigravity"
    "Antigravity-ide"
    "Antigravity-cli"
    "Quit"
)

antigravity_select_and_download_release() {
    # 1. Define release arrays
    # Fetch live data from the endpoint
    local Download_App_name="$1"
    local Base_Url="$2"
    local Url_para="$3"

    echo "⠋ Querying release repository for $Download_App_name ($platform)..."

    response=$(curl -s "$Base_Url/$Url_para")

    # 2. Load into Bash arrays using jq
    #readarray -t versions < <(echo "$response" | jq -r '.[].version')
    #readarray -t exec_ids < <(echo "$response" | jq -r '.[].execution_id')

    # Load all version strings into a Bash array named 'versions'
    readarray -t versions < <(echo "$response" | grep -Po '"version"\s*:\s*"\K[^"]+')

    # Load all execution IDs into a Bash array named 'exec_ids'
    readarray -t exec_ids < <(echo "$response" | grep -Po '"execution_id"\s*:\s*"\K[^"]+')

    # 3. Configure menu prompt dynamically
    local total_options=$(( ${#versions[@]} + 1 ))
    local PS3="Please select a release file to download (1-${total_options}): "

    # 4. Interactive selection menu
    select opt in "${versions[@]}" "Quit"; do
        # Handle Quit
        if [[ "$opt" == "Quit" ]]; then
            echo "Exiting selection menu."
            return 0
        fi

        # Handle valid menu option
        if [[ -n "$opt" ]]; then
            # Convert 1-based menu choice ($REPLY) to 0-based array index
            local idx=$(( REPLY - 1 ))

            local version="${versions[$idx]}"
            local exec_id="${exec_ids[$idx]}"
            local download_url="${Base_Url}/${version}-${exec_id}"

            echo "----------------------------------------"
            #echo "Selection  : Option $REPLY -> $version"
            echo "Selection  : $Download_App_name $version"
            echo "Release ID : $exec_id"
            echo "URL        : $download_url"
            echo "----------------------------------------"

            full_version="${version}-${exec_id}"
            return 0
        else
            echo "Invalid selection '$REPLY'. Please choose a number between 1 and ${total_options}."
        fi
    done
}

select opt in "${options[@]}"; do
    case $opt in
        "${options[0]}")
            echo "Start Building Antigravity ..."
            antigravity_select_and_download_release "${options[0]}" "$Antigravity_Base_Url" "releases"
            docker build --build-arg ANTIGRAVITY_VERSION=${full_version} --target builder-antigravity -t antigravity-remote:latest .
            exit 0
            ;;
        "${options[1]}")
            echo "Start Building Antigravity IDE ..."
            antigravity_select_and_download_release "${options[1]}" "$Antigravity_IDE_Base_Url" "releases"
            docker build --build-arg ANTIGRAVITY_IDE_VERSION=${full_version} --target builder-antigravity-ide -t antigravity-remote:latest .
            exit 0
            ;;
        "${options[2]}")
            echo "Start Building Antigravity CLI ..."
            antigravity_select_and_download_release "${options[2]}" "$Antigravity_cli_Base_Url" "releases"
            exit 0
            ;;
        "${options[3]}")
            echo "Exiting script."
            exit 0
            ;;
        *)
            echo "Invalid option: $REPLY"
            ;;
    esac
done
