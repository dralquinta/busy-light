# 🚀 BusyLight Release Process

This guide describes how to create and publish a new version of BusyLight for macOS.

## 📋 Table of Contents

- [Quick Start](#quick-start)
- [Prerequisites](#prerequisites)
- [Release Process](#release-process)
- [Testing and Validation (Dry Run)](#testing-and-validation-dry-run)
- [Code Signing and Notarization](#code-signing-and-notarization)
- [GitHub Actions (CI)](#github-actions-ci)
- [Troubleshooting](#troubleshooting)

---

## Quick Start

To create a complete release (signed and published):

```bash
# 1. Prepare the release
git checkout main
git pull

# 2. Validate everything is ready (recommended)
./scripts/validate-release.sh

# 3. Run the release script (from project root)
./release.sh v1.0.0

# 4. Verify the DMG
open dist/BusyLight-1.0.0.dmg

# 5. Publish (push the tag)
git push origin v1.0.0
```

The script automates:
- ✅ Info.plist versioning
- ✅ Release mode compilation
- ✅ DMG creation with /Applications symlink and custom icon
- ✅ Developer ID signing (if configured)
- ✅ Apple notarization (if configured)
- ✅ GitHub Releases publication

---

## Prerequisites

### Required Tools

```bash
# Verify tool installation
swift --version        # Swift 6.0+
xcodebuild -version    # Xcode 15+ (for notarization)
gh --version           # GitHub CLI
codesign --version     # macOS command line tools
hdiutil --version      # macOS tools (pre-installed)
```

### Install Missing Tools

```bash
# GitHub CLI
brew install gh
gh auth login

# Xcode Command Line Tools
xcode-select --install

# Full Xcode (required for notarization)
# Download from Mac App Store
```

### Credentials Setup (Optional for Signing)

To sign and notarize the DMG, you need:

1. **Apple Developer Program**: Active account ($99/year)
2. **Developer ID Application Certificate**: Installed in Keychain
3. **Notarization Credentials**: Profile or Apple ID credentials

---

## Release Process

### 1. Preparation

```bash
# Ensure you're on the correct branch
git checkout main
git pull origin main

# Verify no uncommitted changes
git status

# Verify tests pass
./build.sh test

# Run comprehensive pre-release validation
./scripts/validate-release.sh
```

**What the validation script checks:**
- ✅ Git repository state (branch, uncommitted changes, untracked files)
- ✅ Build system readiness (Swift, Xcode, dependencies)
- ✅ Source code compilation
- ✅ Test suite execution
- ✅ Info.plist validity
- ✅ Documentation (README, CHANGELOG)
- ✅ Code signing setup (if configured)
- ✅ GitHub CLI authentication
- ✅ Release artifacts structure

**Exit codes:**
- `0` = All checks passed → Proceed with release
- `1` = Critical failures → Fix issues before releasing
- `2` = Warnings only → Can proceed with caution

> **💡 Tip:** Fix all critical issues before proceeding. Warnings can usually be ignored for development releases but should be addressed for production.

### 2. Choose Version Number

Use [Semantic Versioning](https://semver.org/):

- **MAJOR.MINOR.PATCH** (e.g., `v1.2.3`)
- **MAJOR.MINOR.PATCH-prerelease** (e.g., `v1.0.0-beta.1`)

Examples:
- `v1.0.0` - First stable version
- `v1.1.0` - New features (backwards compatible)
- `v1.0.1` - Bug fixes
- `v2.0.0` - Breaking changes
- `v1.0.0-beta.1` - Prerelease

### 3. Run Release

#### Option A: Complete Release (Signed and Published)

```bash
./release.sh v1.0.0
```

This will:
1. Create tag (if it doesn't exist)
2. Update versions in Info.plist
3. Build in Release mode
4. Sign with Developer ID
5. Notarize with Apple
6. Create DMG with custom icon
7. Publish to GitHub Releases

#### Option B: Release Without Signing (Development)

```bash
./release.sh v1.0.0 --skip-sign
```

Applies ad-hoc signature (for local testing only).

#### Option C: Dry Run (Don't Publish)

```bash
./release.sh v1.0.0 --dry-run
```

Generates DMG but does NOT publish to GitHub. Useful for testing.

#### Option D: No Signing and No Publishing

```bash
./release.sh v1.0.0 --skip-sign --dry-run
```

### 4. Verify DMG

```bash
# Open the DMG
open dist/BusyLight-1.0.0.dmg

# Verify contents:
# ✓ BusyLight.app is present
# ✓ /Applications link works
# ✓ App can be dragged to Applications
# ✓ Custom icon is visible

# Test installation
cp -R /Volumes/BusyLight/BusyLight.app /Applications/
open /Applications/BusyLight.app
```

### 5. Verify Signature (If Applicable)

```bash
# Verify app signature
codesign --verify --deep --strict --verbose=2 BusyLight.app

# Verify notarization
spctl --assess --verbose=2 BusyLight.app

# Verify stapling
xcrun stapler validate BusyLight.app
```

### 6. Publish the Tag

```bash
# Push tag to GitHub (triggers CI if configured)
git push origin v1.0.0
```

### 7. Verify GitHub Release

1. Go to `https://github.com/OWNER/busy-light/releases`
2. Verify the release is created
3. Verify the DMG is attached
4. Edit release notes if needed
5. Test DMG download

---

## Testing and Validation (Dry Run)

### Why Use Dry Run?

Before publishing to GitHub, use dry-run mode to:
- ✅ Test the build process without creating a release
- ✅ Verify DMG creation and signing
- ✅ Catch issues early before publishing
- ✅ Validate version numbers and metadata
- ✅ Test on local machine risk-free

### Pre-Release Validation

Run the validation script **before** creating a release:

```bash
./scripts/validate-release.sh
```

This checks:
- ✅ Git status (no uncommitted changes, correct branch)
- ✅ Build system (Swift, Xcode, dependencies)
- ✅ Source code builds successfully
- ✅ Tests pass
- ✅ Info.plist validity
- ✅ Version numbers
- ✅ Documentation (README, CHANGELOG)
- ✅ Code signing setup (if configured)
- ✅ GitHub CLI authentication
- ✅ Release artifacts

**Exit codes**:
- `0` = All checks passed
- `1` = Critical failures (must fix)
- `2` = Warnings only (can proceed)

### Dry Run Workflow

#### Step 1: Validate Environment

```bash
# Run pre-release validation
./scripts/validate-release.sh

# Fix any critical issues before proceeding
```

#### Step 2: Dry Run Without Signing

Test the build and DMG creation locally:

```bash
# Build and create DMG without signing or publishing
./release.sh v1.0.0 --skip-sign --dry-run
```

This will:
1. ✅ Update Info.plist versions
2. ✅ Build in Release mode
3. ✅ Apply ad-hoc signature (for local testing)
4. ✅ Create DMG with custom icon
5. ❌ Skip notarization
6. ❌ Skip GitHub publishing

#### Step 3: Verify the DMG

```bash
# Check DMG was created
ls -lh dist/BusyLight-1.0.0.dmg

# Mount and inspect
open dist/BusyLight-1.0.0.dmg

# Verify contents:
# ✓ BusyLight.app present
# ✓ /Applications symlink works
# ✓ Custom icon visible
# ✓ App can be dragged to Applications
```

#### Step 4: Test the App

```bash
# Copy to Applications
cp -R /Volumes/BusyLight/BusyLight.app /tmp/BusyLight.app

# Launch and test
open /tmp/BusyLight.app

# Verify:
# ✓ App launches without errors
# ✓ Menu bar icon appears
# ✓ Status menu works
# ✓ Calendar permission prompt (if first run)
# ✓ Hotkey registration works
# ✓ All features functional
```

#### Step 5: Dry Run With Signing (Optional)

If you have code signing configured, test the full signing process:

```bash
# Build, sign, and notarize but DON'T publish
./release.sh v1.0.0 --dry-run
```

This will:
1. ✅ Update Info.plist versions
2. ✅ Build in Release mode
3. ✅ Sign with Developer ID
4. ✅ Notarize with Apple (can take 5-15 minutes)
5. ✅ Staple notarization ticket
6. ✅ Create DMG
7. ❌ Skip GitHub publishing

**Verify signing and notarization**:

```bash
# Verify signature
codesign --verify --deep --strict --verbose=2 BusyLight.app
codesign -dvvv BusyLight.app

# Verify notarization
spctl --assess --verbose=2 --type execute BusyLight.app

# Verify stapling
xcrun stapler validate BusyLight.app

# Should see:
# "The validate action worked!"
```

#### Step 6: Clean Up Test Artifacts

```bash
# Remove test app
rm -rf /tmp/BusyLight.app

# Unmount DMG (force if necessary)
hdiutil detach /Volumes/BusyLight -force

# Optionally clean dist/ (will be recreated)
# rm -rf dist/

# Reset source Info.plist to default version (if not committing)
git checkout macos-agent/Sources/BusyLight/Resources/Info.plist
```

**Important:** The dry-run modifies the source `Info.plist` to stamp versions. After testing:
- **Option 1:** Reset it with `git checkout macos-agent/Sources/BusyLight/Resources/Info.plist`
- **Option 2:** Keep it for the actual release (skip this step)
- **Option 3:** Commit it if you want to track version in source control

### Testing Specific Scenarios

#### Test Version Stamping

Verify Info.plist is updated correctly:

```bash
# After dry run, check versions
plutil -p macos-agent/Sources/BusyLight/Resources/Info.plist | grep Version

# Should show:
# "CFBundleShortVersionString" => "1.0.0"
# "CFBundleVersion" => "1.0.0"
```

#### Test Pre-Release Versions

```bash
# Test beta release
./release.sh v1.0.0-beta.1 --skip-sign --dry-run

# Verify version in Info.plist
plutil -extract CFBundleVersion raw macos-agent/Sources/BusyLight/Resources/Info.plist
# Should output: 1.0.0-beta.1
```

#### Test DMG Customization

Verify the DMG has the custom icon:

```bash
# Mount DMG
hdiutil attach dist/BusyLight-1.0.0.dmg

# Check volume icon (should be custom busy-light-icon.png)
ls -la /Volumes/BusyLight/.VolumeIcon.icns

# Visual check: Open Finder and verify icon
open /Volumes/BusyLight
```

### Troubleshooting Dry Run Issues

#### Issue: "Version not updated in Info.plist"

**Diagnosis**:
```bash
plutil -p macos-agent/Sources/BusyLight/Resources/Info.plist | grep Version
```

**Solution**:
```bash
# Manually stamp version
plutil -replace CFBundleShortVersionString -string "1.0.0" macos-agent/Sources/BusyLight/Resources/Info.plist
plutil -replace CFBundleVersion -string "1.0.0" macos-agent/Sources/BusyLight/Resources/Info.plist
```

#### Issue: "DMG creation failed"

**Diagnosis**:
```bash
# Check if BusyLight.app exists
ls -la BusyLight.app

# Check disk space
df -h .

# Check for stuck DMG mounts
mount | grep BusyLight
```

**Solution**:
```bash
# Clean and rebuild
rm -rf BusyLight.app dist/
./build.sh release
./release.sh v1.0.0 --skip-sign --dry-run
```

#### Issue: "hdiutil: convert failed - Resource temporarily unavailable"

**Cause**: System hasn't fully released the temporary DMG file after unmounting

**This issue has been fixed**: The script now:
- Waits 3 seconds after unmounting before compression
- Syncs filesystem buffers
- Retries compression up to 3 times with delays
- Shows clear error messages

**If you still encounter this:**
```bash
# Clean up any temp DMG files
rm -f /tmp/temp-*.dmg

# Clean dist and retry
rm -rf dist/
./release.sh v1.0.0 --skip-sign --dry-run
```

#### Issue: "App doesn't launch after DMG install"

**Diagnosis**:
```bash
# Check executable permissions
ls -la /Volumes/BusyLight/BusyLight.app/Contents/MacOS/BusyLight

# Check bundle structure
tree /Volumes/BusyLight/BusyLight.app/Contents/
```

**Solution**:
```bash
# Ensure executable bit is set
chmod +x BusyLight.app/Contents/MacOS/BusyLight

# Rebuild DMG
rm dist/BusyLight-1.0.0.dmg
./release.sh v1.0.0 --skip-sign --dry-run
```

#### Issue: "Failed to unmount DMG after 5 attempts"

**Cause**: The Finder window customization (AppleScript) opens Finder, which locks the volume

**This issue has been fixed**: The script no longer performs Finder window customization to avoid this problem. The DMG will still have:
- ✅ Custom volume icon
- ✅ Applications symlink  
- ✅ All files accessible
- ⚠️ No custom window positioning (minor cosmetic feature)

**If you still encounter this issue:**

```bash
# Option 1: Quick fix - restart Finder and unmount
killall Finder && sleep 2 && diskutil unmount force /Volumes/BusyLight

# Option 2: Check what's holding the volume
lsof /Volumes/BusyLight

# Option 3: If an app is running from the DMG, kill it first
ps aux | grep BusyLight
# Then: kill -9 <PID>

# Option 4: Clean up and retry
rm -rf dist/BusyLight-*.dmg
./release.sh v1.0.0 --skip-sign --dry-run
```

#### Issue: "Modified files in git after dry-run"

**Cause**: Release script modifies source Info.plist and may leave build artifacts

**Solution**:
```bash
# Reset source Info.plist
git checkout macos-agent/Sources/BusyLight/Resources/Info.plist

# Clean build artifacts (now in .gitignore)
rm -rf BusyLight.app dist/

# Verify clean state
git status
```

### Complete Dry Run Checklist

Before publishing the actual release:

- [ ] Pre-release validation passed: `./scripts/validate-release.sh`
- [ ] Dry run completes successfully
- [ ] DMG created in `dist/` directory
- [ ] DMG mounts without errors
- [ ] App icon visible in DMG window
- [ ] /Applications symlink present
- [ ] App can be copied to /Applications
- [ ] App launches without errors
- [ ] Menu bar icon appears
- [ ] Status menu opens and works
- [ ] All features functional (calendar, hotkeys, etc.)
- [ ] No permission errors
- [ ] Version number correct in Info.plist
- [ ] Signature valid (if signed): `codesign --verify`
- [ ] Notarization OK (if notarized): `spctl --assess`

### Ready to Release?

Once dry run validation is complete:

```bash
# 1. Clean dry run artifacts (optional)
rm -rf dist/

# 2. Run actual release (creates and publishes to GitHub)
./release.sh v1.0.0

# 3. Push the tag
git push origin v1.0.0

# 4. Verify on GitHub
gh release view v1.0.0
```

---

## Code Signing and Notarization

### Why Sign and Notarize?

- **Signing**: Allows macOS to verify the code hasn't been modified
- **Notarization**: Apple verifies it doesn't contain known malware
- **Without signing/notarization**: Users will see security warnings

### Certificate Setup

#### 1. Obtain Developer ID Certificate

1. Go to [Apple Developer Portal](https://developer.apple.com/account/resources/certificates/list)
2. Create **Developer ID Application** certificate
3. Download and double-click to install in Keychain

#### 2. Verify Certificate

```bash
# List installed certificates
security find-identity -p codesigning -v

# Should show something like:
# 1) ABC123... "Developer ID Application: Your Name (TEAM_ID)"
```

### Notarization Setup

#### Option 1: Notarytool with Profile (Recommended)

```bash
# Create notarization profile
xcrun notarytool store-credentials "busylight-notarize" \
    --apple-id "your@email.com" \
    --team-id "YOUR_TEAM_ID" \
    --password "app-specific-password"

# Use profile in release
export NOTARIZATION_PROFILE="busylight-notarize"
./release.sh v1.0.0
```

**Advantages**: Credentials stored securely in Keychain

#### Option 2: Environment Variables

```bash
# Configure credentials
export APPLE_ID="your@email.com"
export APPLE_PASSWORD="app-specific-password"  # Create at appleid.apple.com
export APPLE_TEAM_ID="ABC1234567"

# Run release
./release.sh v1.0.0
```

#### Create App-Specific Password

1. Go to [appleid.apple.com](https://appleid.apple.com/)
2. Sign In
3. Security → App-Specific Passwords
4. Generate new password
5. Save in secure location

### Environment Variables for Signing

```bash
# ~/.zshrc or ~/.bashrc

# Signing identity (optional, defaults to "Developer ID Application")
export SIGNING_IDENTITY="Developer ID Application: Your Name"

# Notarization profile (recommended)
export NOTARIZATION_PROFILE="busylight-notarize"

# Or direct credentials (alternative)
export APPLE_ID="your@email.com"
export APPLE_PASSWORD="xxxx-xxxx-xxxx-xxxx"
export APPLE_TEAM_ID="ABC1234567"
```

---

## GitHub Actions (CI)

### Workflow Configuration

A GitHub Actions workflow is included in `.github/workflows/release.yml` that automates the release process.

#### 1. Configure Secrets

In GitHub: `Settings → Secrets and variables → Actions`

Add:
- `SIGNING_CERTIFICATE_P12_BASE64`: Certificate in base64
- `SIGNING_CERTIFICATE_PASSWORD`: Certificate password
- `APPLE_ID`: Your Apple ID
- `APPLE_PASSWORD`: App-specific password
- `APPLE_TEAM_ID`: Team ID

#### 2. Export Certificate (Local)

```bash
# Export certificate from Keychain
# 1. Open Keychain Access
# 2. Select "Developer ID Application" certificate
# 3. File → Export Items → .p12
# 4. Save with password

# Convert to base64
base64 -i DeveloperID.p12 -o DeveloperID.p12.base64

# Copy content of DeveloperID.p12.base64 to secret
cat DeveloperID.p12.base64 | pbcopy
```

#### 3. Trigger Release from CI

```bash
# Create and push tag
git tag v1.0.0
git push origin v1.0.0

# GitHub Actions will automatically:
# - Build the app
# - Sign and notarize
# - Create the DMG
# - Publish GitHub Release
```

### View CI Logs

1. Go to `Actions` tab in GitHub
2. Select workflow run
3. View detailed logs

---

## Troubleshooting

### Error: "No signing identity found"

**Cause**: No Developer ID certificate installed

**Solution**:
```bash
# Option 1: Install certificate (if you have one)
# Download from developer.apple.com and double-click

# Option 2: Release without signing
./release.sh v1.0.0 --skip-sign
```

### Error: "Notarization failed"

**Cause**: Incorrect credentials or app rejected

**Diagnosis**:
```bash
# View rejection details
xcrun notarytool log <submission-id> \
    --keychain-profile "busylight-notarize"
```

**Common solutions**:
- Verify certificate is "Developer ID Application" (not "Mac App Distribution")
- Verify all credentials are correct
- Review notarization log for specific details

### Error: "GitHub CLI not authenticated"

**Cause**: Haven't run `gh auth login`

**Solution**:
```bash
gh auth login
# Follow on-screen instructions
```

### Error: "DMG verification failed"

**Cause**: Problem creating the DMG

**Solution**:
```bash
# Clean and retry
rm -rf dist/
./release.sh v1.0.0
```

### Error: "Working directory has uncommitted changes"

**Cause**: Modified files in git

**Solution**:
```bash
# Option 1: Commit changes
git add .
git commit -m "Prepare release"

# Option 2: Stash changes
git stash

# Option 3: Continue anyway (not recommended)
# Script will ask for confirmation
```

### Warning: "Signed but not notarized"

**Cause**: No notarization credentials configured

**Effect**: DMG is signed but users will see warnings on macOS

**Solution for future releases**:
- Configure notarization profile (see section above)
- Or use unsigned release for development: `--skip-sign`

### Error: "codesign: code object is not signed at all"

**Cause**: App doesn't have valid signature

**Solution**:
```bash
# Verify build.sh completed correctly
./build.sh release

# Verify BusyLight.app exists
ls -la BusyLight.app

# Try manual signing
codesign --force --deep --sign - BusyLight.app
```

### DMG Mounts But App Doesn't Work

**Diagnosis**:
```bash
# Verify permissions
ls -la /Volumes/BusyLight/BusyLight.app/Contents/MacOS/

# Verify bundle structure
tree /Volumes/BusyLight/BusyLight.app

# Verify Info.plist
plutil -lint /Volumes/BusyLight/BusyLight.app/Contents/Info.plist
```

**Solutions**:
- Verify `BusyLight.app/Contents/MacOS/BusyLight` is executable
- Verify `Info.plist` is present and valid
- Rebuild with `./build.sh release`

---

## Release Checklist

Before publishing:

- [ ] Pre-release validation passed: `./scripts/validate-release.sh`
- [ ] Tests pass: `./build.sh test`
- [ ] Version number is correct
- [ ] CHANGELOG.md updated (if applicable)
- [ ] No uncommitted changes
- [ ] DMG mounts correctly
- [ ] App can be copied to /Applications
- [ ] App launches without errors
- [ ] Calendar permission works
- [ ] Signature verified (if applicable): `codesign --verify`
- [ ] Notarization OK (if applicable): `spctl --assess`
- [ ] Release notes are clear
- [ ] Tag pushed to GitHub

After publishing:

- [ ] Verify release on GitHub
- [ ] Download DMG from GitHub
- [ ] Test installation on clean machine
- [ ] Update documentation if anything changed
- [ ] Announce release (if applicable)

---

## Command Reference

### Main Script

```bash
# Help
./release.sh

# Complete release
./release.sh v1.0.0

# Without signing
./release.sh v1.0.0 --skip-sign

# Without publishing (dry-run)
./release.sh v1.0.0 --dry-run

# Build only (no publish or sign)
./release.sh v1.0.0 --skip-sign --dry-run
```

### macOS Tools

```bash
# Verify signature
codesign --verify --deep --strict BusyLight.app
codesign -dvvv BusyLight.app

# Verify notarization
spctl --assess --verbose=2 BusyLight.app
xcrun stapler validate BusyLight.app

# View certificates
security find-identity -p codesigning -v

# Verify DMG
hdiutil verify dist/BusyLight-1.0.0.dmg

# Mount DMG
hdiutil attach dist/BusyLight-1.0.0.dmg
```

### Git Tags

```bash
# List tags
git tag -l

# View tag details
git show v1.0.0

# Create tag
git tag -a v1.0.0 -m "Release v1.0.0"

# Delete tag (local)
git tag -d v1.0.0

# Delete tag (remote)
git push origin :refs/tags/v1.0.0

# Push tag
git push origin v1.0.0

# Push all tags
git push origin --tags
```

### GitHub CLI

```bash
# View release
gh release view v1.0.0

# List releases
gh release list

# Delete release
gh release delete v1.0.0 --yes

# Download asset
gh release download v1.0.0

# Edit release notes
gh release edit v1.0.0
```

---

## Additional Resources

- [Apple Code Signing Guide](https://developer.apple.com/support/code-signing/)
- [Notarization Documentation](https://developer.apple.com/documentation/security/notarizing_macos_software_before_distribution)
- [GitHub Releases Documentation](https://docs.github.com/en/repositories/releasing-projects-on-github)
- [Semantic Versioning](https://semver.org/)
- [GitHub CLI Documentation](https://cli.github.com/manual/)

---

## Support

Problems with the release process?

1. Review this documentation
2. Search in [Issues](https://github.com/dralquinta/busy-light/issues)
3. Create new issue with details and logs
