#!/usr/bin/env bash
# validate-release.sh — Pre-release validation checks
#
# Usage:
#   ./scripts/validate-release.sh [version]
#
# Performs comprehensive checks before releasing:
#   - Git repository state
#   - Build system health
#   - Code quality (if tools available)
#   - Test suite
#   - Documentation
#   - Version consistency
#
# Exit codes:
#   0 - All checks passed
#   1 - Critical failures (must fix)
#   2 - Warnings (can proceed with caution)

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

# Counters
ERRORS=0
WARNINGS=0
CHECKS=0

section() {
    echo
    echo -e "${BOLD}${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${BOLD}${BLUE}  $*${NC}"
    echo -e "${BOLD}${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo
}

check_pass() {
    echo -e "${GREEN}✓${NC} $*"
    ((CHECKS++))
}

check_fail() {
    echo -e "${RED}✗${NC} $*"
    ((ERRORS++))
    ((CHECKS++))
}

check_warn() {
    echo -e "${YELLOW}⚠${NC} $*"
    ((WARNINGS++))
    ((CHECKS++))
}

info() {
    echo -e "${BLUE}ℹ${NC} $*"
}

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# Check Functions
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

check_git_state() {
    section "Git Repository State"
    
    # Check if in git repo
    if ! git rev-parse --git-dir &>/dev/null; then
        check_fail "Not in a git repository"
        return
    fi
    check_pass "Git repository detected"
    
    # Check for uncommitted changes
    if [[ -n "$(git status --porcelain)" ]]; then
        check_warn "Uncommitted changes detected"
        git status --short | head -10
    else
        check_pass "Working directory is clean"
    fi
    
    # Check current branch
    local branch
    branch=$(git branch --show-current)
    if [[ "$branch" != "main" ]] && [[ "$branch" != "master" ]]; then
        check_warn "Not on main/master branch (current: $branch)"
    else
        check_pass "On main branch: $branch"
    fi
    
    # Check if up to date with remote
    git fetch &>/dev/null || true
    local local_commit
    local remote_commit
    local_commit=$(git rev-parse HEAD)
    remote_commit=$(git rev-parse @{u} 2>/dev/null || echo "")
    
    if [[ -n "$remote_commit" ]] && [[ "$local_commit" != "$remote_commit" ]]; then
        check_warn "Local branch differs from remote"
    elif [[ -n "$remote_commit" ]]; then
        check_pass "In sync with remote"
    fi
    
    # Check for tags
    local tag_count
    tag_count=$(git tag -l | wc -l | tr -d ' ')
    info "Found $tag_count existing tags"
}

check_dependencies() {
    section "Build Dependencies"
    
    # Swift
    if command -v swift &>/dev/null; then
        local swift_version
        swift_version=$(swift --version 2>&1 | head -1)
        check_pass "Swift: $swift_version"
    else
        check_fail "Swift not found"
    fi
    
    # Xcode
    if command -v xcodebuild &>/dev/null; then
        local xcode_version
        xcode_version=$(xcodebuild -version 2>&1 | head -1)
        check_pass "Xcode: $xcode_version"
    else
        check_warn "Xcode not found (required for notarization)"
    fi
    
    # GitHub CLI
    if command -v gh &>/dev/null; then
        if gh auth status &>/dev/null; then
            check_pass "GitHub CLI: authenticated"
        else
            check_warn "GitHub CLI: not authenticated"
        fi
    else
        check_warn "GitHub CLI not found (required for publishing)"
    fi
    
    # Code signing tools
    if command -v codesign &>/dev/null; then
        check_pass "codesign available"
    else
        check_fail "codesign not found"
    fi
    
    # DMG creation tools
    if command -v hdiutil &>/dev/null; then
        check_pass "hdiutil available"
    else
        check_fail "hdiutil not found"
    fi
}

