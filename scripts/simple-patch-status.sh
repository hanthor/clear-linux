#!/bin/bash

# Simple patch status checker
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
SPEC_FILE="${PROJECT_ROOT}/linux.spec"
KERNEL_VERSION=$(grep -E "^Version:" "$SPEC_FILE" | awk '{print $2}')

echo "Clear Linux Patch Status for Kernel $KERNEL_VERSION"
echo "=================================================="
echo

enabled=0
disabled=0

echo "ENABLED PATCHES:"
echo "----------------"
while IFS= read -r line; do
    if [[ $line =~ ^Patch([0-9]+):[[:space:]]*(.+\.patch)$ ]]; then
        patch_num="${BASH_REMATCH[1]}"
        patch_file="${BASH_REMATCH[2]}"
        
        # Check if application line exists and is not commented
        if grep -q "^%patch ${patch_num}" "$SPEC_FILE"; then
            echo "  $patch_num: $patch_file"
            ((enabled++))
        fi
    fi
done < "$SPEC_FILE"

echo
echo "DISABLED PATCHES:"
echo "-----------------"
while IFS= read -r line; do
    if [[ $line =~ ^(#)?Patch([0-9]+):[[:space:]]*(.+\.patch)$ ]]; then
        comment_prefix="${BASH_REMATCH[1]}"
        patch_num="${BASH_REMATCH[2]}"
        patch_file="${BASH_REMATCH[3]}"
        
        # Check if declaration is commented OR application is commented/missing
        if [[ -n "$comment_prefix" ]] || grep -q "^#%patch ${patch_num}" "$SPEC_FILE" || ! grep -q "^%patch${patch_num}" "$SPEC_FILE"; then
            if [[ -n "$comment_prefix" ]]; then
                echo "  $patch_num: $patch_file (declaration commented)"
            elif grep -q "^#%patch ${patch_num}" "$SPEC_FILE"; then
                echo "  $patch_num: $patch_file (application commented)"
            else
                echo "  $patch_num: $patch_file (no application found)"
            fi
            ((disabled++))
        fi
    fi
done < "$SPEC_FILE"

echo
echo "Summary: $enabled enabled, $disabled disabled"
echo

echo "PATCHES THAT COULD BE RE-ENABLED:"
echo "=================================="
echo "The following disabled patches might work with kernel $KERNEL_VERSION:"
echo

# List some specific patches that are likely to be safe to re-enable
while IFS= read -r line; do
    if [[ $line =~ ^#Patch([0-9]+):[[:space:]]*(.+\.patch)$ ]]; then
        patch_num="${BASH_REMATCH[1]}"
        patch_file="${BASH_REMATCH[2]}"
        
        # Check if both declaration and application are commented
        if grep -q "^#% ${patch_num}" "$SPEC_FILE"; then
            echo "  $patch_num: $patch_file"
            echo "    To enable: sed -i 's/^#Patch${patch_num}:/Patch${patch_num}:/'' linux.spec"
            echo "               sed -i 's/^#%patch ${patch_num}/%patch ${patch_num}/' linux.spec"
            echo
        fi
    fi
done < "$SPEC_FILE"
