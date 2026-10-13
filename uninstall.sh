#!/usr/bin/env bash
set -euo pipefail
PKG_NAME="st-accel-sam0201"
PKG_VERSION="1.0"

sudo modprobe -r st_accel_i2c st_accel 2>/dev/null || true
sudo dkms remove -m "$PKG_NAME" -v "$PKG_VERSION" --all
sudo rm -rf "/usr/src/${PKG_NAME}-${PKG_VERSION}"
echo "Removed. In-kernel stock st_accel/st_accel_i2c will be used (without SAM0201 support) on next load."