check_build() {
    section "Build System"
    
    cd "$PROJECT_ROOT"
    
    # Check build script exists
    if [[ -f "build.sh" ]]; then
        check_pass "build.sh found"
    else
        check_fail "build.sh not found"
        return
    fi
    
    # Check Package.swift
    if [[ -f "macos-agent/Package.swift" ]]; then
        check_pass "Package.swift found"
    else
        check_fail "Package.swift not found"
        return
    fi
    
    # Try to build
    info "Running test build..."
    if ./build.sh release &>/dev/null; then
        check_pass "Release build successful"
        
        # Check if app bundle was created
        if [[ -d "BusyLight.app" ]]; then
            check_pass "App bundle created"
            
            # Check Info.plist
            if [[ -f "BusyLight.app/Contents/Info.plist" ]]; then
                check_pass "Info.plist present"
                
                # Validate plist
                if plutil -lint "BusyLight.app/Contents/Info.plist" &>/dev/null; then
                    check_pass "Info.plist is valid"
                else
                    check_fail "Info.plist validation failed"
                fi
            else
                check_fail "Info.plist missing"
            fi
        else
            check_fail "App bundle not created"
        fi
    else
        check_fail "Release build failed"
    fi
}

check_tests() {
    section "Test Suite"
    
    cd "$PROJECT_ROOT"
    
    # Check if tests exist
    if [[ -d "macos-agent/Tests" ]]; then
        check_pass "Test directory found"
        
        # Count test files
        local test_count
        test_count=$(find macos-agent/Tests -name "*Tests.swift" | wc -l | tr -d ' ')
        info "Found $test_count test files"
        
        # Try to run tests (if Xcode available)
        if command -v xcodebuild &>/dev/null; then
            info "Running test suite..."
            if ./build.sh test &>/dev/null; then
                check_pass "All tests passed"
            else
                check_fail "Tests failed"
            fi
        else
            check_warn "Xcode not available, skipping test execution"
        fi
    else
        check_warn "No test directory found"
    fi
}

check_code_quality() {
    section "Code Quality"
    
    # SwiftLint (optional)
    if command -v swiftlint &>/dev/null; then
        info "Running SwiftLint..."
        if swiftlint lint --quiet 2>/dev/null; then
            check_pass "SwiftLint: no issues"
        else
            check_warn "SwiftLint found issues"
        fi
    else
        info "SwiftLint not installed (optional)"
    fi
    
    # SwiftFormat (optional)
    if command -v swiftformat &>/dev/null; then
        info "Checking Swift formatting..."
        if swiftformat --lint . &>/dev/null; then
            check_pass "Swift formatting correct"
        else
            check_warn "Code formatting issues detected"
        fi
    else
        info "SwiftFormat not installed (optional)"
    fi
    
    # Check for TODO/FIXME comments
    local todo_count
    todo_count=$(grep -r "TODO\|FIXME" --include="*.swift" macos-agent/ 2>/dev/null | wc -l | tr -d ' ')
    if [[ "$todo_count" -gt 0 ]]; then
        check_warn "Found $todo_count TODO/FIXME comments"
    else
        check_pass "No TODO/FIXME comments"
    fi
}

check_documentation() {
    section "Documentation"
    
    # README
    if [[ -f "$PROJECT_ROOT/README.md" ]]; then
        check_pass "README.md exists"
        
        # Check README size
        local readme_size
        readme_size=$(wc -l < "$PROJECT_ROOT/README.md")
        if [[ $readme_size -gt 50 ]]; then
            check_pass "README is substantial ($readme_size lines)"
        else
            check_warn "README is short ($readme_size lines)"
        fi
    else
        check_fail "README.md missing"
    fi
    
    # CHANGELOG
    if [[ -f "$PROJECT_ROOT/CHANGELOG.md" ]]; then
        check_pass "CHANGELOG.md exists"
    else
        check_warn "CHANGELOG.md missing"
    fi
    
    # LICENSE
    if [[ -f "$PROJECT_ROOT/LICENSE" ]] || [[ -f "$PROJECT_ROOT/LICENSE.md" ]]; then
        check_pass "LICENSE file exists"
    else
        check_warn "LICENSE file missing"
    fi
    
    # Documentation directory
    if [[ -d "$PROJECT_ROOT/docs" ]]; then
        local doc_count
        doc_count=$(find "$PROJECT_ROOT/docs" -name "*.md" | wc -l | tr -d ' ')
        check_pass "Documentation directory exists ($doc_count files)"
    else
        check_warn "No docs directory"
    fi
}

