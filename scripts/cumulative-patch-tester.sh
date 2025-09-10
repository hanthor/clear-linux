#!/bin/bash

# Cumulative Patch Tester for Clear Linux
# Tests patches in the same sequence as the actual build

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
SPEC_FILE="$PROJECT_ROOT/linux.spec"
WORKDIR="$PROJECT_ROOT/cumulative-test"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
log_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# Get kernel version from spec file
get_kernel_version() {
    KERNEL_VERSION=$(grep -E "^Version:" "$SPEC_FILE" | awk '{print $2}')
    if [[ -z "$KERNEL_VERSION" ]]; then
        log_error "Could not extract kernel version from spec file"
        exit 1
    fi
    log_info "Detected kernel version: $KERNEL_VERSION"
}

# Extract enabled patches in order from spec file
get_enabled_patches() {
    local patches_file="$1"
    
    log_info "Extracting enabled patches from linux.spec..."
    
    # Get patch declarations that are NOT commented out
    grep -E "^Patch[0-9]+:" "$SPEC_FILE" | while read -r line; do
        if [[ $line =~ ^Patch([0-9]+):[[:space:]]*(.+\.patch)$ ]]; then
            local patch_num="${BASH_REMATCH[1]}"
            local patch_file="${BASH_REMATCH[2]}"
            
            # Check if this patch is applied (not commented in %patch section)
            if grep -q "^%patch ${patch_num}" "$SPEC_FILE"; then
                echo "$patch_num|$patch_file"
            fi
        fi
    done | sort -t'|' -k1,1n > "$patches_file"
    
    local patch_count=$(wc -l < "$patches_file")
    log_success "Found $patch_count enabled patches"
}

# Test cumulative patch application
test_cumulative_patches() {
    local patches_file="$WORKDIR/enabled_patches.list"
    local test_dir="$WORKDIR/kernel-source"
    
    mkdir -p "$WORKDIR"
    
    get_enabled_patches "$patches_file"
    
    # Download and extract kernel source
    local kernel_tarball="$WORKDIR/linux-${KERNEL_VERSION}.tar.xz"
    
    if [[ ! -f "$kernel_tarball" ]]; then
        log_info "Downloading kernel source..."
        wget -q "https://cdn.kernel.org/pub/linux/kernel/v6.x/linux-${KERNEL_VERSION}.tar.xz" -O "$kernel_tarball"
    fi
    
    # Clean and extract
    rm -rf "$test_dir"
    mkdir -p "$test_dir"
    log_info "Extracting kernel source..."
    tar -xf "$kernel_tarball" -C "$test_dir" --strip-components=1
    
    cd "$test_dir"
    
    local total_patches=0
    local successful_patches=0
    local failed_patches=0
    
    log_info "Testing cumulative patch application..."
    echo
    
    while IFS='|' read -r patch_num patch_file; do
        [[ -z "$patch_num" ]] && continue
        
        ((total_patches++))
        local full_patch_path="$PROJECT_ROOT/$patch_file"
        
        if [[ ! -f "$full_patch_path" ]]; then
            log_warning "Patch file not found: $patch_file"
            continue
        fi
        
        printf "Applying patch %s (%s)... " "$patch_num" "$(basename "$patch_file")"
        
        # Try to apply the patch
        if patch -p1 --no-backup-if-mismatch < "$full_patch_path" >/dev/null 2>&1; then
            echo -e "${GREEN}SUCCESS${NC}"
            ((successful_patches++))
        else
            echo -e "${RED}FAILED${NC}"
            ((failed_patches++))
            
            # Save the reject files for analysis
            local reject_dir="$WORKDIR/rejects/patch-$patch_num"
            mkdir -p "$reject_dir"
            find . -name "*.rej" -exec cp {} "$reject_dir/" \; 2>/dev/null || true
            find . -name "*.orig" -exec rm {} \; 2>/dev/null || true
            
            log_error "Patch $patch_num failed. Reject files saved to: $reject_dir"
            
            # Stop on first failure to avoid cascading issues
            log_error "Stopping cumulative test due to patch failure"
            break
        fi
    done < "$patches_file"
    
    echo
    log_info "Cumulative Test Results:"
    echo "  Total patches: $total_patches"
    echo "  Successful: $successful_patches"
    echo "  Failed: $failed_patches"
    
    if [[ $failed_patches -eq 0 ]]; then
        log_success "All enabled patches applied successfully in sequence!"
        return 0
    else
        log_error "Cumulative patch application failed"
        return 1
    fi
}

# Clean up test directory
cleanup() {
    if [[ -d "$WORKDIR" ]]; then
        log_info "Cleaning up test directory..."
        rm -rf "$WORKDIR"
    fi
}

# Show help
show_help() {
    cat << EOF
Cumulative Patch Tester for Clear Linux

This script tests patches in the same sequence as the actual build,
revealing conflicts that dry-run testing misses.

Usage: $0 [COMMAND]

Commands:
    test        Run cumulative patch test (default)
    clean       Clean up test directory
    help        Show this help message

The script will:
1. Extract enabled patches from linux.spec in order
2. Apply them sequentially to a clean kernel source
3. Stop on the first failure and show reject files
4. Simulate the exact same process as the container build

EOF
}

# Main function
main() {
    local command="${1:-test}"
    
    case "$command" in
        "test")
            get_kernel_version
            if test_cumulative_patches; then
                log_success "Cumulative patch testing completed successfully"
            else
                log_error "Cumulative patch testing failed"
                exit 1
            fi
            ;;
        "clean")
            cleanup
            ;;
        "help"|*)
            show_help
            ;;
    esac
}

# Handle cleanup on exit
trap cleanup EXIT

# Run main function
main "$@"
