#!/usr/bin/env bash
# generate-changelog.sh — Generate or update CHANGELOG.md from git history
#
# Usage:
#   ./scripts/generate-changelog.sh [version]
#
# Arguments:
#   version    Optional: specific version to generate (e.g., v1.0.0)
#              If omitted, generates from last tag to HEAD
#
# Features:
#   - Auto-categorizes commits (feat:, fix:, docs:, etc.)
#   - Generates markdown formatted changelog
#   - Preserves manual entries
#   - Links to commits and PRs

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
CHANGELOG_FILE="$PROJECT_ROOT/CHANGELOG.md"

# Colors
if [[ -t 1 ]]; then
    GREEN='\033[0;32m'
    BLUE='\033[0;34m'
    YELLOW='\033[1;33m'
    NC='\033[0m'
else
    GREEN='' BLUE='' YELLOW='' NC=''
fi

log() { echo -e "${GREEN}▸${NC} $*"; }
info() { echo -e "${BLUE}ℹ${NC} $*"; }
warn() { echo -e "${YELLOW}⚠${NC} $*"; }

# Get repository URL
get_repo_url() {
    local url
    url=$(git config --get remote.origin.url || echo "")
    # Convert SSH to HTTPS
    url="${url/git@github.com:/https://github.com/}"
    url="${url%.git}"
    echo "$url"
}

# Get previous tag
get_previous_tag() {
    local current_tag="$1"
    if [[ -n "$current_tag" ]]; then
        git describe --tags --abbrev=0 "$current_tag^" 2>/dev/null || echo ""
    else
        git describe --tags --abbrev=0 2>/dev/null || echo ""
    fi
}

# Categorize commit message
categorize_commit() {
    local msg="$1"
    local category=""
    
    if [[ "$msg" =~ ^feat(\(.*\))?:\ .+ ]]; then
        category="Added"
    elif [[ "$msg" =~ ^fix(\(.*\))?:\ .+ ]]; then
        category="Fixed"
    elif [[ "$msg" =~ ^docs(\(.*\))?:\ .+ ]]; then
        category="Documentation"
    elif [[ "$msg" =~ ^style(\(.*\))?:\ .+ ]]; then
        category="Style"
    elif [[ "$msg" =~ ^refactor(\(.*\))?:\ .+ ]]; then
        category="Changed"
    elif [[ "$msg" =~ ^perf(\(.*\))?:\ .+ ]]; then
        category="Performance"
    elif [[ "$msg" =~ ^test(\(.*\))?:\ .+ ]]; then
        category="Tests"
    elif [[ "$msg" =~ ^build(\(.*\))?:\ .+ ]]; then
        category="Build"
    elif [[ "$msg" =~ ^ci(\(.*\))?:\ .+ ]]; then
        category="CI/CD"
    elif [[ "$msg" =~ ^chore(\(.*\))?:\ .+ ]]; then
        category="Maintenance"
    elif [[ "$msg" =~ ^(breaking|BREAKING)[ :]+ ]]; then
        category="Breaking"
    else
        category="Other"
    fi
    
    echo "$category"
}

# Clean commit message (remove conventional commit prefix)
clean_message() {
    local msg="$1"
    # Remove conventional commit prefix
    msg=$(echo "$msg" | sed -E 's/^(feat|fix|docs|style|refactor|perf|test|build|ci|chore|breaking|BREAKING)(\([^)]+\))?:[ ]*//')
    # Capitalize first letter
    msg="$(echo "${msg:0:1}" | tr '[:lower:]' '[:upper:]')${msg:1}"
    echo "$msg"
}

# Generate changelog section for a version
generate_version_section() {
    local version="$1"
    local prev_tag="$2"
    local repo_url="$3"
    local date
    date=$(git log -1 --format=%ai "$version" 2>/dev/null | cut -d' ' -f1 || date +%Y-%m-%d)
    
    # Get commit range
    local range
    if [[ -n "$prev_tag" ]]; then
        range="$prev_tag..$version"
    else
        range="$version"
    fi
    
    info "Generating changelog for $version (from $range)"
    
    # Get all commits
    local commits
    commits=$(git log --pretty=format:"%H|||%s|||%an" "$range" 2>/dev/null || echo "")
    
    if [[ -z "$commits" ]]; then
        warn "No commits found for range $range"
        return
    fi
    
    # Parse and categorize commits
    declare -A categories
    categories=(
        ["Breaking"]=""
        ["Added"]=""
        ["Changed"]=""
        ["Deprecated"]=""
        ["Removed"]=""
        ["Fixed"]=""
        ["Security"]=""
        ["Performance"]=""
        ["Documentation"]=""
        ["Tests"]=""
        ["Build"]=""
        ["CI/CD"]=""
        ["Maintenance"]=""
        ["Other"]=""
    )
    
    while IFS='|||' read -r hash subject author; do
        # Skip merge commits
        [[ "$subject" =~ ^Merge ]] && continue
        
        local category
        category=$(categorize_commit "$subject")
        local clean_msg
        clean_msg=$(clean_message "$subject")
        
        # Create link to commit
        local link=""
        if [[ -n "$repo_url" ]]; then
            link=" ([${hash:0:7}]($repo_url/commit/$hash))"
        fi
        
        # Add to category
        categories[$category]+="- $clean_msg$link"$'\n'
    done <<< "$commits"
    
    # Generate markdown
    echo ""
    echo "## [$version] - $date"
    echo ""
    
    # Print categories in order (only non-empty ones)
    for category in "Breaking" "Added" "Changed" "Deprecated" "Removed" "Fixed" "Security" "Performance" "Documentation" "Tests" "Build" "CI/CD" "Maintenance" "Other"; do
        if [[ -n "${categories[$category]}" ]]; then
            echo "### $category"
            echo ""
            echo -n "${categories[$category]}"
            echo ""
        fi
    done
    
    # Add comparison link
    if [[ -n "$prev_tag" ]] && [[ -n "$repo_url" ]]; then
        echo "[Full changelog]($repo_url/compare/$prev_tag...$version)"
        echo ""
    fi
}

