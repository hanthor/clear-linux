#!/bin/bash

# Clear Linux Patch Tester
# Tests disabled patches against the current kernel version to see which ones can be re-enabled

set -uo pipefail  # Removed -e temporarily for debugging

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
SPEC_FILE="${PROJECT_ROOT}/linux.spec"
WORKDIR="${PROJECT_ROOT}/temp-kernel"
KERNEL_VERSION=$(grep -E "^Version:" "$SPEC_FILE" | awk '{print $2}')

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

# Test if a specific patch applies cleanly
test_patch() {
    local patch_file="$1"
    local patch_num="$2"
    
    if [[ ! -f "$patch_file" ]]; then
        echo "MISSING"
        return 1
    fi
    
    local test_dir="${WORKDIR}/test-${patch_num}"
    local kernel_dir="${WORKDIR}/linux-${KERNEL_VERSION}"
    
    # Create test directory with kernel source
    rm -rf "$test_dir"
    mkdir -p "$test_dir"
    
    if [[ ! -d "$kernel_dir" ]]; then
        log_error "Kernel source not found. Please run: ./patch-tester.sh download"
        return 1
    fi
    
    cp -r "$kernel_dir" "$test_dir/linux-${KERNEL_VERSION}"
    cd "$test_dir/linux-${KERNEL_VERSION}"
    
    # Try to apply the patch
    if patch -p1 --dry-run --silent < "$patch_file" 2>/dev/null; then
        echo "CLEAN"
        cd "$PROJECT_ROOT"
        rm -rf "$test_dir"
        return 0
    elif patch -p1 --dry-run --fuzz=3 --silent < "$patch_file" 2>/dev/null; then
        echo "FUZZY"
        cd "$PROJECT_ROOT"
        rm -rf "$test_dir"
        return 1
    else
        echo "FAILED"
        cd "$PROJECT_ROOT"
        rm -rf "$test_dir"
        return 2
    fi
}

# Download kernel source
download_kernel() {
    local kernel_tarball="${WORKDIR}/linux-${KERNEL_VERSION}.tar.xz"
    local kernel_dir="${WORKDIR}/linux-${KERNEL_VERSION}"
    
    mkdir -p "$WORKDIR"
    
    if [[ -d "$kernel_dir" ]]; then
        log_info "Kernel source already present"
        return 0
    fi
    
    if [[ ! -f "$kernel_tarball" ]]; then
        log_info "Downloading Linux $KERNEL_VERSION..."
        wget -q --show-progress "https://cdn.kernel.org/pub/linux/kernel/v6.x/linux-${KERNEL_VERSION}.tar.xz" -O "$kernel_tarball"
    fi
    
    log_info "Extracting kernel source..."
    tar -xf "$kernel_tarball" -C "$WORKDIR"
    log_success "Kernel source ready at $kernel_dir"
}

# Test all disabled patches
test_disabled() {
    results_file="${WORKDIR}/test-results.txt"
    
    if [[ ! -d "${WORKDIR}/linux-${KERNEL_VERSION}" ]]; then
        log_error "Kernel source not found. Run: $0 download"
        exit 1
    fi
    
    log_info "Testing disabled patches against Linux $KERNEL_VERSION..."
    echo
    
    # Create results file
    cat > "$results_file" << EOF
# Patch Test Results for Linux $KERNEL_VERSION
# Generated: $(date)
# Format: PATCH_NUM|FILENAME|RESULT|COMMANDS_TO_ENABLE

EOF
    
    total=0
    clean=0
    fuzzy=0
    failed=0
    missing=0
    
    # Find all disabled patch declarations
    while IFS= read -r line; do
        if [[ $line =~ ^#Patch([0-9]+):[[:space:]]*(.+\.patch)$ ]]; then
            patch_num="${BASH_REMATCH[1]}"
            patch_file="${BASH_REMATCH[2]}"
            
            # Only test if application is also commented
            if grep -q "^#%patch ${patch_num}" "$SPEC_FILE"; then
                ((total++))
                printf "Testing patch %s %-50s ... " "$patch_num" "$(basename "$patch_file")"
                
                result=$(test_patch "$PROJECT_ROOT/$patch_file" "$patch_num")
                printf "%s\n" "$result"
                
                case "$result" in
                    "CLEAN")
                        ((clean++))
                        echo "$patch_num|$patch_file|CLEAN|sed -i 's/^#Patch${patch_num}:/Patch${patch_num}:/' linux.spec && sed -i 's/^#%patch${patch_num}/%patch${patch_num}/' linux.spec" >> "$results_file"
                        ;;
                    "FUZZY")
                        ((fuzzy++))
                        echo "$patch_num|$patch_file|FUZZY|# May work with fuzz - sed -i 's/^#Patch${patch_num}:/Patch${patch_num}:/' linux.spec && sed -i 's/^#%patch${patch_num}/%patch${patch_num}/' linux.spec" >> "$results_file"
                        ;;
                    "FAILED")
                        ((failed++))
                        echo "$patch_num|$patch_file|FAILED|# Needs manual update" >> "$results_file"
                        ;;
                    "MISSING")
                        ((missing++))
                        echo "$patch_num|$patch_file|MISSING|# Patch file not found" >> "$results_file"
                        ;;
                esac
            fi
        fi
    done < <(grep "^#Patch[0-9]" "$SPEC_FILE")
    
    echo
    log_info "Test Results Summary:"
    printf "  Total tested: %d\n" $total
    printf "  ${GREEN}Clean applies: %d${NC}\n" $clean
    printf "  ${YELLOW}Fuzzy applies: %d${NC}\n" $fuzzy
    printf "  ${RED}Failed applies: %d${NC}\n" $failed
    printf "  Missing files: %d\n" $missing
    echo
    log_info "Results saved to: $results_file"
}

