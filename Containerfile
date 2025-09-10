# Containerfile for building Clear Linux kernel and replacing it in a bootc container
# Usage: podman build --build-arg BASE_IMAGE=<your-bootc-image> -t kernel-updated-image .

ARG BASE_IMAGE
ARG USE_LOCAL_KERNEL=false
FROM ${BASE_IMAGE} as builder

# Install build dependencies for kernel compilation
RUN dnf install -y \
    rpm-build \
    rpmdevtools \
    gcc \
    gcc-c++ \
    make \
    binutils \
    elfutils-libelf-devel \
    openssl-devel \
    dwarves \
    python3-devel \
    perl \
    bc \
    tar \
    xz \
    gzip \
    flex \
    bison \
    pahole \
    rsync \
    zstd \
    wget \
    git \
    patch \
    findutils \
    ncurses-devel \
    which \
    diffutils \
    hostname \
    kmod \
    cpio \
    bzip2 \
    xz-devel \
    zlib-devel \
    libzstd-devel \
    ncurses-devel \
    elfutils-devel \
    binutils-devel \
    net-tools \
    gawk \
    && dnf clean all

# Set up build environment
WORKDIR /tmp/kernel-build

# Copy the kernel spec and related files
COPY linux.spec .
COPY config .
COPY cmdline .
COPY *.patch .
COPY options.conf .
COPY release .
COPY upstream .

# Ensure root's home directory is properly configured for OSTree systems
# In OSTree systems, /root is a symlink to /var/roothome
RUN mkdir -p /var/roothome && \
    if [ -L /root ] && [ "$(readlink /root)" = "/var/roothome" ]; then \
        echo "OSTree system detected: /root -> /var/roothome"; \
    elif [ ! -d /root ]; then \
        mkdir -p /root; \
    fi && \
    if ! grep -q "^root:.*:/root:" /etc/passwd; then \
        sed -i 's|^root:[^:]*:[^:]*:[^:]*:[^:]*:[^:]*:.*$|root:x:0:0:root:/root:/bin/bash|' /etc/passwd; \
    fi

# Create RPM build directories
RUN rpmdev-setuptree

# Copy local temp-kernel source if USE_LOCAL_KERNEL is true
ARG USE_LOCAL_KERNEL
COPY temp-kernel/ ./temp-kernel/

# Use local temp-kernel if available, otherwise download kernel source
RUN KERNEL_VERSION=$(grep "^Version:" linux.spec | awk '{print $2}') && \
    echo "Kernel version: ${KERNEL_VERSION}" && \
    echo "USE_LOCAL_KERNEL: ${USE_LOCAL_KERNEL}" && \
    cd ~/rpmbuild/SOURCES && \
    if [ "${USE_LOCAL_KERNEL}" = "true" ] && [ -f "/tmp/kernel-build/temp-kernel/linux-${KERNEL_VERSION}.tar.xz" ]; then \
        echo "✅ Using local temp-kernel source..." && \
        cp /tmp/kernel-build/temp-kernel/linux-${KERNEL_VERSION}.tar.xz . && \
        echo "Local kernel source: $(ls -lh linux-${KERNEL_VERSION}.tar.xz)"; \
    else \
        echo "⬇️ Downloading kernel ${KERNEL_VERSION} from kernel.org..." && \
        wget -O linux-${KERNEL_VERSION}.tar.xz \
        https://cdn.kernel.org/pub/linux/kernel/v6.x/linux-${KERNEL_VERSION}.tar.xz && \
        echo "Downloaded kernel source: $(ls -lh linux-${KERNEL_VERSION}.tar.xz)"; \
    fi

# Copy spec and source files to RPM build directories
RUN cp linux.spec ~/rpmbuild/SPECS/ && \
    cp config ~/rpmbuild/SOURCES/ && \
    cp cmdline ~/rpmbuild/SOURCES/ && \
    cp *.patch ~/rpmbuild/SOURCES/ 2>/dev/null || true

# Build the kernel RPM packages
RUN cd ~/rpmbuild/SPECS && \
    echo "Starting kernel build - this may take 30-60 minutes..." && \
    rpmbuild -ba linux.spec && \
    echo "Build completed. Generated RPMs:" && \
    ls -la ~/rpmbuild/RPMS/x86_64/

# Create the final stage with the new kernel
FROM ${BASE_IMAGE}

# Copy the built RPMs from the build stage
COPY --from=builder /root/rpmbuild/RPMS/x86_64/*.rpm /tmp/

# Back up the existing kernel files and install the new kernel
RUN mkdir -p /usr/lib/kernel.backup && \
    cp -r /usr/lib/kernel/* /usr/lib/kernel.backup/ 2>/dev/null || true && \
    cp -r /usr/lib/modules /usr/lib/modules.backup 2>/dev/null || true

# Install the new kernel packages
RUN rpm -Uvh --force /tmp/linux-*.rpm

# Update the bootloader configuration to use the new kernel
RUN if [ -f /usr/lib/kernel/default-native ]; then \
        NEW_KERNEL=$(readlink /usr/lib/kernel/default-native) && \
        echo "New kernel: $NEW_KERNEL" && \
        # Update grub if it exists
        if command -v grub2-mkconfig >/dev/null 2>&1; then \
            grub2-mkconfig -o /boot/grub2/grub.cfg 2>/dev/null || true; \
        fi; \
        # Update systemd-boot if it exists
        if [ -d /boot/loader ]; then \
            bootctl update 2>/dev/null || true; \
        fi; \
    fi

# Clean up temporary files
RUN rm -rf /tmp/*.rpm

# Verify the kernel installation
RUN ls -la /usr/lib/kernel/ && \
    echo "Available kernels:" && \
    ls -la /usr/lib/kernel/org.clearlinux.* 2>/dev/null || echo "No Clear Linux kernels found" && \
    echo "Kernel modules:" && \
    ls -la /usr/lib/modules/ | head -10

# Add a label to identify this as a custom kernel image
LABEL description="Bootc container with Clear Linux custom kernel"
LABEL kernel.source="Clear Linux optimized kernel"

# Set working directory back to root
WORKDIR /