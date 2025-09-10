#!/bin/bash

# Clear Linux Patch Manager
# This script helps manage patch application and testing for Clear Linux kernel builds

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SPEC_FILE="${SCRIPT_DIR}/linux.spec"
KERNEL_VERSION=""
WORKDIR="${SCRIPT_DIR}/patch-testing"

# Check if required tools are installed
for cmd in grep sed awk patch wget tar; do
    if ! command -v $cmd &> /dev/null; then
        sudo dnf install -y $cmd || sudo dnf install -y $cmd --transient || sudo apt-get install -y $cmd
        echo "Error: Required command '$cmd' not found. Please install it." >&2
        exit 1
    fi
done

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Get kernel version from spec file
get_kernel_version() {
    if [[ ! -f "$SPEC_FILE" ]]; then
        log_error "linux.spec not found at $SPEC_FILE"
        exit 1
    fi
    
    KERNEL_VERSION=$(grep -E "^Version:" "$SPEC_FILE" | awk '{print $2}')
    if [[ -z "$KERNEL_VERSION" ]]; then
        log_error "Could not extract kernel version from spec file"
        exit 1
    fi
    
    log_info "Detected kernel version: $KERNEL_VERSION"
}

# Extract all patch information from spec file
extract_patch_info() {
    local patches_file="$1"
    
    log_info "Extracting patch information from linux.spec..."
    
    # Create a structured file with patch info
    cat > "$patches_file" << 'EOF'
# Format: STATUS|PATCH_NUM|PATCH_FILE|DECLARATION_LINE|APPLICATION_LINE
# STATUS: ENABLED, DISABLED_DECL, DISABLED_APP, DISABLED_BOTH
EOF
    
    # Get all patch declarations - improved regex to handle the actual format
    while IFS= read -r line; do
        if [[ $line =~ ^(#)?Patch([0-9]+):[[:space:]]*(.+\.patch)$ ]]; then
            local comment_prefix="${BASH_REMATCH[1]}"
            local patch_num="${BASH_REMATCH[2]}"
            local patch_file="${BASH_REMATCH[3]}"
            local line_num=$(grep -n "^#\?Patch${patch_num}:" "$SPEC_FILE" | head -1 | cut -d: -f1)
            
            # Check if declaration is commented
            local decl_commented=""
            if [[ -n "$comment_prefix" ]]; then
                decl_commented="DECL"
            fi
            
            # Check if patch application is commented
            local app_line=$(grep -n "^#\?%patch ${patch_num}" "$SPEC_FILE" | head -1 | cut -d: -f1)
            local app_commented=""
            
            if grep -q "^#%patch ${patch_num}" "$SPEC_FILE"; then
                app_commented="APP"
            fi
            
            # Determine overall status
            local status="ENABLED"
            if [[ -n "$decl_commented" && -n "$app_commented" ]]; then
                status="DISABLED_BOTH"
            elif [[ -n "$decl_commented" ]]; then
                status="DISABLED_DECL"
            elif [[ -n "$app_commented" ]]; then
                status="DISABLED_APP"
            elif [[ -z "$app_line" ]]; then
                # Patch declared but no application found
                status="DISABLED_APP"
            fi
            
            echo "$status|$patch_num|$patch_file|$line_num|$app_line" >> "$patches_file"
        fi
    done < "$SPEC_FILE"
    
    log_success "Patch information extracted to $patches_file"
}

# Show current patch status
show_patch_status() {
    local patches_file="${WORKDIR}/patches.info"
    
    if [[ ! -f "$patches_file" ]]; then
        extract_patch_info "$patches_file"
    fi
    
    echo
    log_info "Current patch status for Linux $KERNEL_VERSION:"
    echo
    
    local enabled_count=0
    local disabled_count=0
    
    printf "%-8s %-8s %-50s %s\n" "STATUS" "PATCH#" "FILENAME" "DESCRIPTION"
    printf "%-8s %-8s %-50s %s\n" "------" "------" "--------" "-----------"
    
    while IFS='|' read -r status patch_num patch_file decl_line app_line; do
        [[ $status == \#* ]] && continue  # Skip comments
        [[ -z "$status" ]] && continue    # Skip empty lines
        
        case "$status" in
            "ENABLED")
                printf "${GREEN}%-8s${NC} %-8s %-50s %s\n" "ENABLED" "$patch_num" "$patch_file" "Active"
                ((enabled_count++))
                ;;
            "DISABLED_BOTH")
                printf "${RED}%-8s${NC} %-8s %-50s %s\n" "DISABLED" "$patch_num" "$patch_file" "Declaration and application commented"
                ((disabled_count++))
                ;;
            "DISABLED_DECL")
                printf "${YELLOW}%-8s${NC} %-8s %-50s %s\n" "PARTIAL" "$patch_num" "$patch_file" "Declaration commented only"
                ((disabled_count++))
                ;;
            "DISABLED_APP")
                printf "${YELLOW}%-8s${NC} %-8s %-50s %s\n" "PARTIAL" "$patch_num" "$patch_file" "Application commented only"
                ((disabled_count++))
                ;;
        esac
    done < "$patches_file"
    
    echo
    log_info "Summary: $enabled_count enabled, $disabled_count disabled/partial patches"
}

# Test if a specific patch applies cleanly
test_patch_application() {
    local patch_file="$1"
    local test_dir="${WORKDIR}/test-$(basename "$patch_file" .patch)"
    
    if [[ ! -f "$patch_file" ]]; then
        log_error "Patch file not found: $patch_file"
        return 1
    fi
    
    log_info "Testing patch application: $(basename "$patch_file")"
    
    # Create test directory
    rm -rf "$test_dir"
    mkdir -p "$test_dir"
    
    # Download and extract kernel source if not already present
    local kernel_tarball="${WORKDIR}/linux-${KERNEL_VERSION}.tar.xz"
    local kernel_dir="${WORKDIR}/linux-${KERNEL_VERSION}"
    
    if [[ ! -f "$kernel_tarball" ]]; then
        log_info "Downloading kernel source..."
        wget -q "https://cdn.kernel.org/pub/linux/kernel/v6.x/linux-${KERNEL_VERSION}.tar.xz" -O "$kernel_tarball"
    fi
    
    if [[ ! -d "$kernel_dir" ]]; then
        log_info "Extracting kernel source..."
        tar -xf "$kernel_tarball" -C "$WORKDIR"
    fi
    
    # Copy kernel source to test directory
    cp -r "$kernel_dir" "$test_dir/linux-${KERNEL_VERSION}"
    cd "$test_dir/linux-${KERNEL_VERSION}"
    
    # Try to apply the patch
    local patch_result=0
    if patch -p1 --dry-run < "$patch_file" >/dev/null 2>&1; then
        log_success "Patch applies cleanly"
        patch_result=0
    else
        log_warning "Patch has conflicts"
        # Try with fuzz
        if patch -p1 --dry-run --fuzz=3 < "$patch_file" >/dev/null 2>&1; then
            log_warning "Patch applies with fuzz (minor conflicts)"
            patch_result=1
        else
            log_error "Patch fails to apply even with fuzz"
            patch_result=2
        fi
    fi
    
    # Cleanup
    cd "$SCRIPT_DIR"
    rm -rf "$test_dir"
    
    return $patch_result
}

# Test all disabled patches
test_disabled_patches() {
    local patches_file="${WORKDIR}/patches.info"
    local results_file="${WORKDIR}/test-results.txt"
    
    mkdir -p "$WORKDIR"
    
    if [[ ! -f "$patches_file" ]]; then
        extract_patch_info "$patches_file"
    fi
    
    log_info "Testing all disabled patches against Linux $KERNEL_VERSION..."
    echo
    
    # Create results header
    cat > "$results_file" << EOF
# Patch Test Results for Linux $KERNEL_VERSION
# Generated on $(date)
# Format: PATCH_NUM|FILENAME|RESULT|DESCRIPTION

EOF
    
    local total_tested=0
    local clean_applies=0
    local fuzzy_applies=0
    local failed_applies=0
    
    while IFS='|' read -r status patch_num patch_file decl_line app_line; do
        [[ $status == \#* ]] && continue  # Skip comments
        
        # Only test disabled patches
        if [[ "$status" == "DISABLED_BOTH" || "$status" == "DISABLED_DECL" || "$status" == "DISABLED_APP" ]]; then
            if [[ -f "$SCRIPT_DIR/$patch_file" ]]; then
                ((total_tested++))
                echo -n "Testing patch $patch_num ($(basename "$patch_file"))... "
                
                if test_patch_application "$SCRIPT_DIR/$patch_file"; then
                    result_code=$?
                    case $result_code in
                        0)
                            echo -e "${GREEN}CLEAN${NC}"
                            echo "$patch_num|$patch_file|CLEAN|Applies without conflicts" >> "$results_file"
                            ((clean_applies++))
                            ;;
                        1)
                            echo -e "${YELLOW}FUZZY${NC}"
                            echo "$patch_num|$patch_file|FUZZY|Applies with minor conflicts (fuzz)" >> "$results_file"
                            ((fuzzy_applies++))
                            ;;
                        2)
                            echo -e "${RED}FAILED${NC}"
                            echo "$patch_num|$patch_file|FAILED|Significant conflicts, needs manual update" >> "$results_file"
                            ((failed_applies++))
                            ;;
                    esac
                else
                    echo -e "${RED}ERROR${NC}"
                    echo "$patch_num|$patch_file|ERROR|Test failed" >> "$results_file"
                    ((failed_applies++))
                fi
            else
                log_warning "Patch file not found: $patch_file"
                echo "$patch_num|$patch_file|MISSING|Patch file not found" >> "$results_file"
            fi
        fi
    done < "$patches_file"
    
    echo
    log_info "Test Summary:"
    echo "  Total tested: $total_tested"
    echo "  Clean applies: $clean_applies"
    echo "  Fuzzy applies: $fuzzy_applies"
    echo "  Failed applies: $failed_applies"
    echo
    log_info "Detailed results saved to: $results_file"
}

