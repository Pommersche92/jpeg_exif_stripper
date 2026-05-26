#!/usr/bin/env bash
#
# .deb Package Build Script for jpeg_exif_stripper
# Usage: ./scripts/build-deb.sh [--skip-build]
#
# Builds a Debian/Ubuntu .deb package using cargo-deb and places the result
# in target/dist/.
#
# Prerequisites:
#   cargo install cargo-deb
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
SKIP_BUILD=false

log_info()    { echo -e "${BLUE}ℹ${NC} $1" >&2; }
log_success() { echo -e "${GREEN}✓${NC} $1" >&2; }
log_warning() { echo -e "${YELLOW}⚠${NC} $1" >&2; }
log_error()   { echo -e "${RED}✗${NC} $1" >&2; }
log_step()    { echo -e "${CYAN}${BOLD}▶ $1${NC}" >&2; }

get_version() {
    grep '^version = ' "$CARGO_TOML" | head -n1 | sed 's/version = "\(.*\)"/\1/'
}

check_cargo_deb() {
    if ! cargo deb --help &>/dev/null 2>&1; then
        log_error "cargo-deb is not installed."
        log_error "Install it with: cargo install cargo-deb"
        exit 1
    fi
}

while [[ $# -gt 0 ]]; do
    case $1 in
        --skip-build)
            SKIP_BUILD=true
            shift
            ;;
        -h|--help)
            echo "Usage: $0 [--skip-build]"
            echo ""
            echo "Options:"
            echo "  --skip-build   Use the binary already in target/release/ (skip cargo build)"
            exit 0
            ;;
        *)
            echo -e "${RED}Unknown option: $1${NC}"
            exit 1
            ;;
    esac
done

main() {
    cd "$PROJECT_ROOT"

    check_cargo_deb

    local version
    version=$(get_version)
    log_info "Building .deb for jpeg_exif_stripper v$version"
    echo ""

    mkdir -p "$DIST_DIR"

    local cargo_deb_args=()
    if [ "$SKIP_BUILD" = true ]; then
        log_info "Using existing binary (--skip-build)"
        cargo_deb_args+=(--no-build)
    else
        log_step "Building release binary..."
        cargo build --release
        log_success "Release binary built"
        echo ""
        # cargo deb will re-build internally if we don't pass --no-build, so pass it
        # since we already built above to avoid double compilation.
        cargo_deb_args+=(--no-build)
    fi

    log_step "Packaging .deb..."
    cargo deb "${cargo_deb_args[@]}"

    # cargo-deb places output in target/debian/
    local deb_src
    deb_src=$(find "${PROJECT_ROOT}/target/debian" -maxdepth 1 -name "*.deb" 2>/dev/null \
        | sort -V | tail -n1)

    if [ -z "$deb_src" ]; then
        log_error ".deb not found in target/debian/ — cargo-deb may have failed"
        exit 1
    fi

    local deb_dest="${DIST_DIR}/$(basename "$deb_src")"
    cp "$deb_src" "$deb_dest"

    log_success "Built: $(basename "$deb_dest") ($(du -sh "$deb_dest" | cut -f1))"
    echo ""
    log_info "Install locally with: sudo dpkg -i $deb_dest"
}

main
