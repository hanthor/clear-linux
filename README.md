# Clear Linux Kernel Build System

A containerized build system for Clear Linux kernel with automated patch management and compatibility testing.

## Overview

This project builds Clear3. Test compatibility: `./scripts/patch-tester.sh test`
4. Build and verify: `./scripts/build-example.sh <base-image>`inux kernel packages in containers with selective patch application based on kernel version compatibility. The system includes tools for testing patch compatibility and automatically enabling/disabling patches for different kernel versions.

## Features

- **Containerized Builds**: Build kernels in clean container environments
- **Multi-Base Support**: Compatible with yellowfin-dx and bluefin-dx container images
- **Automated Patch Testing**: Test patch compatibility against target kernel versions
- **Selective Patch Management**: Enable/disable patches based on compatibility
- **CI/CD Integration**: GitHub Actions workflow for automated builds
- **OSTree Compatibility**: Proper handling of OSTree filesystem structures

## Quick Start

### Prerequisites

- Podman or Docker
- Just command runner (optional but recommended)

### Basic Usage

```bash
# Build with yellowfin-dx base
just build-yellowfin

# Build with bluefin-dx base  
just build-bluefin

# Test patch compatibility
just test-patches

# Enable compatible patches
just enable-clean-patches

# Check current patch status
just patch-status
```

## Build System

### Container Build

The build system uses a multi-stage Containerfile that:

1. **Stage 1**: Sets up build environment with all dependencies
2. **Stage 2**: Downloads and builds kernel with RPM
3. **Stage 3**: Installs kernel into bootc-compatible image

### Supported Base Images

- `ghcr.io/tuna-os/yellowfin-dx:latest` - Fedora-based development environment
- `ghcr.io/ublue-os/bluefin-dx:lts` - Ubuntu-based LTS environment

### Manual Build

```bash
# Build with specific base image
./scripts/build-example.sh ghcr.io/tuna-os/yellowfin-dx:latest

# Tag and push (optional)
podman tag clear-linux-kernel:latest your-registry/clear-linux-kernel:latest
podman push your-registry/clear-linux-kernel:latest
```

## Patch Management

### Current Status (Linux 6.15.9)

- **44 patches enabled** - Tested and compatible
- **10 patches disabled** - Incompatible or requiring updates
- **15 patches recently re-enabled** through compatibility testing

### Patch Categories

**Performance Patches:**
- CPU idle state optimizations (intel_idle tweaks)
- Memory allocation scaling
- Network performance improvements
- Scheduler optimizations

**Hardware Support:**
- Intel ADL/RDT improvements
- ACPI buffer alignment
- Power management enhancements

**System Features:**
- Stateless firmware loading
- Boot optimization patches
- Debug and monitoring improvements

### Patch Testing Workflow

1. **Download kernel source**: `./scripts/patch-tester.sh download`
2. **Test all disabled patches**: `./scripts/patch-tester.sh test`
3. **Review results**: `./scripts/patch-tester.sh results`
4. **Enable clean patches**: `./scripts/patch-tester.sh enable-clean`
5. **Test build**: `./scripts/build-example.sh <base-image>`

### Patch Test Results

| Result | Description | Action |
|--------|-------------|--------|
| 🟢 CLEAN | Applies perfectly | Safe to enable |
| 🟡 FUZZY | Applies with fuzz | Needs testing |
| 🔴 FAILED | Cannot apply | Needs manual update |
| ⚪ MISSING | File not found | Check file existence |

## Tools

### scripts/patch-tester.sh

Comprehensive patch compatibility testing tool:

```bash
./scripts/patch-tester.sh download      # Download kernel source
./scripts/patch-tester.sh test          # Test all disabled patches
./scripts/patch-tester.sh results       # Show formatted results
./scripts/patch-tester.sh enable-clean  # Auto-enable safe patches
./scripts/patch-tester.sh enable-fuzzy  # Enable risky patches
```

