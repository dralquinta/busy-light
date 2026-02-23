#!/usr/bin/env bash
# rollback-release.sh — Rollback a failed or problematic release
#
# Usage:
#   ./scripts/rollback-release.sh <version>
#
# Arguments:
#   version    Version tag to rollback (e.g., v1.0.0)
#
# Actions:
#   - Deletes GitHub release (if exists)
#   - Removes git tag (local and remote)
#   - Restores previous Info.plist version
#   - Cleans up generated artifacts
#
# Options:
#   --keep-tag       Keep the git tag (only delete GitHub release)
#   --keep-remote    Keep remote tag (only delete local)
#   --dry-run        Show what would be done without doing it

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Colors
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

log() { echo -e "${GREEN}▸${NC} $*"; }
warn() { echo -e "${YELLOW}⚠${NC} $*"; }
fail() { echo -e "${RED}✗${NC} $*" >&2; exit 1; }
success() { echo -e "${GREEN}✓${NC} $*"; }
info() { echo -e "${BLUE}ℹ${NC} $*"; }

section() {
    echo
    echo -e "${BOLD}${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${BOLD}${BLUE}  $*${NC}"
    echo -e "${BOLD}${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo
}

confirm() {
    local prompt="$1"
    local reply
    read -p "$(echo -e "${YELLOW}?${NC} $prompt [y/N] ")" -n 1 -r reply
    echo
    [[ $reply =~ ^[Yy]$ ]]
}

# Parse arguments
VERSION=""
KEEP_TAG=false
KEEP_REMOTE=false
DRY_RUN=false

while [[ $# -gt 0 ]]; do
    case "$1" in
        --keep-tag)
            KEEP_TAG=true
            shift
            ;;
        --keep-remote)
            KEEP_REMOTE=true
            shift
            ;;
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        -*)
            fail "Unknown option: $1"
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
    fail "Usage: $0 <version> [--keep-tag] [--keep-remote] [--dry-run]"
fi

# Normalize version
if [[ ! "$VERSION" =~ ^v ]]; then
    VERSION="v$VERSION"
fi

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# Preflight
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

section "Rollback Preflight"

if [[ "$DRY_RUN" == "true" ]]; then
    warn "DRY RUN MODE - no changes will be made"
fi

log "Version to rollback: $VERSION"

# Check git repo
if ! git rev-parse --git-dir &>/dev/null; then
    fail "Not in a git repository"
fi

# Check if tag exists
if ! git rev-parse "$VERSION" &>/dev/null 2>&1; then
    warn "Tag $VERSION does not exist locally"
else
    log "✓ Tag $VERSION exists locally"
fi

# Check if tag exists on remote
if git ls-remote --tags origin | grep -q "refs/tags/$VERSION$"; then
    log "✓ Tag $VERSION exists on remote"
    TAG_ON_REMOTE=true
else
    warn "Tag $VERSION does not exist on remote"
    TAG_ON_REMOTE=false
fi

# Check GitHub CLI
if command -v gh &>/dev/null; then
    if gh auth status &>/dev/null; then
        log "✓ GitHub CLI authenticated"
        HAS_GH=true
    else
        warn "GitHub CLI not authenticated"
        HAS_GH=false
    fi
else
    warn "GitHub CLI not available"
    HAS_GH=false
fi

# Confirm action
echo
warn "This will rollback release $VERSION"
echo "Actions to perform:"
echo "  - Delete GitHub release (if exists)"
if [[ "$KEEP_TAG" == "false" ]]; then
    echo "  - Delete local git tag"
    if [[ "$KEEP_REMOTE" == "false" ]] && [[ "$TAG_ON_REMOTE" == "true" ]]; then
        echo "  - Delete remote git tag"
    fi
fi
echo "  - Clean up build artifacts"
echo

if [[ "$DRY_RUN" == "false" ]]; then
    if ! confirm "Proceed with rollback?"; then
        log "Rollback cancelled"
        exit 0
    fi
fi

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# Delete GitHub Release
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

if [[ "$HAS_GH" == "true" ]]; then
    section "Step 1: Delete GitHub Release"
    
    if gh release view "$VERSION" &>/dev/null; then
        log "Found GitHub release: $VERSION"
        
        if [[ "$DRY_RUN" == "true" ]]; then
            info "[DRY RUN] Would delete GitHub release $VERSION"
        else
            if gh release delete "$VERSION" --yes; then
                success "Deleted GitHub release $VERSION"
            else
                warn "Failed to delete GitHub release (may not exist)"
            fi
        fi
    else
        info "No GitHub release found for $VERSION"
    fi