# Enable a specific patch
enable_patch() {
    local patch_num="$1"
    
    if [[ -z "$patch_num" ]]; then
        log_error "Patch number required"
        return 1
    fi
    
    log_info "Enabling patch $patch_num..."
    
    # Uncomment patch declaration
    sed -i "s/^#Patch${patch_num}:/Patch${patch_num}:/" "$SPEC_FILE"
    
    # Uncomment patch application
    sed -i "s/^#%patch${patch_num}/%patch${patch_num}/" "$SPEC_FILE"
    
    log_success "Patch $patch_num enabled"
}

# Disable a specific patch
disable_patch() {
    local patch_num="$1"
    
    if [[ -z "$patch_num" ]]; then
        log_error "Patch number required"
        return 1
    fi
    
    log_info "Disabling patch $patch_num..."
    
    # Comment patch declaration
    sed -i "s/^Patch${patch_num}:/#Patch${patch_num}:/" "$SPEC_FILE"
    
    # Comment patch application
    sed -i "s/^%patch${patch_num}/#%patch${patch_num}/" "$SPEC_FILE"
    
    log_success "Patch $patch_num disabled"
}

# Enable all patches that apply cleanly
enable_clean_patches() {
    local results_file="${WORKDIR}/test-results.txt"
    
    if [[ ! -f "$results_file" ]]; then
        log_error "No test results found. Run 'test' command first."
        return 1
    fi
    
    log_info "Enabling all patches that apply cleanly..."
    
    local enabled_count=0
    
    while IFS='|' read -r patch_num patch_file result description; do
        [[ $patch_num == \#* ]] && continue  # Skip comments
        
        if [[ "$result" == "CLEAN" ]]; then
            enable_patch "$patch_num"
            ((enabled_count++))
        fi
    done < "$results_file"
    
    log_success "Enabled $enabled_count patches"
}

# Show help
show_help() {
    cat << EOF
Clear Linux Patch Manager

Usage: $0 [COMMAND] [OPTIONS]

Commands:
    status          Show current status of all patches
    test            Test all disabled patches against current kernel version
    enable <NUM>    Enable a specific patch by number
    disable <NUM>   Disable a specific patch by number
    enable-clean    Enable all patches that tested as clean
    help            Show this help message

Examples:
    $0 status                    # Show current patch status
    $0 test                      # Test all disabled patches
    $0 enable 106                # Enable patch 106
    $0 disable 118               # Disable patch 118
    $0 enable-clean              # Enable all clean-applying patches

The script will:
1. Parse linux.spec to identify enabled/disabled patches
2. Test disabled patches against the current kernel version
3. Provide tools to selectively enable/disable patches
4. Help you gradually re-enable patches that work

EOF
}

# Main function
main() {
    local command="${1:-help}"
    
    get_kernel_version
    mkdir -p "$WORKDIR"
    
    case "$command" in
        "status")
            show_patch_status
            ;;
        "test")
            test_disabled_patches
            ;;
        "enable")
            if [[ -n "${2:-}" ]]; then
                enable_patch "$2"
            else
                log_error "Patch number required for enable command"
                exit 1
            fi
            ;;
        "disable")
            if [[ -n "${2:-}" ]]; then
                disable_patch "$2"
            else
                log_error "Patch number required for disable command"
                exit 1
            fi
            ;;
        "enable-clean")
            enable_clean_patches
            ;;
        "help"|*)
            show_help
            ;;
    esac
}

# Run main function with all arguments
main "$@"
