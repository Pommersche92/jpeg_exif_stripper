#!/usr/bin/env bash
#
# AUR Deployment Script for jpeg_exif_stripper
# Usage: ./scripts/deploy-aur.sh [OPTIONS]
#
# Updates the PKGBUILDs for jpeg-exif-stripper (source), jpeg-exif-stripper-git,
# and jpeg-exif-stripper-bin (binary), regenerates .SRCINFO, and optionally
# pushes to the AUR.
#
# Prerequisites:
#   - AUR repos cloned into the aur/<pkgname>/aur-repo/ directories
#   - makepkg available (Arch Linux or Arch-based Docker image)
#   - curl or wget available
#
# AUR setup (one-time, run on an Arch Linux machine):
#   mkdir -p aur/jpeg-exif-stripper
#   git clone ssh://aur@aur.archlinux.org/jpeg-exif-stripper.git aur/jpeg-exif-stripper/aur-repo
#
#   mkdir -p aur/jpeg-exif-stripper-git
#   git clone ssh://aur@aur.archlinux.org/jpeg-exif-stripper-git.git aur/jpeg-exif-stripper-git/aur-repo
#
#   mkdir -p aur/jpeg-exif-stripper-bin
#   git clone ssh://aur@aur.archlinux.org/jpeg-exif-stripper-bin.git aur/jpeg-exif-stripper-bin/aur-repo
#

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
AUR_DIR="${PROJECT_ROOT}/aur"
TMP_DIR=$(mktemp -d)
trap 'rm -rf "$TMP_DIR"' EXIT

PUSH=false
PACKAGE=""   # empty = process all

while [[ $# -gt 0 ]]; do
    case $1 in
        --push)
            PUSH=true
            shift
            ;;
        --package)
            PACKAGE="$2"
            shift 2
            ;;
        -h|--help)
            echo "Usage: $0 [OPTIONS]"
            echo ""
            echo "Deploy jpeg_exif_stripper PKGBUILDs to the AUR."
            echo ""
            echo "Options:"
            echo "  --push               Commit and push to AUR (default: dry-run)"
            echo "  --package NAME       Process only this package:"
            echo "                         jpeg-exif-stripper"
            echo "                         jpeg-exif-stripper-git"
            echo "                         jpeg-exif-stripper-bin"
            echo "  -h, --help           Show this help"
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

update_pkgbuild_version() {
    local pkgbuild="$1"
    local new_version="$2"
    sed -i "s/^pkgver=.*/pkgver=${new_version}/" "$pkgbuild"
    sed -i "s/^pkgrel=.*/pkgrel=1/" "$pkgbuild"
    log_info "Updated pkgver to $new_version"
}

# Compute sha256 for the crates.io source tarball (jpeg-exif-stripper)
update_source_checksum() {
    local pkgbuild="$1"
    local version="$2"
    local crate_name="jpeg_exif_stripper"
    local url="https://static.crates.io/crates/${crate_name}/${crate_name}-${version}.crate"

    log_info "Downloading crate to compute sha256: $url"
    local crate_file="${TMP_DIR}/${crate_name}-${version}.crate"
    if command -v wget &>/dev/null; then
        wget -qO "$crate_file" "$url"
    else
        curl -sSfL "$url" -o "$crate_file"
    fi

    local sha256
    sha256=$(sha256sum "$crate_file" | awk '{print $1}')
    log_info "sha256: $sha256"

    sed -i "s/^sha256sums=.*/sha256sums=('${sha256}')/" "$pkgbuild"
    log_success "Updated source checksum"
}

# Compute sha256 for the GitHub release binary tarball (jpeg-exif-stripper-bin)
update_binary_checksum() {
    local pkgbuild="$1"
    local version="$2"
    local pkg_binary_name="jpeg_exif_stripper"
    local url="https://github.com/Pommersche92/jpeg_exif_stripper/releases/download/v${version}/${pkg_binary_name}-${version}-x86_64.tar.gz"

    log_info "Downloading release tarball to compute sha256: $url"
    local tarball="${TMP_DIR}/${pkg_binary_name}-${version}-x86_64.tar.gz"
    if command -v wget &>/dev/null; then
        wget -qO "$tarball" "$url"
    else
        curl -sSfL "$url" -o "$tarball"
    fi

    local sha256
    sha256=$(sha256sum "$tarball" | awk '{print $1}')
    log_info "sha256: $sha256"

    sed -i "s/^sha256sums=.*/sha256sums=('${sha256}')/" "$pkgbuild"
    log_success "Updated binary checksum"
}

generate_srcinfo() {
    local dir="$1"
    log_step "Generating .SRCINFO..."
    (cd "$dir" && makepkg --printsrcinfo > .SRCINFO)
    log_success ".SRCINFO generated"
}

