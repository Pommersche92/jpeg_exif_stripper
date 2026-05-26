#!/usr/bin/env bash
#
# AppImage Build Script for jpeg_exif_stripper
# Usage: ./scripts/build-appimage.sh build [--skip-build]
#
# Downloads linuxdeploy (if needed), creates an AppDir, and packages the
# jpeg_exif_stripper binary into an AppImage stored in target/dist/.
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
BUILD_DIR="${PROJECT_ROOT}/target/appimage-build"
DIST_DIR="${PROJECT_ROOT}/target/dist"
LINUXDEPLOY_URL="https://github.com/linuxdeploy/linuxdeploy/releases/download/continuous/linuxdeploy-x86_64.AppImage"
LINUXDEPLOY="${BUILD_DIR}/linuxdeploy-x86_64.AppImage"
SKIP_BUILD=false

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

download_linuxdeploy() {
    if [ -f "$LINUXDEPLOY" ] && [ -x "$LINUXDEPLOY" ]; then
        log_info "linuxdeploy already present"
        return 0
    fi
    log_step "Downloading linuxdeploy..."
    mkdir -p "$BUILD_DIR"
    if command -v wget &>/dev/null; then
        wget -qO "$LINUXDEPLOY" "$LINUXDEPLOY_URL"
    elif command -v curl &>/dev/null; then
        curl -sSfL "$LINUXDEPLOY_URL" -o "$LINUXDEPLOY"
    else
        log_error "Neither wget nor curl found"
        exit 1
    fi
    chmod +x "$LINUXDEPLOY"
    log_success "linuxdeploy downloaded"
}

create_appdir() {
    local pkg="$1"
    local appdir="$2"

    log_step "Creating AppDir for ${pkg}..."
    rm -rf "$appdir"
    mkdir -p "$appdir/usr/bin"
    mkdir -p "$appdir/usr/share/applications"
    mkdir -p "$appdir/usr/share/icons/hicolor/256x256/apps"

    # Binary
    cp "${PROJECT_ROOT}/target/release/$pkg" "$appdir/usr/bin/$pkg"

    # .desktop file — Terminal=true since this is a CLI tool
    cat > "$appdir/usr/share/applications/${pkg}.desktop" << DESKTOP
[Desktop Entry]
Type=Application
Name=JPEG EXIF Stripper
Comment=Lossless JPEG EXIF metadata removal utility
Exec=${pkg}
Icon=${pkg}
Categories=Utility;
Terminal=true
DESKTOP

    # Icon — generate a minimal placeholder since this is a CLI tool
    local icon_out="$appdir/usr/share/icons/hicolor/256x256/apps/${pkg}.png"
    if command -v convert &>/dev/null; then
        log_info "Generating placeholder icon with ImageMagick"
        convert -size 256x256 xc:'#1a1a2e' \
            -fill '#e94560' -font DejaVu-Sans-Bold -pointsize 64 \
            -gravity center -annotate 0 'EXIF' \
            "$icon_out"
    elif command -v magick &>/dev/null; then
        log_info "Generating placeholder icon with ImageMagick (magick)"
        magick -size 256x256 xc:'#1a1a2e' \
            -fill '#e94560' -font DejaVu-Sans-Bold -pointsize 64 \
            -gravity center -annotate 0 'EXIF' \
            "$icon_out"
    else
        log_warning "ImageMagick not found — generating minimal 1x1 PNG placeholder"
        # Minimal valid 1x1 PNG
        printf '\x89PNG\r\n\x1a\n\x00\x00\x00\rIHDR\x00\x00\x00\x01\x00\x00\x00\x01\x08\x02\x00\x00\x00\x90wS\xde\x00\x00\x00\x0cIDATx\x9cc\xf8\x0f\x00\x00\x01\x01\x00\x05\x18\xd8N\x00\x00\x00\x00IEND\xaeB`\x82' \
            > "$icon_out"
    fi

    # AppRun
    cat > "$appdir/AppRun" << APPRUN
#!/bin/sh
HERE="\$(dirname "\$(readlink -f "\$0")")"
exec "\${HERE}/usr/bin/${pkg}" "\$@"
APPRUN
    chmod +x "$appdir/AppRun"

    log_success "AppDir created"
}

run_linuxdeploy() {
    local pkg="$1"
    local output_path="$2"
    local appdir="$3"

    mkdir -p "$DIST_DIR"
    export OUTPUT="${output_path}"
    if ! ARCH=x86_64 "$LINUXDEPLOY" \
            --appdir "$appdir" \
            --desktop-file "$appdir/usr/share/applications/${pkg}.desktop" \
            --icon-file "$appdir/usr/share/icons/hicolor/256x256/apps/${pkg}.png" \
            --output appimage 2>&1; then
        log_warning "linuxdeploy failed with FUSE; retrying with --appimage-extract-and-run"
        export APPIMAGE_EXTRACT_AND_RUN=1
        ARCH=x86_64 "$LINUXDEPLOY" \
            --appdir "$appdir" \
            --desktop-file "$appdir/usr/share/applications/${pkg}.desktop" \
            --icon-file "$appdir/usr/share/icons/hicolor/256x256/apps/${pkg}.png" \
            --output appimage
    fi

    if [ ! -f "$output_path" ]; then
        local found
        found=$(find "$BUILD_DIR" "$PROJECT_ROOT" -maxdepth 1 -name '*.AppImage' -newer "$LINUXDEPLOY" 2>/dev/null | head -n1)
        if [ -n "$found" ]; then
            mv "$found" "$output_path"
        else
            log_error "Could not locate built AppImage"
            exit 1
        fi
    fi

    chmod +x "$output_path"
    log_success "AppImage: $(basename "$output_path") ($(du -sh "$output_path" | cut -f1))"
}

main() {
    local command="${1:-build}"
    shift || true

    while [[ $# -gt 0 ]]; do
        case $1 in
            --skip-build)
                SKIP_BUILD=true
                shift
                ;;
            -h|--help)
                echo "Usage: $0 build [--skip-build]"
                echo ""
                echo "Options:"
                echo "  --skip-build   Skip cargo build (use binary already in target/release/)"
                exit 0
                ;;
            *)
                echo -e "${RED}Unknown option: $1${NC}"
                exit 1
                ;;
        esac
    done

    if [ "$command" != "build" ]; then
        echo "Usage: $0 build [--skip-build]"
        exit 1
    fi

    cd "$PROJECT_ROOT"

    local pkg version
    pkg=$(get_package_name)
    version=$(get_version)
    local appdir="${BUILD_DIR}/AppDir"
    local output_path="${DIST_DIR}/${pkg}-${version}-x86_64.AppImage"

    log_info "Building AppImage for $pkg v$version"
    echo ""

    download_linuxdeploy

    if [ "$SKIP_BUILD" = false ]; then
        log_step "Building release binary..."
        cargo build --release
        log_success "Release binary built"
        echo ""
    else
        log_info "Skipping cargo build (--skip-build)"
    fi

    create_appdir "$pkg" "$appdir"
    echo ""
    log_step "Packaging AppImage..."
    run_linuxdeploy "$pkg" "$output_path" "$appdir"

    echo ""
    log_success "AppImage build complete"
}

main "$@"
