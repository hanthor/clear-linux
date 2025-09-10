#!/bin/bash

SPEC_FILE="linux.spec"

echo "Testing regex pattern..."

while IFS= read -r line; do
    echo "Processing line: $line"
    if [[ $line =~ ^#Patch([0-9]+):[[:space:]]*(.+\.patch)$ ]]; then
        patch_num="${BASH_REMATCH[1]}"
        patch_file="${BASH_REMATCH[2]}"
        
        echo "Found: patch_num=$patch_num, patch_file=$patch_file"
        
        # Check if application is also commented
        if grep -q "^#%patch ${patch_num}" "$SPEC_FILE"; then
            echo "  Application is also commented - this would be tested"
        else
            echo "  Application is NOT commented - this would be skipped"
        fi
    else
        echo "  No match with regex"
    fi
done < <(grep "^#Patch[0-9]" "$SPEC_FILE" | head -3)
