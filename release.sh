#!/usr/bin/env bash
# release.sh — Complete BusyLight Release Automation
#
# Usage:
#   ./release.sh <version> [options]
#
# Arguments:
#   version         Git tag (e.g., v1.0.0 or 1.0.0)
#
# Options:
#   --skip-sign     Skip code signing and notarization
#   --skip-publish  Build DMG but don't publish to GitHub
#   --dry-run       Run all steps except GitHub publish (same as --skip-publish)
#   --help          Show this help message
#
# Environment variables (optional):
#   SIGNING_IDENTITY     Developer ID Application certificate name (default: "Developer ID Application")
#   NOTARIZATION_PROFILE Notarization profile name for notarytool (recommended)
#   APPLE_ID             Apple ID for notarization (legacy method)
#   APPLE_PASSWORD       App-specific password (legacy method)
#   APPLE_TEAM_ID        Team ID for notarization (legacy method)
#
# Examples:
#   ./release.sh v1.0.0                    # Full release with signing
#   ./release.sh 1.0.1 --skip-sign         # Development build without signing
#   ./release.sh v1.2.0 --dry-run          # Build DMG locally only
#
# Requirements:
#   - macOS with Xcode Command Line Tools
#   - Swift toolchain
#   - hdiutil (built-in)
#   - gh CLI (for publishing)

set -euo pipefail

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# Configuration
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$SCRIPT_DIR"
DIST_DIR="$PROJECT_ROOT/dist"
APP_NAME="BusyLight"
BUNDLE_ID="com.busylight.agent"
ICON_PATH="$PROJECT_ROOT/img/busy-light-icon.png"

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# Logging and UI Functions
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

# Colors for terminal output
if [[ -t 1 ]]; then
    RED='\033[0;31m'
    GREEN='\033[0;32m'
    YELLOW='\033[1;33m'
    BLUE='\033[0;34m'
    BOLD='\033[1m'
    NC='\033[0m'
else
    RED='' GREEN='' YELLOW='' BLUE='' BOLD='' NC=''
fi

log() {
    echo -e "${GREEN}▸${NC} $*"
}

section() {
    echo
    echo -e "${BOLD}${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${BOLD}${BLUE}  $*${NC}"
    echo -e "${BOLD}${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo
}

warn() {
    echo -e "${YELLOW}⚠ $*${NC}" >&2
}

fail() {
    echo -e "${RED}✗ ERROR: $*${NC}" >&2
    exit 1
}

success() {
    echo -e "${GREEN}✓ $*${NC}"
}

confirm() {
    local prompt="$1"
    local reply
    read -p "$(echo -e "${YELLOW}?${NC} $prompt [y/N] ")" -n 1 -r reply
    echo
    [[ $reply =~ ^[Yy]$ ]]
}

check_command() {
    local cmd="$1"
    local hint="${2:-}"
    if ! command -v "$cmd" &>/dev/null; then
        fail "Required command not found: $cmd${hint:+ ($hint)}"
    fi
    log "✓ Found: $cmd"
}

require_file() {
    local file="$1"
    local desc="${2:-file}"
    if [[ ! -f "$file" ]]; then
        fail "Required $desc not found: $file"
    fi
}

require_dir() {
    local dir="$1"
    local desc="${2:-directory}"
    if [[ ! -d "$dir" ]]; then
        fail "Required $desc not found: $dir"
    fi
}

ensure_dir() {
    local dir="$1"
    if [[ ! -d "$dir" ]]; then
        mkdir -p "$dir"
        log "Created directory: $dir"
    fi
}

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# Version Stamping
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

