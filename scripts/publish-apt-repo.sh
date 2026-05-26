#!/usr/bin/env bash
#
# APT Repository Publisher for jpeg_exif_stripper
# Usage: ./scripts/publish-apt-repo.sh [--push]
#
# Maintains a Debian/Ubuntu APT repository hosted on the 'gh-pages' branch of
# this GitHub repository, served free via GitHub Pages. After each release, run
# this script to add the new .deb to the repository index and push the update.
#
# ─── ONE-TIME SETUP ──────────────────────────────────────────────────────────
#
#  1. Enable GitHub Pages for this repo:
#       GitHub repo → Settings → Pages → Source: Deploy from a branch
#       Branch: gh-pages / root (or /apt if you prefer a subfolder)
#       Save. GitHub will serve https://pommersche92.github.io/jpeg_exif_stripper/
#
#  2. Create a GPG key for signing (skip if you already have one):
#       gpg --full-generate-key
#       # Choose: RSA, 4096 bits, no expiry, enter your name/email
#
#  3. Note your GPG key fingerprint:
#       gpg --list-secret-keys --keyid-format LONG
#       # Example output: sec rsa4096/ABCDEF1234567890
#       # Your key ID is: ABCDEF1234567890
#
#  4. Export the public key so users can trust the repo:
#       This script handles it automatically when GPG_KEY_ID is set.
#
#  5. Set your key ID in your shell environment (add to ~/.bashrc or ~/.zshrc):
#       export GPG_KEY_ID="ABCDEF1234567890"
#
#  6. Create the gh-pages orphan branch (one-time, only if it doesn't exist):
#       git checkout --orphan gh-pages
#       git rm -rf .
#       git commit --allow-empty -m "Initial gh-pages branch"
#       git push origin gh-pages
#       git checkout main   # or your default branch
#
#  7. Tell users how to add the repo (after first publish):
#       # Add GPG key
#       curl -fsSL https://pommersche92.github.io/jpeg_exif_stripper/KEY.gpg \
#           | sudo gpg --dearmor -o /usr/share/keyrings/jpeg-exif-stripper.gpg
#       # Add repository source
#       echo "deb [arch=amd64 signed-by=/usr/share/keyrings/jpeg-exif-stripper.gpg] \
#           https://pommersche92.github.io/jpeg_exif_stripper stable main" \
#           | sudo tee /etc/apt/sources.list.d/jpeg-exif-stripper.list
#       # Install
#       sudo apt-get update && sudo apt-get install jpeg-exif-stripper
#
# ─── PREREQUISITES ───────────────────────────────────────────────────────────
#
#   sudo apt install dpkg-dev gnupg
#
# ─────────────────────────────────────────────────────────────────────────────

set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CARGO_TOML="${PROJECT_ROOT}/Cargo.toml"
DIST_DIR="${PROJECT_ROOT}/target/dist"
WORKTREE_DIR="${PROJECT_ROOT}/target/apt-repo-worktree"

PUSH=false

while [[ $# -gt 0 ]]; do
    case $1 in
        --push)
            PUSH=true
            shift
            ;;
        -h|--help)
            echo "Usage: $0 [--push]"
            echo ""
            echo "Builds the APT repository index from .deb files in target/dist/"
            echo "and updates the gh-pages branch."
            echo ""
            echo "Options:"
            echo "  --push    Commit and push the updated index to gh-pages (default: dry-run)"
            echo ""
            echo "Environment variables:"
            echo "  GPG_KEY_ID    GPG key fingerprint or email used for signing (required for signed repo)"
            exit 0
            ;;
        *)
            echo -e "${RED}Unknown option: $1${NC}"
            exit 1
            ;;
    esac
done

log_info()    { echo -e "${BLUE}ℹ${NC} $1" >&2; }
log_success() { echo -e "${GREEN}✓${NC} $1" >&2; }
log_warning() { echo -e "${YELLOW}⚠${NC} $1" >&2; }
log_error()   { echo -e "${RED}✗${NC} $1" >&2; }
log_step()    { echo -e "${CYAN}${BOLD}▶ $1${NC}" >&2; }

get_version() {
    grep '^version = ' "$CARGO_TOML" | head -n1 | sed 's/version = "\(.*\)"/\1/'
}

