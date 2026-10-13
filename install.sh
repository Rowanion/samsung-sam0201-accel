#!/usr/bin/env bash
set -euo pipefail

PKG_NAME="st-accel-sam0201"
PKG_VERSION="1.0"
SRC_DIR="/usr/src/${PKG_NAME}-${PKG_VERSION}"
KVER="$(uname -r)"
KBUILD_DIR="/usr/src/kernels/${KVER}"
WORKDIR="$(mktemp -d)"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

cleanup() { rm -rf "$WORKDIR"; }
trap cleanup EXIT

echo "==> Checking for ACPI device SAM0201 (Samsung K2HH/LIS2HH12-compatible accelerometer)..."
if ! ls /sys/bus/acpi/devices/ 2>/dev/null | grep -q '^SAM0201'; then
    echo "ERROR: No ACPI device with HID SAM0201 found on this system."
    echo "This fix only applies to Samsung Galaxy Book devices exposing this ACPI ID"
    echo "(confirmed working on Galaxy Book 10.6 / SM-W620, originally Galaxy Book 12)."
    echo "Detected: $(cat /sys/class/dmi/id/sys_vendor 2>/dev/null) $(cat /sys/class/dmi/id/product_name 2>/dev/null) ($(cat /sys/class/dmi/id/product_version 2>/dev/null))"
    exit 1
fi
echo "    Found. Detected as: $(cat /sys/class/dmi/id/sys_vendor 2>/dev/null) $(cat /sys/class/dmi/id/product_name 2>/dev/null) ($(cat /sys/class/dmi/id/product_version 2>/dev/null))"

echo "==> Installing build dependencies..."
sudo dnf install -y dkms patch gcc make "kernel-devel-${KVER}" curl tar xz

if [ ! -d "$KBUILD_DIR" ]; then
    echo "ERROR: ${KBUILD_DIR} not found even after installing kernel-devel-${KVER}."
    echo "Your running kernel and installed kernel-devel may be out of sync"
    echo "(common right after a kernel update, before reboot). Reboot and retry."
    exit 1
fi

KVER_BASE="$(echo "$KVER" | sed -E 's/-.*//')"
KMAJOR="$(echo "$KVER_BASE" | cut -d. -f1)"
TARBALL="linux-${KVER_BASE}.tar.xz"
URL="https://cdn.kernel.org/pub/linux/kernel/v${KMAJOR}.x/${TARBALL}"

echo "==> Fetching vanilla kernel source for ${KVER_BASE} (needed: 4 small files from drivers/iio/accel)..."
echo "    ${URL}"
curl -fL -o "${WORKDIR}/${TARBALL}" "$URL"
tar -xf "${WORKDIR}/${TARBALL}" -C "$WORKDIR" \
    "linux-${KVER_BASE}/drivers/iio/accel/st_accel_core.c" \
    "linux-${KVER_BASE}/drivers/iio/accel/st_accel_buffer.c" \
    "linux-${KVER_BASE}/drivers/iio/accel/st_accel_i2c.c" \
    "linux-${KVER_BASE}/drivers/iio/accel/st_accel.h"

echo "==> Applying SAM0201 ACPI ID patch..."
patch -p1 -d "${WORKDIR}/linux-${KVER_BASE}" < "${SCRIPT_DIR}/patches/0001-add-SAM0201-acpi-id.patch"

SRC_EXTRACTED="${WORKDIR}/linux-${KVER_BASE}/drivers/iio/accel"

echo "==> Staging DKMS source tree at ${SRC_DIR}..."
sudo rm -rf "$SRC_DIR"
sudo mkdir -p "$SRC_DIR"
sudo cp "${SRC_EXTRACTED}"/st_accel_core.c "${SRC_EXTRACTED}"/st_accel_buffer.c \
        "${SRC_EXTRACTED}"/st_accel_i2c.c "${SRC_EXTRACTED}"/st_accel.h "$SRC_DIR"/

sudo tee "$SRC_DIR/Makefile" > /dev/null <<'EOF'
obj-m += st_accel.o
st_accel-y := st_accel_core.o st_accel_buffer.o
obj-m += st_accel_i2c.o
EOF

sudo tee "$SRC_DIR/dkms.conf" > /dev/null <<EOF
PACKAGE_NAME="${PKG_NAME}"
PACKAGE_VERSION="${PKG_VERSION}"
BUILT_MODULE_NAME[0]="st_accel"
DEST_MODULE_LOCATION[0]="/updates/drivers/iio/accel"
BUILT_MODULE_NAME[1]="st_accel_i2c"
DEST_MODULE_LOCATION[1]="/updates/drivers/iio/accel"
AUTOINSTALL="yes"
MAKE[0]="make -C \${kernel_source_dir} M=\${dkms_tree}/\${PACKAGE_NAME}/\${PACKAGE_VERSION}/build modules"
CLEAN="make -C \${kernel_source_dir} M=\${dkms_tree}/\${PACKAGE_NAME}/\${PACKAGE_VERSION}/build clean"
EOF

echo "==> Registering with DKMS..."
sudo dkms remove -m "$PKG_NAME" -v "$PKG_VERSION" --all 2>/dev/null || true
sudo dkms add -m "$PKG_NAME" -v "$PKG_VERSION"
sudo dkms build -m "$PKG_NAME" -v "$PKG_VERSION"
sudo dkms install -m "$PKG_NAME" -v "$PKG_VERSION"

echo "==> Loading module..."
sudo modprobe -r st_accel_i2c st_accel 2>/dev/null || true
sudo modprobe st_accel_i2c
sleep 1

echo "==> Verifying..."
found=0
for f in /sys/bus/iio/devices/iio:device*/name; do
    [ -f "$f" ] && grep -q lis2hh12 "$f" && { echo "    SUCCESS: $(dirname "$f") -> lis2hh12"; found=1; }
done
[ "$found" -eq 1 ] || { echo "WARNING: no iio device reporting 'lis2hh12'. Check: dmesg -T | tail -30"; exit 1; }

echo "==> Done. Also run: gsettings set org.gnome.settings-daemon.peripherals.touchscreen orientation-lock false"