stamp_version() {
    local version="$1"
    local version_number="${version#v}"
    local info_plist="$PROJECT_ROOT/macos-agent/Sources/BusyLight/Resources/Info.plist"
    
    require_file "$info_plist" "Info.plist"
    check_command plutil
    
    if ! plutil -lint "$info_plist" &>/dev/null; then
        fail "Info.plist is not valid: $info_plist"
    fi
    
    log "Updating version to $version_number in Info.plist..."
    
    # Extract version components (e.g., "1.0.0" from "1.0.0-beta.1")
    if [[ "$version_number" =~ ^([0-9]+\.[0-9]+\.[0-9]+)(-.*)?$ ]]; then
        local short_version="${BASH_REMATCH[1]}"
        local build_version="$version_number"
    else
        fail "Invalid version format: $version_number (expected: 1.2.3 or 1.2.3-beta.1)"
    fi
    
    # Backup and update
    cp "$info_plist" "$info_plist.bak"
    
    plutil -replace CFBundleShortVersionString -string "$short_version" "$info_plist"
    plutil -replace CFBundleVersion -string "$build_version" "$info_plist"
    
    if ! plutil -lint "$info_plist" &>/dev/null; then
        mv "$info_plist.bak" "$info_plist"
        fail "Info.plist validation failed after modification"
    fi
    
    rm "$info_plist.bak"
    success "CFBundleShortVersionString → $short_version"
    success "CFBundleVersion → $build_version"
}

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# Build
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

build_app() {
    log "Building $APP_NAME in Release configuration..."
    
    if [[ ! -f "$PROJECT_ROOT/build.sh" ]]; then
        fail "build.sh not found in project root"
    fi
    
    cd "$PROJECT_ROOT"
    ./build.sh release
    
    local build_app="$PROJECT_ROOT/$APP_NAME.app"
    if [[ ! -d "$build_app" ]]; then
        fail "Build failed: $build_app not found"
    fi
    
    success "Build complete: $build_app"
}

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# Code Signing and Notarization
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

sign_and_notarize() {
    local app_path="$1"
    local signing_identity="${SIGNING_IDENTITY:-Developer ID Application}"
    
    require_dir "$app_path" "application bundle"
    check_command codesign
    
    local app_name
    app_name="$(basename "$app_path")"
    
    log "Checking for signing identity: $signing_identity"
    
    # Check if signing identity is available
    if ! security find-identity -p codesigning -v | grep -q "$signing_identity"; then
        warn "No signing identity found matching: $signing_identity"
        warn "Available identities:"
        security find-identity -p codesigning -v | grep "Developer ID Application" || echo "  (none)"
        warn ""
        warn "Applying ad-hoc signature for local testing..."
        
        codesign --force --deep --sign - "$app_path"
        success "Applied ad-hoc signature"
        return 0
    fi
    
    success "Found signing identity"
    
    # Code sign with hardened runtime
    log "Signing $app_name with identity: $signing_identity"
    
    codesign \
        --force \
        --deep \
        --options runtime \
        --timestamp \
        --sign "$signing_identity" \
        "$app_path"
    
    success "Code signing complete"
    
    # Verify signature
    if codesign --verify --deep --strict --verbose=2 "$app_path" 2>&1; then
        success "Signature verification passed"
    else
        fail "Signature verification failed"
    fi
    
    # Notarization
    if ! command -v xcrun &>/dev/null || ! xcrun notarytool --version &>/dev/null 2>&1; then
        warn "notarytool not available (requires Xcode 13+)"
        warn "Notarization skipped"
        return 0
    fi
    
    # Check notarization credentials
    local notarization_method=""
    if [[ -n "${NOTARIZATION_PROFILE:-}" ]]; then
        notarization_method="profile"
        log "Notarization: using profile '$NOTARIZATION_PROFILE'"
    elif [[ -n "${APPLE_ID:-}" ]] && [[ -n "${APPLE_PASSWORD:-}" ]] && [[ -n "${APPLE_TEAM_ID:-}" ]]; then
        notarization_method="credentials"
        log "Notarization: using Apple ID credentials"
    else
        warn "Notarization credentials not configured"
        warn "To enable notarization, set NOTARIZATION_PROFILE or APPLE_ID/APPLE_PASSWORD/APPLE_TEAM_ID"
        warn "Skipping notarization..."
        return 0
    fi
    
    # Create ZIP for notarization
    log "Creating ZIP archive for notarization..."
    local zip_path="/tmp/$app_name-$$.zip"
    
    ditto -c -k --keepParent "$app_path" "$zip_path"
    success "Created archive: $zip_path"
    
    # Submit for notarization
    log "Submitting to Apple notarization service..."
    log "(This may take several minutes...)"
    
    local notarize_output
    if [[ "$notarization_method" == "profile" ]]; then
        notarize_output=$(xcrun notarytool submit "$zip_path" \
            --keychain-profile "$NOTARIZATION_PROFILE" \
            --wait 2>&1) || fail "Notarization submission failed"
    else
        notarize_output=$(xcrun notarytool submit "$zip_path" \
            --apple-id "$APPLE_ID" \
            --password "$APPLE_PASSWORD" \
            --team-id "$APPLE_TEAM_ID" \
            --wait 2>&1) || fail "Notarization submission failed"
    fi
    
    rm -f "$zip_path"
    
    if echo "$notarize_output" | grep -q "status: Accepted"; then
        success "Notarization accepted"
        
        # Staple notarization ticket
        log "Stapling notarization ticket..."
        xcrun stapler staple "$app_path" || warn "Could not staple ticket"
        success "Notarization complete"
    else
        warn "Notarization failed or incomplete"
        echo "$notarize_output"
    fi
}

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# DMG Creation
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

