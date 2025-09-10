# Clear Linux Kernel Build Justfile
# Provides convenient commands for building and managing Clear Linux kernel

# Default recipe - show available commands
default:
    @just --list

# Build kernel container with current spec
build:
    #!/usr/bin/env bash
    echo "🔨 Building kernel container..."
    ./scripts/build-example.sh ghcr.io/tuna-os/yellowfin-dx:latest

# Prepare local kernel source in temp-kernel
prepare-local-kernel:
    #!/usr/bin/env bash
    echo "📦 Preparing local kernel source..."
    KERNEL_VERSION=$(grep "^Version:" linux.spec | awk '{print $2}')
    echo "Kernel version: ${KERNEL_VERSION}"
    
    mkdir -p temp-kernel
    cd temp-kernel
    
    if [ ! -f "linux-${KERNEL_VERSION}.tar.xz" ]; then
        echo "Downloading kernel ${KERNEL_VERSION}..."
        wget -O linux-${KERNEL_VERSION}.tar.xz \
        https://cdn.kernel.org/pub/linux/kernel/v6.x/linux-${KERNEL_VERSION}.tar.xz
        echo "✅ Kernel source ready in temp-kernel/"
    else
        echo "✅ Kernel source already exists in temp-kernel/"
    fi

# Build kernel container using local temp-kernel if available  
build-local:
    #!/usr/bin/env bash
    echo "🔨 Building kernel container with local sources..."
    # Check if temp-kernel exists and has kernel tarball
    KERNEL_VERSION=$(grep "^Version:" linux.spec | awk '{print $2}')
    if [ -f "temp-kernel/linux-${KERNEL_VERSION}.tar.xz" ]; then
        echo "✅ Using local kernel source"
        ./scripts/build-example.sh ghcr.io/tuna-os/yellowfin-dx:latest
    else
        echo "❌ No local kernel source found in temp-kernel/"
        echo "Run 'just prepare-local-kernel' first"
        exit 1
    fi

# Build with bluefin-dx LTS base image  
build-bluefin:
    @echo "🔨 Building Clear Linux kernel with bluefin-dx LTS base..."
    ./scripts/build-example.sh ghcr.io/ublue-os/bluefin-dx:lts

# Build with custom base image
build-custom BASE_IMAGE:
    @echo "🔨 Building Clear Linux kernel with custom base: {{BASE_IMAGE}}"
    ./scripts/build-example.sh {{BASE_IMAGE}}

# Download kernel source for patch testing
download-kernel:
    @echo "📥 Downloading kernel source for patch testing..."
    ./scripts/patch-tester.sh download

# Test patches against current kernel version  
test-patches:
    #!/usr/bin/env bash
    echo "🧪 Testing patches against kernel..."
    ./scripts/patch-tester.sh test

# Test patches cumulatively (like the real build)
test-cumulative:
    #!/usr/bin/env bash
    echo "🔄 Testing cumulative patch application..."
    ./scripts/cumulative-patch-tester.sh test

# Show patch test results in formatted table
show-results:
    @echo "📊 Showing patch test results..."
    ./scripts/patch-tester.sh results

# Enable all patches that apply cleanly
enable-clean-patches:
    @echo "✅ Enabling patches that apply cleanly..."
    ./scripts/patch-tester.sh enable-clean

# Enable patches that apply with fuzz (risky)
enable-fuzzy-patches:
    @echo "⚠️  Enabling patches that apply with fuzz (may cause issues)..."
    ./scripts/patch-tester.sh enable-fuzzy

# Show current patch status overview
patch-status:
    @echo "📋 Current patch status:"
    ./scripts/simple-patch-status.sh

# Full patch workflow: download, test, enable clean patches
patch-workflow:
    @echo "🔄 Running full patch compatibility workflow..."
    ./scripts/patch-tester.sh download
    ./scripts/patch-tester.sh test
    ./scripts/patch-tester.sh enable-clean
    @echo "✅ Patch workflow complete. Review results with: just show-results"

