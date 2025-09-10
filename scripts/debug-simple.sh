#!/bin/bash

SPEC_FILE="linux.spec"

echo "Testing simple loop..."

while IFS= read -r line; do
    echo "Processing: $line"
    if [[ $line =~ ^#Patch([0-9]+):[[:space:]]*(.+\.patch)$ ]]; then
        patch_num="${BASH_REMATCH[1]}"
        patch_file="${BASH_REMATCH[2]}"
        echo "  Found patch: $patch_num -> $patch_file"
        
        if grep -q "^#%patch ${patch_num}" "$SPEC_FILE"; then
            echo "  ✓ Application is also commented - would test this patch"
        else
            echo "  ✗ Application is NOT commented - would skip"
        fi
    else
        echo "  No regex match"
    fi
done < <(grep "^#Patch[0-9]" "$SPEC_FILE" | head -3)

echo "Done."