create_dmg() {
    local app_path="$1"
    local output_dmg="$2"
    
    require_dir "$app_path" "application bundle"
    check_command hdiutil
    
    local app_name
    app_name="$(basename "$app_path")"
    local volume_name="${app_name%.app}"
    local output_dir
    output_dir="$(dirname "$output_dmg")"
    
    ensure_dir "$output_dir"
    
    log "Preparing DMG staging area..."
    
    local staging_dir
    staging_dir="$(mktemp -d)"
    trap 'rm -rf "$staging_dir"' EXIT
    
    # Copy app to staging
    cp -R "$app_path" "$staging_dir/"
    success "Copied $app_name to staging"
    
    # Create Applications symlink
    ln -s /Applications "$staging_dir/Applications"
    success "Created /Applications symlink"
    
    # Copy icon if available
    if [[ -f "$ICON_PATH" ]]; then
        cp "$ICON_PATH" "$staging_dir/.VolumeIcon.icns"
        success "Added volume icon: $ICON_PATH"
    else
        warn "Icon not found at $ICON_PATH, DMG will use default icon"
    fi
    
    # Create DMG
    log "Creating DMG..."
    
    # Clean up any previous mount
    local mount_dir="/Volumes/$volume_name"
    if [[ -d "$mount_dir" ]]; then
        warn "Volume already mounted, cleaning up..."
        diskutil unmount force "$mount_dir" &>/dev/null || hdiutil detach "$mount_dir" -force &>/dev/null || true
    fi
    
    if [[ -f "$output_dmg" ]]; then
        rm -f "$output_dmg"
        log "Removed existing DMG"
    fi
    
    local temp_dmg="/tmp/temp-$$.dmg"
    
    hdiutil create \
        -volname "$volume_name" \
        -srcfolder "$staging_dir" \
        -ov \
        -format UDRW \
        "$temp_dmg" \
        &> /dev/null
    
    success "Created temporary DMG"
    
    # Mount and apply custom icon
    log "Applying custom icon to DMG..."
    
    hdiutil attach "$temp_dmg" -mountpoint "$mount_dir" -nobrowse &> /dev/null
    
    # Apply custom icon to volume (if available)
    if [[ -f "$ICON_PATH" ]]; then
        # Convert PNG to .icns for volume icon (requires sips)
        if command -v sips &>/dev/null; then
            local temp_iconset="/tmp/BusyLight.iconset"
            mkdir -p "$temp_iconset"
            
            sips -z 512 512 "$ICON_PATH" --out "$temp_iconset/icon_512x512.png" &>/dev/null || true
            sips -z 256 256 "$ICON_PATH" --out "$temp_iconset/icon_256x256.png" &>/dev/null || true
            sips -z 128 128 "$ICON_PATH" --out "$temp_iconset/icon_128x128.png" &>/dev/null || true
            
            if command -v iconutil &>/dev/null; then
                iconutil -c icns "$temp_iconset" -o "$mount_dir/.VolumeIcon.icns" 2>/dev/null || true
                SetFile -c icnC "$mount_dir/.VolumeIcon.icns" 2>/dev/null || true
                SetFile -a C "$mount_dir" 2>/dev/null || true
            fi
            
            rm -rf "$temp_iconset"
        fi
    fi
    
    # Skip Finder window customization to avoid locking the volume
    # The DMG will work fine without custom positioning
    log "Skipping Finder customization (prevents unmount issues)"
    
    # Sync to ensure all writes complete
    sync
    sleep 1
    
    # Unmount (with retries if busy)
    log "Unmounting DMG..."
    local unmount_attempts=0
    while [[ $unmount_attempts -lt 5 ]]; do
        # Try diskutil first, then hdiutil
        if diskutil unmount "$mount_dir" &> /dev/null || hdiutil detach "$mount_dir" -force &> /dev/null; then
            success "Unmounted DMG"
            break
        fi
        unmount_attempts=$((unmount_attempts + 1))
        if [[ $unmount_attempts -lt 5 ]]; then
            warn "Unmount attempt $unmount_attempts failed, retrying..."
            # Try to kill any processes holding the mount
            lsof "$mount_dir" 2>/dev/null | grep -v "COMMAND" | awk '{print $2}' | xargs kill -9 2>/dev/null || true
            sleep 2
        else
            # Last resort: restart Finder and try one more time
            warn "Trying last resort: restarting Finder..."
            lsof "$mount_dir" 2>/dev/null || true
            killall Finder 2>/dev/null || true
            sleep 3
            
            if diskutil unmount force "$mount_dir" &>/dev/null; then
                success "Unmounted DMG after restarting Finder"
                break
            fi
            
            fail "Failed to unmount DMG after all attempts. Manual cleanup required: diskutil unmount force $mount_dir"
        fi
    done
    
    # Wait for system to fully release the DMG file
    log "Waiting for system to release DMG file..."
    sync
    sleep 3
    
    # Verify temp DMG is accessible
    if [[ ! -f "$temp_dmg" ]]; then
        fail "Temporary DMG file not found: $temp_dmg"
    fi
    
    # Convert to compressed read-only (with retries)
    log "Compressing DMG..."
    local convert_attempts=0
    local convert_success=false
    
    while [[ $convert_attempts -lt 3 ]] && [[ "$convert_success" == "false" ]]; do
        convert_attempts=$((convert_attempts + 1))
        
        if hdiutil convert "$temp_dmg" \
            -format UDZO \
            -imagekey zlib-level=9 \
            -o "$output_dmg" \
            2>&1; then
            convert_success=true
        else
            if [[ $convert_attempts -lt 3 ]]; then
                warn "Compression attempt $convert_attempts failed, retrying..."
                sync
                sleep 2
            else
                fail "DMG compression failed after $convert_attempts attempts"
            fi
        fi
    done
    
    rm -f "$temp_dmg"
    
    if [[ ! -f "$output_dmg" ]]; then
        fail "DMG file was not created: $output_dmg"
    fi
    
    success "DMG created: $output_dmg"
    log "Size: $(du -h "$output_dmg" | cut -f1)"
}

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# GitHub Release Publishing
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