else
    info "Skipping GitHub release deletion (gh not available)"
fi

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# Delete Git Tags
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

if [[ "$KEEP_TAG" == "false" ]]; then
    section "Step 2: Delete Git Tags"
    
    # Delete local tag
    if git rev-parse "$VERSION" &>/dev/null 2>&1; then
        if [[ "$DRY_RUN" == "true" ]]; then
            info "[DRY RUN] Would delete local tag $VERSION"
        else
            if git tag -d "$VERSION"; then
                success "Deleted local tag $VERSION"
            else
                warn "Failed to delete local tag"
            fi
        fi
    else
        info "Local tag $VERSION does not exist"
    fi
    
    # Delete remote tag
    if [[ "$KEEP_REMOTE" == "false" ]] && [[ "$TAG_ON_REMOTE" == "true" ]]; then
        if [[ "$DRY_RUN" == "true" ]]; then
            info "[DRY RUN] Would delete remote tag $VERSION"
        else
            warn "Deleting remote tag - this affects all users!"
            if confirm "Really delete remote tag?"; then
                if git push origin ":refs/tags/$VERSION"; then
                    success "Deleted remote tag $VERSION"
                else
                    warn "Failed to delete remote tag"
                fi
            else
                info "Skipped remote tag deletion"
            fi
        fi
    fi
else
    info "Keeping git tags (--keep-tag specified)"
fi

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# Restore Previous Version
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

section "Step 3: Restore Previous Version"

INFO_PLIST="$PROJECT_ROOT/macos-agent/Sources/BusyLight/Resources/Info.plist"

if [[ -f "$INFO_PLIST" ]]; then
    CURRENT_VERSION=$(plutil -extract CFBundleShortVersionString raw "$INFO_PLIST" 2>/dev/null || echo "unknown")
    log "Current Info.plist version: $CURRENT_VERSION"
    
    # Find previous tag
    PREV_TAG=$(git describe --tags --abbrev=0 "$VERSION^" 2>/dev/null || echo "")
    
    if [[ -n "$PREV_TAG" ]]; then
        PREV_VERSION="${PREV_TAG#v}"
        log "Previous version: $PREV_VERSION"
        
        if [[ "$DRY_RUN" == "true" ]]; then
            info "[DRY RUN] Would restore Info.plist to version $PREV_VERSION"
        else
            if confirm "Restore Info.plist to version $PREV_VERSION?"; then
                # Extract version components
                if [[ "$PREV_VERSION" =~ ^([0-9]+\.[0-9]+\.[0-9]+)(-.*)?$ ]]; then
                    SHORT_VERSION="${BASH_REMATCH[1]}"
                    BUILD_VERSION="$PREV_VERSION"
                    
                    plutil -replace CFBundleShortVersionString -string "$SHORT_VERSION" "$INFO_PLIST"
                    plutil -replace CFBundleVersion -string "$BUILD_VERSION" "$INFO_PLIST"
                    
                    success "Restored Info.plist to $PREV_VERSION"
                else
                    warn "Could not parse previous version: $PREV_VERSION"
                fi
            else
                info "Skipped Info.plist restoration"
            fi
        fi
    else
        warn "No previous version tag found"
        info "You may need to manually edit Info.plist"
    fi
else
    warn "Info.plist not found: $INFO_PLIST"
fi

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# Clean Artifacts
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

section "Step 4: Clean Build Artifacts"

cd "$PROJECT_ROOT"

ARTIFACTS=(
    "dist/BusyLight-${VERSION#v}.dmg"
    "BusyLight.app"
)

for artifact in "${ARTIFACTS[@]}"; do
    if [[ -e "$artifact" ]]; then
        if [[ "$DRY_RUN" == "true" ]]; then
            info "[DRY RUN] Would delete: $artifact"
        else
            if rm -rf "$artifact"; then
                success "Deleted: $artifact"
            else
                warn "Failed to delete: $artifact"
            fi
        fi
    fi
done

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# Summary
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

section "Rollback Complete"

if [[ "$DRY_RUN" == "true" ]]; then
    warn "DRY RUN - no changes were made"
    info "Run without --dry-run to perform actual rollback"
else
    success "Successfully rolled back release $VERSION"
fi

echo
log "Next steps:"
log "  1. Verify git status: git status"
log "  2. Check remote tags: git ls-remote --tags origin"
if [[ "$HAS_GH" == "true" ]]; then
    log "  3. Verify GitHub releases: gh release list"
fi
log "  4. If needed, rebuild: ./build.sh release"