# Quick build test with current patch configuration
test-build BASE_IMAGE="ghcr.io/tuna-os/yellowfin-dx:latest":
    @echo "🚀 Testing build with current patch configuration..."
    ./scripts/build-example.sh {{BASE_IMAGE}}

# Quick build test using local kernel source (faster, no download)
test-build-local BASE_IMAGE="ghcr.io/tuna-os/yellowfin-dx:latest":
    #!/usr/bin/env bash
    echo "🚀 Testing build with local kernel source..."
    KERNEL_VERSION=$(grep "^Version:" linux.spec | awk '{print $2}')
    if [ -f "temp-kernel/linux-${KERNEL_VERSION}.tar.xz" ]; then
        echo "✅ Using local kernel source"
        USE_LOCAL_KERNEL=true ./scripts/build-example.sh {{BASE_IMAGE}}
    else
        echo "❌ No local kernel source. Run 'just prepare-local-kernel' first"
        exit 1
    fi

# Complete development workflow
dev-workflow:
    #!/usr/bin/env bash
    echo "� Running complete development workflow..."
    echo "1. Testing cumulative patch application..."
    just test-cumulative
    echo "2. Testing build..."
    just test-build

# Clean up patch testing artifacts
clean-patch-testing:
    @echo "🧹 Cleaning up patch testing artifacts..."
    rm -rf patch-testing/test-*
    @echo "✅ Cleanup complete"

# Clean up all build artifacts
clean-all:
    @echo "🧹 Cleaning up all build artifacts..."
    rm -rf patch-testing/
    podman image prune -f
    @echo "✅ Full cleanup complete"

# Show kernel version from spec file
show-kernel-version:
    @echo "🐧 Current kernel version:"
    @grep "^Version:" linux.spec | awk '{print $2}'

# Show patch statistics
patch-stats:
    @echo "📈 Patch Statistics:"
    @echo "Enabled patches:  $(grep -c "^Patch[0-9]" linux.spec)"
    @echo "Disabled patches: $(grep -c "^#Patch[0-9]" linux.spec)"
    @echo "Total patches:    $(grep -c "Patch[0-9]" linux.spec)"

# Validate spec file syntax
validate-spec:
    @echo "✅ Validating linux.spec syntax..."
    @rpmlint linux.spec || echo "❌ Spec file validation failed"

# Search for specific patch by number
find-patch PATCH_NUM:
    @echo "🔍 Searching for patch {{PATCH_NUM}}:"
    @grep -n "{{PATCH_NUM}}" linux.spec || echo "Patch {{PATCH_NUM}} not found"

# Enable specific patch by number
enable-patch PATCH_NUM:
    @echo "🔧 Enabling patch {{PATCH_NUM}}..."
    sed -i 's/^#Patch{{PATCH_NUM}}:/Patch{{PATCH_NUM}}:/' linux.spec
    sed -i 's/^#%patch{{PATCH_NUM}}/%patch{{PATCH_NUM}}/' linux.spec
    @echo "✅ Patch {{PATCH_NUM}} enabled"

# Disable specific patch by number
disable-patch PATCH_NUM:
    @echo "🔧 Disabling patch {{PATCH_NUM}}..."
    sed -i 's/^Patch{{PATCH_NUM}}:/#Patch{{PATCH_NUM}}:/' linux.spec
    sed -i 's/^%patch{{PATCH_NUM}}/#%patch{{PATCH_NUM}}/' linux.spec
    @echo "✅ Patch {{PATCH_NUM}} disabled"

# Show git status and changes
git-status:
    @echo "📝 Git status:"
    @git status --short
    @echo "\n🔄 Modified files:"
    @git diff --name-only

# Create development branch for patch testing
create-patch-branch BRANCH_NAME:
    @echo "🌟 Creating patch testing branch: {{BRANCH_NAME}}"
    git checkout -b patch-test/{{BRANCH_NAME}}
    @echo "✅ Branch created. Make your patch changes and use 'just test-build' to verify"