publish_github_release() {
    local version="$1"
    local dmg_path="$2"
    
    check_command gh
    require_file "$dmg_path" "DMG file"
    
    # Verify gh authentication
    if ! gh auth status &>/dev/null; then
        fail "GitHub CLI not authenticated. Run: gh auth login"
    fi
    
    success "GitHub CLI authenticated"
    
    # Get repository info
    local repo_name
    repo_name=$(gh repo view --json nameWithOwner -q .nameWithOwner)
    log "Repository: $repo_name"
    
    # Check if release exists
    if gh release view "$version" &>/dev/null; then
        warn "Release $version already exists"
        
        if confirm "Delete existing release and create new one?"; then
            gh release delete "$version" --yes
            success "Deleted existing release"
        else
            fail "Release already exists, aborting"
        fi
    fi
    
    # Generate release notes
    log "Generating release notes..."
    
    local prev_tag
    prev_tag=$(git describe --tags --abbrev=0 "$version^" 2>/dev/null || echo "")
    
    local notes_file="/tmp/release-notes-$$.md"
    
    {
        echo "## 🎉 BusyLight $version"
        echo
        
        if [[ -n "$prev_tag" ]]; then
            echo "### Cambios desde $prev_tag"
            echo
            git log --pretty=format:"- %s (%h)" "$prev_tag..$version" | grep -v "^- Merge" || echo "- Release inicial"
        else
            echo "### Release Inicial"
            echo
            echo "Primer release público de BusyLight - indicador de presencia para macOS con integración de calendario."
        fi
        
        echo
        echo "---"
        echo
        echo "### 📦 Instalación"
        echo
        echo "1. Descarga \`$(basename "$dmg_path")\` de los assets abajo"
        echo "2. Abre el archivo DMG"
        echo "3. Arrastra **BusyLight.app** a la carpeta **Applications**"
        echo "4. Ejecuta BusyLight desde Applications"
        echo "5. Otorga permisos de Calendario cuando se solicite"
        echo
        echo "### 🔒 Nota de Seguridad"
        echo
        
        local app_path="$PROJECT_ROOT/$APP_NAME.app"
        if [[ -d "$app_path" ]] && codesign -dv "$app_path" 2>&1 | grep -q "Developer ID Application"; then
            echo "- ✅ Firmado con certificado Developer ID"
            if xcrun stapler validate "$app_path" &>/dev/null; then
                echo "- ✅ Notarizado por Apple"
            else
                echo "- ⚠️ No notarizado (puede requerir permitir en Preferencias del Sistema)"
            fi
        else
            echo "- ⚠️ No firmado con Developer ID (deberá permitir en Preferencias del Sistema → Privacidad y Seguridad)"
        fi
        
        echo
        echo "### 📋 Requisitos"
        echo
        echo "- macOS 14.0 (Sonoma) o posterior"
        echo "- Dispositivo compatible con WLED"
        echo
        echo "### 📚 Documentación"
        echo
        echo "- [Guía de Configuración](https://github.com/$repo_name/blob/main/docs/configuration.md)"
        echo "- [Integración de Calendario](https://github.com/$repo_name/blob/main/docs/eventkit-calendar-integration.md)"
        echo "- [Configuración de Hotkeys](https://github.com/$repo_name/blob/main/docs/hotkey.md)"
        
    } > "$notes_file"
    
    # Create release
    log "Creating GitHub release: $version"
    
    local prerelease_flag=""
    if [[ "$version" =~ -alpha|-beta|-rc ]]; then
        prerelease_flag="--prerelease"
        log "(Marcado como prerelease)"
    fi
    
    gh release create "$version" \
        --title "BusyLight $version" \
        --notes-file "$notes_file" \
        $prerelease_flag \
        "$dmg_path"
    
    rm -f "$notes_file"
    
    success "GitHub release published"
    log "URL: https://github.com/$repo_name/releases/tag/$version"
}

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# Main Script
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