check_version_consistency() {
    section "Version Consistency"
    
    local version="${1:-}"
    
    if [[ -z "$version" ]]; then
        info "No version specified, skipping version checks"
        return
    fi
    
    # Normalize version
    version="${version#v}"
    
    # Check Info.plist version
    local plist="$PROJECT_ROOT/macos-agent/Sources/BusyLight/Resources/Info.plist"
    if [[ -f "$plist" ]]; then
        local plist_version
        plist_version=$(plutil -extract CFBundleShortVersionString raw "$plist" 2>/dev/null || echo "")
        
        if [[ "$plist_version" == "${version%%-*}" ]]; then
            check_pass "Info.plist version matches: $plist_version"
        else
            check_warn "Info.plist version mismatch: $plist_version vs $version"
        fi
    else
        check_fail "Info.plist not found"
    fi
    
    # Check if tag already exists
    if git rev-parse "v$version" &>/dev/null; then
        check_warn "Tag v$version already exists"
    else
        check_pass "Tag v$version is available"
    fi
}

check_assets() {
    section "Release Assets"
    
    # Check icon
    if [[ -f "$PROJECT_ROOT/img/busy-light-icon.png" ]]; then
        check_pass "App icon found"
    else
        check_fail "App icon missing: img/busy-light-icon.png"
    fi
    
    # Check if DMG background exists or can be created
    if [[ -f "$PROJECT_ROOT/img/dmg-background.png" ]]; then
        check_pass "DMG background found"
    else
        check_warn "DMG background not found (will use default)"
    fi
    
    # Check release script
    if [[ -f "$PROJECT_ROOT/release.sh" ]]; then
        if [[ -x "$PROJECT_ROOT/release.sh" ]]; then
            check_pass "release.sh is executable"
        else
            check_warn "release.sh is not executable"
        fi
    else
        check_fail "release.sh not found"
    fi
}

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# Main
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

main() {
    local version="${1:-}"
    
    echo -e "${BOLD}BusyLight Release Validation${NC}"
    echo
    
    if [[ -n "$version" ]]; then
        info "Target version: $version"
    fi
    
    # Run all checks
    check_git_state
    check_dependencies
    check_build
    check_tests
    check_code_quality
    check_documentation
    check_version_consistency "$version"
    check_assets
    
    # Summary
    section "Validation Summary"
    
    echo "Total checks: $CHECKS"
    echo -e "${GREEN}Passed:${NC} $((CHECKS - ERRORS - WARNINGS))"
    echo -e "${YELLOW}Warnings:${NC} $WARNINGS"
    echo -e "${RED}Errors:${NC} $ERRORS"
    echo
    
    # Determine exit code
    if [[ $ERRORS -gt 0 ]]; then
        echo -e "${RED}${BOLD}✗ Validation FAILED${NC}"
        echo "Please fix errors before releasing."
        exit 1
    elif [[ $WARNINGS -gt 0 ]]; then
        echo -e "${YELLOW}${BOLD}⚠ Validation PASSED with warnings${NC}"
        echo "You can proceed but consider addressing warnings."
        exit 2
    else
        echo -e "${GREEN}${BOLD}✓ Validation PASSED${NC}"
        echo "Ready to release!"
        exit 0
    fi
}

main "$@"