# Enable clean patches
enable_clean() {
    results_file="${WORKDIR}/test-results.txt"
    
    if [[ ! -f "$results_file" ]]; then
        log_error "No test results found. Run: $0 test"
        exit 1
    fi
    
    log_info "Enabling patches that apply cleanly..."
    
    enabled=0
    while IFS='|' read -r patch_num patch_file result commands; do
        [[ $patch_num == \#* ]] && continue
        
        if [[ "$result" == "CLEAN" ]]; then
            log_info "Enabling patch $patch_num: $patch_file"
            sed -i "s/^#Patch${patch_num}:/Patch${patch_num}:/" "$SPEC_FILE"
            sed -i "s/^#%patch${patch_num}/%patch${patch_num}/" "$SPEC_FILE"
            ((enabled++))
        fi
    done < "$results_file"
    
    log_success "Enabled $enabled patches"
}

# Enable fuzzy patches
enable_fuzzy() {
    results_file="${WORKDIR}/test-results.txt"
    
    if [[ ! -f "$results_file" ]]; then
        log_error "No test results found. Run: $0 test"
        exit 1
    fi
    
    log_warning "Enabling patches that apply with fuzz (may cause issues)..."
    
    enabled=0
    while IFS='|' read -r patch_num patch_file result commands; do
        [[ $patch_num == \#* ]] && continue
        
        if [[ "$result" == "FUZZY" ]]; then
            log_warning "Enabling fuzzy patch $patch_num: $patch_file"
            sed -i "s/^#Patch${patch_num}:/Patch${patch_num}:/" "$SPEC_FILE"
            sed -i "s/^#%patch${patch_num}/%patch${patch_num}/" "$SPEC_FILE"
            ((enabled++))
        fi
    done < "$results_file"
    
    log_success "Enabled $enabled fuzzy patches"
}

# Show results
show_results() {
    results_file="${WORKDIR}/test-results.txt"
    
    if [[ ! -f "$results_file" ]]; then
        log_error "No test results found. Run: $0 test"
        exit 1
    fi
    
    echo "Patch Test Results for Linux $KERNEL_VERSION:"
    echo "=============================================="
    echo
    
    printf "%-8s %-50s %s\n" "PATCH#" "FILENAME" "RESULT"
    printf "%-8s %-50s %s\n" "------" "--------" "------"
    
    while IFS='|' read -r patch_num patch_file result commands; do
        [[ $patch_num == \#* ]] && continue
        
        case "$result" in
            "CLEAN")
                printf "%-8s %-50s ${GREEN}%s${NC}\n" "$patch_num" "$(basename "$patch_file")" "$result"
                ;;
            "FUZZY")
                printf "%-8s %-50s ${YELLOW}%s${NC}\n" "$patch_num" "$(basename "$patch_file")" "$result"
                ;;
            "FAILED")
                printf "%-8s %-50s ${RED}%s${NC}\n" "$patch_num" "$(basename "$patch_file")" "$result"
                ;;
            "MISSING")
                printf "%-8s %-50s %s\n" "$patch_num" "$(basename "$patch_file")" "$result"
                ;;
        esac
    done < "$results_file"
    
    echo
    echo "Commands to enable clean patches:"
    echo "================================="
    while IFS='|' read -r patch_num patch_file result commands; do
        [[ $patch_num == \#* ]] && continue
        if [[ "$result" == "CLEAN" ]]; then
            echo "$commands"
        fi
    done < "$results_file"
}

# Show help
show_help() {
    cat << EOF
Clear Linux Patch Tester

Usage: $0 [COMMAND]

Commands:
    download        Download and extract kernel source
    test            Test all disabled patches against current kernel
    results         Show test results in a formatted table
    enable-clean    Enable all patches that apply cleanly
    enable-fuzzy    Enable all patches that apply with fuzz (risky)
    help            Show this help

Workflow:
    1. $0 download      # Download kernel source (once)
    2. $0 test          # Test all disabled patches
    3. $0 results       # Review results
    4. $0 enable-clean  # Enable safe patches

Examples:
    $0 download && $0 test && $0 enable-clean

The script tests patches by:
1. Creating a temporary copy of the kernel source
2. Attempting to apply each disabled patch
3. Reporting whether it applies cleanly, with fuzz, or fails
4. Providing commands to re-enable working patches

EOF
}

case "${1:-help}" in
    download)
        download_kernel
        ;;
    test)
        test_disabled
        ;;
    results)
        show_results
        ;;
    enable-clean)
        enable_clean
        ;;
    enable-fuzzy)
        enable_fuzzy
        ;;
    help|*)
        show_help
        ;;
esac