show_help() {
    sed -n '2,/^$/p' "$0" | sed 's/^# \?//'
    exit 0
}

# Parse arguments
VERSION=""
SKIP_SIGN=false
SKIP_PUBLISH=false

while [[ $# -gt 0 ]]; do
    case "$1" in
        --help|-h)
            show_help
            ;;
        --skip-sign)
            SKIP_SIGN=true
            shift
            ;;
        --skip-publish|--dry-run)
            SKIP_PUBLISH=true
            shift
            ;;
        -*)
            fail "Unknown option: $1 (use --help for usage)"
            ;;
        *)
            if [[ -z "$VERSION" ]]; then
                VERSION="$1"
            else
                fail "Unexpected argument: $1"
            fi
            shift
            ;;
    esac
done

if [[ -z "$VERSION" ]]; then
    fail "Usage: $0 <version> [--skip-sign] [--skip-publish]"
fi

# Normalize version (add 'v' prefix if missing)
if [[ ! "$VERSION" =~ ^v ]]; then
    VERSION="v$VERSION"
fi

# Validate version format
if [[ ! "$VERSION" =~ ^v[0-9]+\.[0-9]+\.[0-9]+(-[a-zA-Z0-9.]+)?$ ]]; then
    fail "Invalid version format: $VERSION (expected: v1.2.3 or v1.2.3-beta.1)"