# Main function
main() {
    local target_version="${1:-}"
    
    log "Generating changelog..."
    
    # Check if in git repo
    if ! git rev-parse --git-dir &>/dev/null; then
        echo "Error: Not in a git repository"
        exit 1
    fi
    
    local repo_url
    repo_url=$(get_repo_url)
    if [[ -n "$repo_url" ]]; then
        info "Repository: $repo_url"
    fi
    
    # Create backup of existing changelog
    if [[ -f "$CHANGELOG_FILE" ]]; then
        cp "$CHANGELOG_FILE" "$CHANGELOG_FILE.bak"
        log "Created backup: $CHANGELOG_FILE.bak"
    fi
    
    # Read header (everything before auto-generated marker)
    local header=""
    if [[ -f "$CHANGELOG_FILE" ]]; then
        header=$(sed '/^<!-- Release entries will be auto-generated below this line -->/q' "$CHANGELOG_FILE")
    else
        # Create default header
        header="# Changelog

All notable changes to BusyLight will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added
- Initial release

---

<!-- Release entries will be auto-generated below this line -->"
    fi
    
    # Start new changelog
    echo "$header" > "$CHANGELOG_FILE"
    echo "" >> "$CHANGELOG_FILE"
    
    # Generate sections
    if [[ -n "$target_version" ]]; then
        # Generate for specific version
        local prev_tag
        prev_tag=$(get_previous_tag "$target_version")
        generate_version_section "$target_version" "$prev_tag" "$repo_url" >> "$CHANGELOG_FILE"
    else
        # Generate for all tags
        local tags
        tags=$(git tag -l --sort=-version:refname | grep -E '^v[0-9]+\.[0-9]+\.[0-9]+' || echo "")
        
        if [[ -z "$tags" ]]; then
            info "No version tags found (looking for vX.Y.Z format)"
            echo "## [0.0.0] - Unreleased" >> "$CHANGELOG_FILE"
            echo "" >> "$CHANGELOG_FILE"
            echo "No releases yet." >> "$CHANGELOG_FILE"
            echo "" >> "$CHANGELOG_FILE"
        else
            local prev_tag=""
            while read -r tag; do
                if [[ -n "$tag" ]]; then
                    generate_version_section "$tag" "$prev_tag" "$repo_url" >> "$CHANGELOG_FILE"
                    prev_tag="$tag"
                fi
            done <<< "$tags"
        fi
    fi
    
    # Add footer links
    echo "" >> "$CHANGELOG_FILE"
    echo "---" >> "$CHANGELOG_FILE"
    echo "" >> "$CHANGELOG_FILE"
    
    if [[ -n "$repo_url" ]]; then
        echo "<!-- Version comparison links -->" >> "$CHANGELOG_FILE"
        local tags
        tags=$(git tag -l --sort=-version:refname | grep -E '^v[0-9]+\.[0-9]+\.[0-9]+' || echo "")
        
        if [[ -n "$tags" ]]; then
            local prev_tag=""
            while read -r tag; do
                if [[ -n "$tag" ]]; then
                    if [[ -n "$prev_tag" ]]; then
                        echo "[$tag]: $repo_url/compare/$prev_tag...$tag" >> "$CHANGELOG_FILE"
                    else
                        echo "[$tag]: $repo_url/releases/tag/$tag" >> "$CHANGELOG_FILE"
                    fi
                    prev_tag="$tag"
                fi
            done <<< "$tags"
        fi
        
        echo "[Unreleased]: $repo_url/compare/$(git describe --tags --abbrev=0 2>/dev/null || echo 'HEAD')...HEAD" >> "$CHANGELOG_FILE"
    fi
    
    log "✓ Changelog generated: $CHANGELOG_FILE"
    
    # Show summary
    local entry_count
    entry_count=$(grep -c '^## \[' "$CHANGELOG_FILE" || echo "0")
    info "Generated $entry_count version entries"
    
    # Clean up backup
    rm -f "$CHANGELOG_FILE.bak"
}

# Run
main "$@"
