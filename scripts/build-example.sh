#!/bin/bash

# Example build script for Clear Linux kernel with bootc container
# This demonstrates how to use the Containerfile with common bootc images

set -e

echo "=== Clear Linux Kernel Build Example ==="

# Common bootc base images
FEDORA_BOOTC="quay.io/fedora/fedora-bootc:40"
CENTOS_BOOTC="quay.io/centos-bootc/centos-bootc:stream9"

echo "Available bootc base images:"
echo "1. Fedora 40 bootc: $FEDORA_BOOTC"
echo "2. CentOS Stream 9 bootc: $CENTOS_BOOTC"
echo ""

# Get user choice or use default
BASE_IMAGE="${1:-$FEDORA_BOOTC}"
echo "Using base image: $BASE_IMAGE"
echo ""

# Check if temp-kernel has a kernel tarball
KERNEL_VERSION=$(grep "^Version:" linux.spec | awk '{print $2}')
USE_LOCAL_KERNEL="false"

if [ -f "temp-kernel/linux-${KERNEL_VERSION}.tar.xz" ]; then
    USE_LOCAL_KERNEL="true"
    echo "✅ Found local kernel source: temp-kernel/linux-${KERNEL_VERSION}.tar.xz"
    echo "Using local kernel source instead of downloading"
else
    echo "⬇️ Local kernel source not found, will download from kernel.org"
fi
echo ""

# Get BASE_IMAGE name minus tag for naming
BASE_NAME=$(echo "$BASE_IMAGE" | sed 's/[:\/]/-/g')
echo "Base image name for tagging: $BASE_NAME"
echo ""

# Build the kernel-enhanced container
echo "Building Clear Linux kernel container..."
echo "This will take 30-60 minutes depending on your system"
echo ""

podman build \
  --build-arg BASE_IMAGE="$BASE_IMAGE" \
  --build-arg USE_LOCAL_KERNEL="$USE_LOCAL_KERNEL" \
  -t $BASE_NAME:intel \
  -f Containerfile \
  .

echo ""
echo "=== Build Complete ==="
echo "Container image: $BASE_NAME:intel"
echo ""
echo "To test the container:"
echo "podman run --rm -it $BASE_NAME:intel /bin/bash"
echo ""
echo "To check the kernel:"
echo "podman run --rm $BASE_NAME:intel ls -la /usr/lib/kernel/"
echo ""
echo "To deploy with bootc:"
echo "bootc switch $BASE_NAME:intel"