fi

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# Preflight Checks
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

section "Preflight Checks"

check_command git
check_command swift
check_command codesign
check_command hdiutil
check_command plutil

if [[ "$SKIP_PUBLISH" == "false" ]]; then
    check_command gh
    
    if ! gh auth status &>/dev/null; then
        fail "GitHub CLI not authenticated. Run: gh auth login"
    fi
    log "✓ GitHub CLI authenticated"
fi

# Verify we're in a git repository
if ! git rev-parse --git-dir &>/dev/null; then
    fail "Not in a git repository"
fi

# Check for uncommitted changes
if [[ -n "$(git status --porcelain)" ]]; then
    warn "Working directory has uncommitted changes"
    
    if ! confirm "Continue anyway?"; then
        exit 1
    fi
fi

# Verify or create tag
if ! git rev-parse "$VERSION" &>/dev/null; then
    warn "Tag $VERSION does not exist"
    
    if confirm "Create tag $VERSION at HEAD?"; then
        git tag -a "$VERSION" -m "Release $VERSION"
        success "Created tag $VERSION"
    else
        fail "Tag required for release"
    fi
fi

log "✓ Release version: $VERSION"
log "✓ Commit: $(git rev-parse --short "$VERSION")"

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# Step 1: Version Stamping
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

section "Step 1: Version Stamping"
stamp_version "$VERSION"

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# Step 2: Build
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

section "Step 2: Build Application"
build_app

BUILD_APP="$PROJECT_ROOT/$APP_NAME.app"

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# Step 3: Code Signing
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

if [[ "$SKIP_SIGN" == "true" ]]; then
    section "Step 3: Code Signing (SKIPPED)"
    log "Signing and notarization skipped by request"
    
    # Apply ad-hoc signature for local testing
    codesign --force --deep --sign - "$BUILD_APP"
    success "Applied ad-hoc signature"
else
    section "Step 3: Code Signing and Notarization"
    sign_and_notarize "$BUILD_APP"
fi

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# Step 4: Package DMG
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

section "Step 4: Package DMG"

VERSION_NUMBER="${VERSION#v}"
DMG_NAME="$APP_NAME-$VERSION_NUMBER.dmg"

create_dmg "$BUILD_APP" "$DIST_DIR/$DMG_NAME"

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# Step 5: Publish to GitHub
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

if [[ "$SKIP_PUBLISH" == "true" ]]; then
    section "Step 5: GitHub Release (SKIPPED)"
    log "GitHub release skipped (dry-run mode)"
else
    section "Step 5: Publish to GitHub"
    publish_github_release "$VERSION" "$DIST_DIR/$DMG_NAME"
fi

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# Summary
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

section "Release Complete! 🎉"

log "Version:  $VERSION"
log "Artifact: $DIST_DIR/$DMG_NAME"
log "Size:     $(du -h "$DIST_DIR/$DMG_NAME" | cut -f1)"

if [[ "$SKIP_PUBLISH" == "false" ]]; then
    REPO_NAME=$(gh repo view --json nameWithOwner -q .nameWithOwner 2>/dev/null || echo "")
    if [[ -n "$REPO_NAME" ]]; then
        log "GitHub:   https://github.com/$REPO_NAME/releases/tag/$VERSION"
    fi
fi

echo
log "Próximos pasos:"
log "  1. Probar el DMG en una instalación limpia de macOS"
log "  2. Verificar que los permisos de calendario funcionan correctamente"
log "  3. Actualizar notas de release si es necesario"

if [[ "$SKIP_PUBLISH" == "false" ]]; then
    log "  4. Hacer push del tag: git push origin $VERSION"
else
    log "  4. Publicar release: ./release.sh $VERSION"
    log "  5. Hacer push del tag: git push origin $VERSION"
fi
