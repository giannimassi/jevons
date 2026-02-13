#!/bin/sh
# install.sh - Install Jevons from GitHub releases
# Usage: ./install.sh [version]
# Example: ./install.sh v0.1.0
#          curl -fsSL https://raw.githubusercontent.com/giannimassi/jevons/main/install.sh | bash -s -- v0.1.0

set -e

# Configuration
OWNER="giannimassi"
REPO="jevons"
BINARY_NAME="jevons"
INSTALL_DIR="./bin"

# Detect OS and architecture
detect_platform() {
    os_type=$(uname -s)
    arch=$(uname -m)

    case "$os_type" in
        Darwin)
            os="darwin"
            ;;
        Linux)
            os="linux"
            ;;
        *)
            echo "Error: unsupported OS '$os_type'" >&2
            exit 1
            ;;
    esac

    case "$arch" in
        arm64|aarch64)
            arch="arm64"
            ;;
        x86_64)
            arch="amd64"
            ;;
        *)
            echo "Error: unsupported architecture '$arch'" >&2
            exit 1
            ;;
    esac

    echo "${os}_${arch}"
}

# Fetch the latest release version from GitHub API
get_latest_version() {
    latest_json=$(curl -fsSL "https://api.github.com/repos/${OWNER}/${REPO}/releases/latest" 2>/dev/null)
    if [ -z "$latest_json" ]; then
        echo "Error: failed to fetch latest release from GitHub" >&2
        exit 1
    fi

    # Extract version tag (remove 'v' prefix)
    version=$(echo "$latest_json" | grep -o '"tag_name":"[^"]*"' | cut -d'"' -f4 | head -1)
    if [ -z "$version" ]; then
        echo "Error: could not determine latest version" >&2
        exit 1
    fi

    echo "$version"
}

# Download file with error handling
download_file() {
    url="$1"
    output="$2"

    if ! curl -fsSL -o "$output" "$url"; then
        echo "Error: failed to download from $url" >&2
        exit 1
    fi
}

# Validate checksum
validate_checksum() {
    checksums_file="$1"
    archive="$2"

    if [ ! -f "$checksums_file" ]; then
        echo "Error: checksums file not found" >&2
        exit 1
    fi

    # Extract the checksum for the archive from checksums.txt
    expected_checksum=$(grep "$(basename "$archive")" "$checksums_file" | awk '{print $1}')
    if [ -z "$expected_checksum" ]; then
        echo "Error: checksum not found for $(basename "$archive")" >&2
        exit 1
    fi

    # Compute checksum (use shasum on macOS, sha256sum on Linux)
    if command -v shasum >/dev/null 2>&1; then
        actual_checksum=$(shasum -a 256 "$archive" | awk '{print $1}')
    elif command -v sha256sum >/dev/null 2>&1; then
        actual_checksum=$(sha256sum "$archive" | awk '{print $1}')
    else
        echo "Error: neither 'shasum' nor 'sha256sum' found" >&2
        exit 1
    fi

    if [ "$expected_checksum" != "$actual_checksum" ]; then
        echo "Error: checksum mismatch for $(basename "$archive")" >&2
        echo "  Expected: $expected_checksum" >&2
        echo "  Got:      $actual_checksum" >&2
        exit 1
    fi
}

# Main installation flow
main() {
    # Determine version (argument or latest)
    if [ -n "$1" ]; then
        version="$1"
    else
        echo "Fetching latest release..."
        version=$(get_latest_version)
    fi

    echo "Installing Jevons $version"

    # Detect platform
    platform=$(detect_platform)
    echo "Detected platform: $platform"

    # Create temp directory for downloads
    temp_dir=$(mktemp -d)
    trap "rm -rf $temp_dir" EXIT

    # Download archive and checksums
    archive_name="${BINARY_NAME}_${version#v}_${platform}.tar.gz"
    archive_url="https://github.com/${OWNER}/${REPO}/releases/download/${version}/${archive_name}"
    checksums_url="https://github.com/${OWNER}/${REPO}/releases/download/${version}/checksums.txt"

    echo "Downloading from $archive_url"
    download_file "$archive_url" "$temp_dir/$archive_name"

    echo "Downloading checksums..."
    download_file "$checksums_url" "$temp_dir/checksums.txt"

    # Validate checksum
    echo "Validating checksum..."
    validate_checksum "$temp_dir/checksums.txt" "$temp_dir/$archive_name"
    echo "Checksum valid ✓"

    # Extract archive
    echo "Extracting archive..."
    tar -xzf "$temp_dir/$archive_name" -C "$temp_dir"

    # Create install directory if it doesn't exist
    mkdir -p "$INSTALL_DIR"

    # Move binary to install location
    if [ ! -f "$temp_dir/$BINARY_NAME" ]; then
        echo "Error: binary not found in archive" >&2
        exit 1
    fi

    mv "$temp_dir/$BINARY_NAME" "$INSTALL_DIR/$BINARY_NAME"
    chmod +x "$INSTALL_DIR/$BINARY_NAME"

    echo "Installation complete ✓"
    echo "Binary installed to: $INSTALL_DIR/$BINARY_NAME"
    echo ""
    echo "Next steps:"
    echo "  1. Add $INSTALL_DIR to your PATH (if not already)"
    echo "  2. Run: jevons doctor"
}

main "$@"
