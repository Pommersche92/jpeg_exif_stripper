#!/usr/bin/env bash
#
# GitHub Release Script for jpeg_exif_stripper
# Usage: ./scripts/release-github.sh [OPTIONS]
#
# Builds Linux x64 tarball, AppImage, and Windows x64 zip, then creates
# (or updates) a GitHub release with those assets attached.
#
# Prerequisites:
#   - gh CLI installed and authenticated (gh auth login)
#   - For Windows cross-compile: sudo apt install gcc-mingw-w64-x86-64
#     and: rustup target add x86_64-pc-windows-gnu
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
DIST_DIR="${PROJECT_ROOT}/target/dist"

DRAFT_MODE=false
SKIP_BUILD=false
SKIP_WINDOWS=false
SKIP_APPIMAGE=false
SKIP_DEB=false
RELEASE_NOTES=""

while [[ $# -gt 0 ]]; do
    case $1 in
        --draft)
            DRAFT_MODE=true
            shift
            ;;
        --skip-build)
            SKIP_BUILD=true
            shift
            ;;
        --skip-windows)
            SKIP_WINDOWS=true
            shift
            ;;
        --skip-appimage)
            SKIP_APPIMAGE=true
            shift
            ;;
        --skip-deb)
            SKIP_DEB=true
            shift
            ;;
        --notes)
            RELEASE_NOTES="$2"
            shift 2
            ;;
        -h|--help)
            echo "Usage: $0 [OPTIONS]"
            echo ""
            echo "Build assets and create/update a GitHub release."
            echo ""
            echo "Options:"
            echo "  --draft              Create the release as a draft"
            echo "  --skip-build         Skip the cargo build step"
            echo "  --skip-windows       Skip Windows cross-compile"
            echo "  --skip-appimage      Skip AppImage build"
            echo "  --skip-deb           Skip .deb package build"
            echo "  --notes TEXT         Release notes text"
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

get_package_name() {
    grep '^name = ' "$CARGO_TOML" | head -n1 | sed 's/name = "\(.*\)"/\1/'
}

check_gh_cli() {
    if ! command -v gh &>/dev/null; then
        log_error "GitHub CLI (gh) is not installed. Install it from https://cli.github.com/"
        exit 1
    fi
}

check_gh_auth() {
    if ! gh auth status &>/dev/null; then
        log_error "Not authenticated to GitHub. Run: gh auth login"
        exit 1
    fi
}

check_release_exists() {
    local tag="$1"
    gh release view "$tag" --repo "Pommersche92/jpeg_exif_stripper" &>/dev/null
}

build_release() {
    cd "$PROJECT_ROOT"
    log_step "Building Linux release binary..."
    export RUSTUP_TOOLCHAIN=stable
    cargo build --release
    log_success "Linux binary built"
}

build_windows() {
    if ! command -v x86_64-w64-mingw32-gcc &>/dev/null; then
        log_warning "mingw cross-compiler not found (x86_64-w64-mingw32-gcc)"
        log_warning "Install with: sudo apt install gcc-mingw-w64-x86-64"
        log_warning "Skipping Windows build"
        return 0
    fi
    if ! rustup target list --installed | grep -q 'x86_64-pc-windows-gnu'; then
        log_info "Adding Windows target for Rust..."
        rustup target add x86_64-pc-windows-gnu
    fi
    cd "$PROJECT_ROOT"

    export RUSTUP_TOOLCHAIN=stable
    export CARGO_TARGET_X86_64_PC_WINDOWS_GNU_LINKER=x86_64-w64-mingw32-gcc

    log_step "Building Windows release binary (cross-compile)..."
    cargo build --release --target x86_64-pc-windows-gnu
    log_success "Windows binary built"
}

create_tarball() {
    local archive_basename="${PACKAGE_NAME}-${VERSION}-x86_64.tar.gz"
    local dir_name="${PACKAGE_NAME}-${VERSION}"
    local bin_src="target/release/${PACKAGE_NAME}"

    if [ ! -f "$bin_src" ]; then
        log_warning "Linux binary not found at $bin_src — skipping tarball"
        return 0
    fi

    local tarball="${DIST_DIR}/${archive_basename}"
    log_step "Creating Linux tarball: ${archive_basename}"

    local staging
    staging=$(mktemp -d)
    local staging_dir="${staging}/${dir_name}"
    mkdir -p "$staging_dir"

    cp "$bin_src" "$staging_dir/${PACKAGE_NAME}"
    [ -f LICENSE.md ] && cp LICENSE.md "$staging_dir/"
    [ -f LICENSE ]    && cp LICENSE    "$staging_dir/"
    [ -f README.md ]  && cp README.md  "$staging_dir/"

    tar -czf "$tarball" -C "$staging" "${dir_name}"
    rm -rf "$staging"

    log_success "Created: ${archive_basename} ($(du -sh "$tarball" | cut -f1))"
}

