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

# Build the kernel-enhanced container
echo "Building Clear Linux kernel container..."
echo "This will take 30-60 minutes depending on your system"
echo ""

podman build \
  --build-arg BASE_IMAGE="$BASE_IMAGE" \
  -t clear-linux-kernel-bootc:latest \
  -f Containerfile \
  .

echo ""
echo "=== Build Complete ==="
echo "Container image: clear-linux-kernel-bootc:latest"
echo ""
echo "To test the container:"
echo "podman run --rm -it clear-linux-kernel-bootc:latest /bin/bash"
echo ""
echo "To check the kernel:"
echo "podman run --rm clear-linux-kernel-bootc:latest ls -la /usr/lib/kernel/"
echo ""
echo "To deploy with bootc:"
echo "bootc switch --image clear-linux-kernel-bootc:latest"