check_deps() {
    local missing=()
    command -v dpkg-scanpackages &>/dev/null || missing+=(dpkg-scanpackages)
    command -v gpg              &>/dev/null || missing+=(gpg)
    command -v git              &>/dev/null || missing+=(git)
    command -v gzip             &>/dev/null || missing+=(gzip)

    if [ "${#missing[@]}" -gt 0 ]; then
        log_error "Missing dependencies: ${missing[*]}"
        log_error "Install with: sudo apt install dpkg-dev gnupg"
        exit 1
    fi
}

# Set up the gh-pages worktree in a temp location inside target/
setup_worktree() {
    # Clean up any stale worktree registration
    git -C "$PROJECT_ROOT" worktree prune 2>/dev/null || true

    if [ -d "$WORKTREE_DIR" ]; then
        log_info "Removing existing worktree..."
        git -C "$PROJECT_ROOT" worktree remove --force "$WORKTREE_DIR" 2>/dev/null || \
            rm -rf "$WORKTREE_DIR"
    fi

    log_step "Setting up gh-pages worktree..."

    if git -C "$PROJECT_ROOT" ls-remote --exit-code origin gh-pages &>/dev/null; then
        git -C "$PROJECT_ROOT" worktree add "$WORKTREE_DIR" gh-pages
        log_success "Checked out gh-pages branch"
    else
        log_warning "gh-pages branch does not exist on origin"
        log_info "Creating orphan gh-pages branch..."
        git -C "$PROJECT_ROOT" worktree add --orphan -b gh-pages "$WORKTREE_DIR"
        # Remove any files that may have been added by worktree init
        rm -f "${WORKTREE_DIR}"/* 2>/dev/null || true
        log_success "Created new orphan gh-pages branch"
    fi
}

teardown_worktree() {
    git -C "$PROJECT_ROOT" worktree remove --force "$WORKTREE_DIR" 2>/dev/null || true
    git -C "$PROJECT_ROOT" worktree prune 2>/dev/null || true
}

# Copy all .deb files from target/dist/ into the APT pool structure
populate_pool() {
    local repo_root="$1"
    local deb_pkg_name="jpeg-exif-stripper"
    local pool_dir="${repo_root}/pool/main/j/${deb_pkg_name}"

    mkdir -p "$pool_dir"

    local deb_count=0
    local f
    for f in "${DIST_DIR}"/*.deb; do
        [ -f "$f" ] || continue
        cp "$f" "$pool_dir/"
        log_info "  + $(basename "$f")"
        (( deb_count++ )) || true
    done

    if [ "$deb_count" -eq 0 ]; then
        log_error "No .deb files found in ${DIST_DIR}/"
        log_error "Run ./scripts/build-deb.sh first, or ./scripts/release-github.sh"
        exit 1
    fi

    log_success "Copied $deb_count .deb file(s) to pool"
}

build_packages_index() {
    local repo_root="$1"
    local binary_dir="${repo_root}/dists/stable/main/binary-amd64"

    mkdir -p "$binary_dir"

    log_step "Generating Packages index..."
    cd "$repo_root"
    dpkg-scanpackages --arch amd64 pool/main > "${binary_dir}/Packages"
    gzip -k -f "${binary_dir}/Packages"
    log_success "Packages index generated"
}

create_release_file() {
    local repo_root="$1"
    local dist_dir="${repo_root}/dists/stable"
    local packages_file="${dist_dir}/main/binary-amd64/Packages"
    local packages_gz="${dist_dir}/main/binary-amd64/Packages.gz"
    local release_file="${dist_dir}/Release"

    log_step "Creating Release file..."

    local date
    date=$(date -Ru)

    local pkgs_md5 pkgs_sha256 pkgs_size
    local pkgz_md5 pkgz_sha256 pkgz_size

    pkgs_md5=$(md5sum   "$packages_file" | awk '{print $1}')
    pkgs_sha256=$(sha256sum "$packages_file" | awk '{print $1}')
    pkgs_size=$(stat -c%s "$packages_file")

    pkgz_md5=$(md5sum   "$packages_gz" | awk '{print $1}')
    pkgz_sha256=$(sha256sum "$packages_gz" | awk '{print $1}')
    pkgz_size=$(stat -c%s "$packages_gz")

    cat > "$release_file" << RELEASE
Origin: jpeg-exif-stripper
Label: jpeg-exif-stripper
Suite: stable
Codename: stable
Date: ${date}
Architectures: amd64
Components: main
Description: jpeg-exif-stripper APT repository
MD5Sum:
 ${pkgs_md5} ${pkgs_size} main/binary-amd64/Packages
 ${pkgz_md5} ${pkgz_size} main/binary-amd64/Packages.gz
SHA256:
 ${pkgs_sha256} ${pkgs_size} main/binary-amd64/Packages
 ${pkgz_sha256} ${pkgz_size} main/binary-amd64/Packages.gz
RELEASE

    log_success "Release file created"
}

sign_release() {
    local repo_root="$1"
    local release_file="${repo_root}/dists/stable/Release"

    if [ -z "${GPG_KEY_ID:-}" ]; then
        log_warning "GPG_KEY_ID not set — skipping GPG signing"
        log_warning "Users will need to add [trusted=yes] to their sources.list entry"
        log_warning "To sign: export GPG_KEY_ID=<your-key-id> and re-run"
        return 0
    fi

    log_step "Signing Release with GPG key: ${GPG_KEY_ID}..."

    # Detached ASCII-armored signature (Release.gpg)
    gpg --default-key "$GPG_KEY_ID" \
        --armor --detach-sign \
        --output "${release_file}.gpg" \
        "$release_file"

    # Inline clear-signed file (InRelease — preferred by modern apt)
    gpg --default-key "$GPG_KEY_ID" \
        --armor --clearsign \
        --output "$(dirname "$release_file")/InRelease" \
        "$release_file"

    log_success "Release signed (Release.gpg + InRelease generated)"
}

export_public_key() {
    local repo_root="$1"
    local key_file="${repo_root}/KEY.gpg"

    if [ -z "${GPG_KEY_ID:-}" ]; then
        return 0
    fi

    log_step "Exporting public key to KEY.gpg..."
    gpg --armor --export "$GPG_KEY_ID" > "$key_file"
    log_success "Public key exported to KEY.gpg"
}

commit_and_push() {
    local repo_root="$1"
    local version="$2"

    cd "$repo_root"

    if [ -z "$(git status --porcelain)" ]; then
        log_info "No changes in gh-pages — nothing to commit"
        return 0
    fi

    log_step "Committing APT repository update..."
    git add -A
    git commit -m "APT repo: add jpeg-exif-stripper v${version}"

    if [ "$PUSH" = true ]; then
        log_step "Pushing gh-pages to origin..."
        git push origin gh-pages
        log_success "Pushed gh-pages"
        echo ""
        log_info "APT repository now live at:"
        echo "   https://pommersche92.github.io/jpeg_exif_stripper/"
        echo ""
        log_info "Users can install with:"
        echo "   curl -fsSL https://pommersche92.github.io/jpeg_exif_stripper/KEY.gpg \\"
        echo "       | sudo gpg --dearmor -o /usr/share/keyrings/jpeg-exif-stripper.gpg"
        echo "   echo \"deb [arch=amd64 signed-by=/usr/share/keyrings/jpeg-exif-stripper.gpg] \\"
        echo "       https://pommersche92.github.io/jpeg_exif_stripper stable main\" \\"
        echo "       | sudo tee /etc/apt/sources.list.d/jpeg-exif-stripper.list"
        echo "   sudo apt-get update && sudo apt-get install jpeg-exif-stripper"
    else
        log_warning "Dry-run: changes committed locally but not pushed (pass --push to push)"
        git log --oneline -1
    fi
}

main() {
    cd "$PROJECT_ROOT"

    check_deps

    local version
    version=$(get_version)

    log_info "Publishing APT repository for jpeg_exif_stripper v${version}"
    [ "$PUSH" = true ] && log_info "Mode: PUSH" || log_warning "Mode: dry-run (use --push to actually push)"
    [ -n "${GPG_KEY_ID:-}" ] && log_info "GPG key: ${GPG_KEY_ID}" || log_warning "GPG_KEY_ID not set — repo will be unsigned"
    echo ""

    setup_worktree
    trap 'teardown_worktree' EXIT

    populate_pool     "$WORKTREE_DIR"
    echo ""
    build_packages_index "$WORKTREE_DIR"
    create_release_file  "$WORKTREE_DIR"
    sign_release         "$WORKTREE_DIR"
    export_public_key    "$WORKTREE_DIR"
    echo ""
    commit_and_push      "$WORKTREE_DIR" "$version"
}

main