create_windows_zip() {
    if ! command -v zip &>/dev/null; then
        log_warning "zip command not found, skipping Windows zip"
        return 0
    fi

    local win_dir="target/x86_64-pc-windows-gnu/release"
    local exe_src="${win_dir}/${PACKAGE_NAME}.exe"
    local zip_basename="${PACKAGE_NAME}-${VERSION}-x86_64-windows.zip"
    local dir_name="${PACKAGE_NAME}-${VERSION}"

    if [ ! -f "$exe_src" ]; then
        log_warning "Windows binary not found at $exe_src — skipping zip"
        return 0
    fi

    local zipfile="${DIST_DIR}/${zip_basename}"
    log_step "Creating Windows zip: ${zip_basename}"

    local staging
    staging=$(mktemp -d)
    local staging_dir="${staging}/${dir_name}"
    mkdir -p "$staging_dir"

    cp "$exe_src" "$staging_dir/${PACKAGE_NAME}.exe"
    [ -f LICENSE.md ] && cp LICENSE.md "$staging_dir/"
    [ -f LICENSE ]    && cp LICENSE    "$staging_dir/"
    [ -f README.md ]  && cp README.md  "$staging_dir/"

    (cd "$staging" && zip -r "$zipfile" "${dir_name}")
    rm -rf "$staging"

    log_success "Created: ${zip_basename} ($(du -sh "$zipfile" | cut -f1))"
}

build_appimage() {
    log_step "Building AppImage..."
    if "${PROJECT_ROOT}/scripts/build-appimage.sh" build --skip-build; then
        log_success "AppImage built"
    else
        log_warning "AppImage build failed — asset will be skipped"
    fi
}

build_deb() {
    if ! cargo deb --help &>/dev/null 2>&1; then
        log_warning "cargo-deb not installed — skipping .deb build"
        log_warning "Install with: cargo install cargo-deb"
        return 0
    fi

    cd "$PROJECT_ROOT"
    log_step "Building .deb package (cargo-deb)..."
    # Binary is already built; pass --no-build to avoid recompiling.
    cargo deb --no-build

    local deb_src
    deb_src=$(find "${PROJECT_ROOT}/target/debian" -maxdepth 1 -name '*.deb' 2>/dev/null \
        | sort -V | tail -n1)

    if [ -z "$deb_src" ]; then
        log_warning ".deb not found in target/debian/ — skipping"
        return 0
    fi

    local deb_dest="${DIST_DIR}/$(basename "$deb_src")"
    cp "$deb_src" "$deb_dest"
    log_success "Built: $(basename "$deb_dest") ($(du -sh "$deb_dest" | cut -f1))"
}

create_github_release() {
    local tag="v$VERSION"
    local title="jpeg_exif_stripper v${VERSION}"

    log_step "Creating GitHub release: $tag"

    local -a assets
    assets=()

    local f
    for f in \
        "${DIST_DIR}/${PACKAGE_NAME}-${VERSION}-x86_64.tar.gz" \
        "${DIST_DIR}/${PACKAGE_NAME}-${VERSION}-x86_64.AppImage" \
        "${DIST_DIR}/${PACKAGE_NAME}-${VERSION}-x86_64-windows.zip" \
        "${DIST_DIR}/jpeg-exif-stripper_${VERSION}_amd64.deb"; do
        if [ -f "$f" ]; then
            assets+=("$f")
            log_info "  + $(basename "$f")"
        fi
    done

    if [ "${#assets[@]}" -eq 0 ]; then
        log_warning "No release assets found in $DIST_DIR"
    fi

    local -a gh_args
    gh_args=(release create "$tag" --title "$title")
    [ "$DRAFT_MODE" = true ] && gh_args+=(--draft)
    [ -n "$RELEASE_NOTES" ] && gh_args+=(--notes "$RELEASE_NOTES") || gh_args+=(--generate-notes)
    gh_args+=(--repo "Pommersche92/jpeg_exif_stripper")

    if check_release_exists "$tag"; then
        log_warning "Release $tag already exists — deleting and recreating"
        gh release delete "$tag" --yes --repo "Pommersche92/jpeg_exif_stripper" || true
    fi

    gh "${gh_args[@]}" "${assets[@]}"

    log_success "GitHub release created: https://github.com/Pommersche92/jpeg_exif_stripper/releases/tag/$tag"
}

main() {
    cd "$PROJECT_ROOT"

    check_gh_cli
    check_gh_auth

    VERSION=$(get_version)
    PACKAGE_NAME=$(get_package_name)

    log_info "Package: $PACKAGE_NAME v$VERSION"
    echo ""

    mkdir -p "$DIST_DIR"

    if [ "$SKIP_BUILD" = false ]; then
        build_release
        echo ""
    fi

    if [ "$SKIP_WINDOWS" = false ]; then
        build_windows
        echo ""
    fi

    create_tarball
    create_windows_zip || true
    echo ""

    if [ "$SKIP_APPIMAGE" = false ]; then
        build_appimage
        echo ""
    fi

    if [ "$SKIP_DEB" = false ]; then
        build_deb
        echo ""
    fi

    create_github_release

    echo ""
    echo -e "${GREEN}${BOLD}✓ Release assets in: target/dist/${NC}"
    ls -lh "$DIST_DIR" 2>/dev/null || true
}

main