push_to_aur() {
    local aur_repo="$1"
    local pkgbuild_src="$2"
    local version="$3"
    local pkgname
    pkgname=$(basename "$(dirname "$pkgbuild_src")")

    if [ ! -d "$aur_repo" ]; then
        log_error "AUR repo not found: $aur_repo"
        log_info "Set it up with:"
        log_info "  git clone ssh://aur@aur.archlinux.org/${pkgname}.git $(dirname "$aur_repo")/aur-repo"
        return 1
    fi

    # Copy updated files to AUR repo
    cp "$pkgbuild_src" "$aur_repo/PKGBUILD"
    [ -f "$(dirname "$pkgbuild_src")/.SRCINFO" ] && cp "$(dirname "$pkgbuild_src")/.SRCINFO" "$aur_repo/.SRCINFO"

    cd "$aur_repo"

    local has_changes=false
    if [ -n "$(git status --porcelain)" ]; then
        has_changes=true
        log_step "Committing changes for $pkgname..."
        git add PKGBUILD .SRCINFO
        git commit -m "Update to version $version"
    fi

    local unpushed_commits=0
    if git rev-parse --abbrev-ref @{upstream} &>/dev/null; then
        unpushed_commits=$(git rev-list @{upstream}..HEAD 2>/dev/null | wc -l)
    else
        if [ -n "$(git log --oneline 2>/dev/null)" ]; then
            unpushed_commits=1
        fi
    fi

    if [ "$has_changes" = false ] && [ "$unpushed_commits" -eq 0 ]; then
        log_info "No changes to push for $pkgname"
        return 0
    fi

    if [ "$PUSH" = true ]; then
        log_step "Pushing $pkgname to AUR..."
        if git push -u origin master 2>&1; then
            log_success "Pushed $pkgname v$version to AUR"
        elif git push -u origin main 2>&1; then
            log_success "Pushed $pkgname v$version to AUR"
        else
            log_error "Failed to push $pkgname"
            return 1
        fi
    else
        log_warning "Dry-run: changes ready but not pushed (pass --push to push)"
        git log --oneline -1
    fi
}

# Process jpeg-exif-stripper (stable source from crates.io)
process_source_package() {
    local pkgname="jpeg-exif-stripper"
    local version="$1"
    local pkg_dir="${AUR_DIR}/${pkgname}"
    local pkgbuild="${pkg_dir}/PKGBUILD"
    local aur_repo="${pkg_dir}/aur-repo"

    echo ""
    log_step "Processing $pkgname..."

    if [ ! -f "$pkgbuild" ]; then
        log_error "PKGBUILD not found: $pkgbuild"
        return 1
    fi

    update_pkgbuild_version "$pkgbuild" "$version"
    update_source_checksum "$pkgbuild" "$version"

    if command -v makepkg &>/dev/null; then
        generate_srcinfo "$pkg_dir"
    else
        log_warning "makepkg not available — skipping .SRCINFO generation (run on Arch Linux)"
    fi

    push_to_aur "$aur_repo" "$pkgbuild" "$version"
}

# Process jpeg-exif-stripper-git (bleeding-edge from git)
# The pkgver() function in the PKGBUILD generates version dynamically;
# we only push PKGBUILD changes (no version/checksum update needed).
process_git_package() {
    local pkgname="jpeg-exif-stripper-git"
    local version="$1"
    local pkg_dir="${AUR_DIR}/${pkgname}"
    local pkgbuild="${pkg_dir}/PKGBUILD"
    local aur_repo="${pkg_dir}/aur-repo"

    echo ""
    log_step "Processing $pkgname (no version/checksum update — git package)..."

    if [ ! -f "$pkgbuild" ]; then
        log_error "PKGBUILD not found: $pkgbuild"
        return 1
    fi

    if command -v makepkg &>/dev/null; then
        generate_srcinfo "$pkg_dir"
    else
        log_warning "makepkg not available — skipping .SRCINFO generation (run on Arch Linux)"
    fi

    push_to_aur "$aur_repo" "$pkgbuild" "$version"
}

# Process jpeg-exif-stripper-bin (prebuilt binary from GitHub release)
process_bin_package() {
    local pkgname="jpeg-exif-stripper-bin"
    local version="$1"
    local pkg_dir="${AUR_DIR}/${pkgname}"
    local pkgbuild="${pkg_dir}/PKGBUILD"
    local aur_repo="${pkg_dir}/aur-repo"

    echo ""
    log_step "Processing $pkgname..."

    if [ ! -f "$pkgbuild" ]; then
        log_error "PKGBUILD not found: $pkgbuild"
        return 1
    fi

    update_pkgbuild_version "$pkgbuild" "$version"
    update_binary_checksum "$pkgbuild" "$version"

    if command -v makepkg &>/dev/null; then
        generate_srcinfo "$pkg_dir"
    else
        log_warning "makepkg not available — skipping .SRCINFO generation (run on Arch Linux)"
    fi

    push_to_aur "$aur_repo" "$pkgbuild" "$version"
}

main() {
    cd "$PROJECT_ROOT"

    local version
    version=$(get_version)

    log_info "Deploying jpeg_exif_stripper v$version to AUR"
    [ "$PUSH" = true ] && log_info "Mode: PUSH" || log_warning "Mode: dry-run (use --push to actually push)"
    echo ""

    case "$PACKAGE" in
        "jpeg-exif-stripper")
            process_source_package "$version"
            ;;
        "jpeg-exif-stripper-git")
            process_git_package "$version"
            ;;
        "jpeg-exif-stripper-bin")
            process_bin_package "$version"
            ;;
        "")
            process_source_package "$version"
            process_git_package "$version"
            process_bin_package "$version"
            ;;
        *)
            log_error "Unknown package: $PACKAGE"
            log_info "Valid packages: jpeg-exif-stripper, jpeg-exif-stripper-git, jpeg-exif-stripper-bin"
            exit 1
            ;;
    esac

    echo ""
    log_success "AUR deployment complete"
    echo ""
    log_info "AUR package pages:"
    echo "   https://aur.archlinux.org/packages/jpeg-exif-stripper"
    echo "   https://aur.archlinux.org/packages/jpeg-exif-stripper-git"
    echo "   https://aur.archlinux.org/packages/jpeg-exif-stripper-bin"
}

main
