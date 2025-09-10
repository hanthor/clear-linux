# Clear Linux Kernel Containerfile

This Containerfile builds the Clear Linux optimized kernel from the specifications in this repository and replaces the kernel in a bootc container.

## Usage

```bash
# Build with your bootc base image
podman build --build-arg BASE_IMAGE=<your-bootc-image> -t kernel-updated-image .

# Example with a specific bootc image
podman build --build-arg BASE_IMAGE=quay.io/fedora/fedora-bootc:40 -t clear-linux-kernel-bootc .
```

## What it does

1. **Multi-stage build**: Uses the provided base image to create a build environment
2. **Kernel compilation**: Downloads kernel source and builds using the Clear Linux spec file with all optimizations and patches
3. **Kernel replacement**: Installs the new kernel packages and replaces the existing kernel in the bootc container
4. **Bootloader update**: Updates bootloader configuration to use the new kernel
5. **Cleanup**: Removes build dependencies to keep the final image size reasonable

## Features

- Preserves original kernel as backup in `/usr/lib/kernel.backup/`
- Applies all Clear Linux performance optimizations and patches
- Compatible with bootc containers that have systemd-boot or GRUB
- Multi-stage build keeps final image size optimized

## Build time

Building the kernel can take 30-60 minutes depending on your system's performance.

## Output

The resulting container will have:
- New Clear Linux optimized kernel in `/usr/lib/kernel/`
- Kernel modules in `/usr/lib/modules/`
- Updated bootloader configuration
- Original kernel backed up for safety