### scripts/simple-patch-status.sh

Quick patch status overview:

```bash
./scripts/simple-patch-status.sh        # Show current patch status
```

### scripts/build-example.sh

Container build script:

```bash
./scripts/build-example.sh <base-image> # Build with specific base
```

## Configuration

### linux.spec

The RPM spec file defines:
- Kernel version (currently 6.15.9)
- Build dependencies
- Patch declarations and applications
- Build configuration

### Containerfile

Multi-stage container definition:
- Build environment setup
- Dependency installation
- Kernel compilation
- Image packaging

## CI/CD

### GitHub Actions

Automated workflow (`.github/workflows/build-and-push.yml`):
- Triggers on push to main branch
- Builds with both base images
- Pushes to GitHub Container Registry
- Matrix build for multiple configurations

### Workflow Steps

1. Checkout code
2. Setup build environment
3. Build container images
4. Test patch compatibility
5. Push successful builds

## Development

### Adding New Patches

1. Add patch file to repository
2. Declare in `linux.spec`: `Patch####: filename.patch`
3. Apply in `linux.spec`: `%patch#### -p1`
4. Test compatibility: `./patch-tester.sh test`
5. Build and verify: `./build-example.sh <base-image>`

### Updating Kernel Version

1. Update `Version:` in `linux.spec`
2. Test all patches: `./scripts/patch-tester.sh download && ./scripts/patch-tester.sh test`
3. Review compatibility: `./scripts/patch-tester.sh results`
4. Enable compatible patches: `./scripts/patch-tester.sh enable-clean`
5. Test build with new configuration

### Debugging Build Issues

1. Check patch compatibility: `./scripts/patch-tester.sh test`
2. Review build logs from container build
3. Verify OSTree compatibility for target environment
4. Test individual patches if needed

## Architecture

### Container Structure

```
├── Containerfile              # Multi-stage build definition
├── linux.spec                 # RPM spec file
├── *.patch                    # Kernel patches
├── scripts/                   # Build and management scripts
│   ├── build-example.sh       # Container build script
│   ├── patch-tester.sh        # Patch testing tool
│   └── simple-patch-status.sh # Status overview
├── justfile                   # Command runner recipes
└── .github/workflows/         # CI/CD automation
```

### Build Process

1. **Environment Setup**: Install build dependencies
2. **Source Preparation**: Download kernel source
3. **Patch Application**: Apply enabled patches
4. **Compilation**: Build kernel with optimizations
5. **Packaging**: Create RPM packages
6. **Installation**: Install into bootc image
7. **Cleanup**: Remove build artifacts

## Performance Optimizations

### Enabled Optimizations

- **CPU Management**: Intel idle state tweaks, scheduler improvements
- **Memory**: Allocation scaling, ACPI buffer alignment
- **Network**: Socket buffer optimization, allocation scaling
- **Storage**: ATA initialization ordering, filesystem optimizations
- **Boot**: Initcall optimization, partition scanning improvements

### Benchmark Results

The enabled patches provide improvements in:
- Boot time reduction
- CPU idle power efficiency
- Memory allocation performance
- Network throughput
- I/O responsiveness

## Troubleshooting

### Common Issues

**Build Failures:**
- Check patch compatibility with `./scripts/patch-tester.sh test`
- Verify all dependencies are installed
- Review OSTree/bootc compatibility

**Patch Application Errors:**
- Use `./scripts/patch-tester.sh results` to identify issues
- Manually review failed patches
- Update patch files for kernel version compatibility

**Container Issues:**
- Ensure base image is available
- Check container runtime (podman/docker)
- Verify network connectivity for downloads

### Support

This is a community-maintained fork focusing on containerized Clear Linux kernel builds with automated patch management.

## License

Kernel patches maintain their original licenses. Build system and tools are provided under appropriate open source licenses.

---

*Note: This is a community fork of the discontinued Intel Clear Linux kernel project, adapted for modern containerized build environments.*