# Show container images
show-images:
    @echo "🐳 Available container images:"
    @podman images | grep -E "(clear-linux|yellowfin|bluefin)" || echo "No Clear Linux related images found"

# Tag and push built image
tag-and-push REGISTRY_URL TAG="latest":
    @echo "🏷️  Tagging and pushing image..."
    podman tag clear-linux-kernel:latest {{REGISTRY_URL}}/clear-linux-kernel:{{TAG}}
    podman push {{REGISTRY_URL}}/clear-linux-kernel:{{TAG}}
    @echo "✅ Image pushed to {{REGISTRY_URL}}/clear-linux-kernel:{{TAG}}"

# Run GitHub Actions workflow locally (requires act)
test-ci:
    @echo "🎭 Running GitHub Actions workflow locally..."
    act -j build-and-push

# Show help for patch management
patch-help:
    @echo "🆘 Patch Management Help:"
    @echo ""
    @echo "Basic workflow:"
    @echo "  just download-kernel     # Download kernel source (once)"
    @echo "  just test-patches        # Test patch compatibility" 
    @echo "  just show-results        # Review test results"
    @echo "  just enable-clean-patches # Enable safe patches"
    @echo "  just test-build          # Test build with current patches"
    @echo ""
    @echo "Individual patch management:"
    @echo "  just find-patch 0106     # Find specific patch"
    @echo "  just enable-patch 0106   # Enable specific patch"
    @echo "  just disable-patch 0106  # Disable specific patch"
    @echo ""
    @echo "Development workflow:"
    @echo "  just dev-workflow        # Full dev cycle: test, enable, build"
    @echo "  just patch-workflow      # Patch-only cycle: download, test, enable"

# Show help for building
build-help:
    @echo "🆘 Build Help:"
    @echo ""
    @echo "Quick builds:"
    @echo "  just build-yellowfin     # Build with yellowfin-dx base"
    @echo "  just build-bluefin       # Build with bluefin-dx LTS base"
    @echo "  just build-custom IMAGE  # Build with custom base image"
    @echo ""
    @echo "Local kernel builds (faster):"
    @echo "  just prepare-local-kernel    # Download kernel to temp-kernel/"
    @echo "  just build-local            # Build using local kernel source"
    @echo "  just test-build-local       # Quick test with local kernel"
    @echo ""
    @echo "Testing builds:"
    @echo "  just test-build          # Quick build test"
    @echo "  just dev-workflow        # Full development workflow"
    @echo ""
    @echo "Publishing:"
    @echo "  just tag-and-push REGISTRY TAG # Tag and push to registry"
    @echo "  just show-images         # Show available images"

# Interactive patch management menu
interactive-patches:
    @echo "🎯 Interactive Patch Management"
    @echo "1. Show current status"
    @echo "2. Test patch compatibility"
    @echo "3. Enable clean patches"
    @echo "4. Show test results"
    @echo "5. Run full workflow"
    @read -p "Choose option (1-5): " opt; \
    case $$opt in \
        1) just patch-status ;; \
        2) just test-patches ;; \
        3) just enable-clean-patches ;; \
        4) just show-results ;; \
        5) just patch-workflow ;; \
        *) echo "Invalid option" ;; \
    esac

# Show system requirements and dependencies
check-deps:
    @echo "🔍 Checking system dependencies..."
    @command -v podman >/dev/null 2>&1 && echo "✅ podman: installed" || echo "❌ podman: missing"
    @command -v git >/dev/null 2>&1 && echo "✅ git: installed" || echo "❌ git: missing"
    @command -v patch >/dev/null 2>&1 && echo "✅ patch: installed" || echo "❌ patch: missing"
    @command -v wget >/dev/null 2>&1 && echo "✅ wget: installed" || echo "❌ wget: missing"
    @command -v rpmlint >/dev/null 2>&1 && echo "✅ rpmlint: installed" || echo "⚠️  rpmlint: missing (optional)"
    @command -v act >/dev/null 2>&1 && echo "✅ act: installed" || echo "⚠️  act: missing (optional)"
