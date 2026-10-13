# samsung-sam0201-accel

DKMS-packaged kernel patch that adds support for the ACPI device ID `SAM0201` to
the `st_accel_i2c` IIO driver, enabling the built-in accelerometer on Samsung
Galaxy Book devices whose firmware exposes the accelerometer under this
nonstandard ID instead of a standard ST/SMO8xxx HID.

Confirmed working on:

- Samsung Galaxy Book 10.6 (SM-W620)
- Samsung Galaxy Book 12 (SM-W720/SM-W727) — original discovery by
  [fxjosemi/Samsung-Galaxy-Book-12-Linux](https://github.com/fxjosemi/Samsung-Galaxy-Book-12-Linux)

Both expose the accelerometer as ACPI device `SAM0201`, which decodes as a
Kionix K2HH chip, register-compatible with the ST LIS2HH12.

## What it does

`install.sh`:

1. Checks that ACPI device `SAM0201` is actually present on your system.
2. Installs build dependencies (`dkms`, `kernel-devel` matching your running
   kernel, etc.).
3. Downloads the matching vanilla kernel.org source for your exact kernel
   version, pulls just the four `st_accel_*` files it needs.
4. Applies `patches/0001-add-SAM0201-acpi-id.patch`.
5. Registers the patched driver as a DKMS module, so it's rebuilt
   automatically on future kernel updates.
6. Loads it and verifies the accelerometer reports as `lis2hh12`.

No kernel source is vendored in this repo — it's fetched fresh for whatever
kernel you're running, so the fix doesn't go stale as you update.

## Dependencies

`install.sh` installs these automatically via `dnf`, listed here for
reference:

- `dkms`
- `patch`
- `gcc`, `make`
- `kernel-devel` (matching your exact running kernel — `kernel-devel-$(uname -r)`)
- `curl`, `tar`, `xz`

These are enough when building against a distro `kernel-devel` package, since
it ships prebuilt Kbuild tooling (`scripts/`, `tools/objtool`, `Module.symvers`)
matching the installed kernel.

If you instead build against a plain vanilla kernel.org source tree (e.g. for
development/debugging rather than via this script), `make modules_prepare`
rebuilds that host tooling from scratch, which additionally pulled in on
Fedora:

- `flex`, `bison`
- `openssl-devel` (for `scripts/sign-file`)
- `elfutils-libelf-devel` (for `gelf.h`, needed by `tools/objtool`)
- `ncurses-devel`, `perl-interpreter`, `perl-devel`, `rsync`, `dwarves`, `bc`

## Usage

```bash
git clone <this-repo>
cd samsung-sam0201-accel
./install.sh
```

To remove:

```bash
./uninstall.sh
```

## Known limitation

Like any out-of-tree DKMS module, a future kernel release could change
internal IIO/ACPI APIs enough to break the build. If `dkms status` shows a
failed build after a kernel update, that's what happened — open an issue.

## Credit

ACPI ID fix originally discovered and patched by
[fxjosemi](https://github.com/fxjosemi/Samsung-Galaxy-Book-12-Linux) for the
Galaxy Book 12. This repo packages the same patch as a reproducible,
DKMS-managed install for the wider family of Galaxy Book devices sharing this
ACPI ID, confirmed here on the Galaxy Book 10.6.

## License

GPL-2.0-only, matching the Linux kernel.
