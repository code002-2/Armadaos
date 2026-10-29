#!/usr/bin/env bash
# Tests for the thyme (Xiaomi Mi 10S) internal-storage build path: pipeline
# files exist, device profile wires up, and the boot.img arg/DTB selection
# picks the vendor-ABL header-v1 geometry verified on this device.
set -euo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
DEV_DIR="$ROOT/system_files/usr/lib/armada/devices"
DEVICE=sm8250-xiaomi-thyme
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }

# ---------------------------------------------------------------------------
# 1. Pipeline files exist
# ---------------------------------------------------------------------------
for f in \
    "system_files/usr/lib/armada/devices/${DEVICE}.conf" \
    "system_files/usr/lib/armada/supported-dtbs.${DEVICE}" \
    "system_files/usr/lib/armada/bootimg-args.${DEVICE}" \
    "system_files/usr/libexec/armada/armada-bootimg-update" \
    "system_files/usr/libexec/armada/device-env" \
    "post_process/export-fastboot-images.sh" \
    "disk_config/disk-thyme.toml" \
    "kernel-thyme/BUILD.env" \
    "kernel-thyme/build.sh" \
    "kernel-thyme/Containerfile" \
    "kernel-thyme/thyme-armada.config.overrides" \
    "kernel-thyme/sm8250.config" \
    ".github/workflows/build-thyme-container.yml" \
    ".github/workflows/build-armada-export.yml" \
    ".github/scripts/armada-export-flashable.sh" \
    "build_files/52-thyme-device-fixes.sh" \
    "docs/flashing-xiaomi-thyme.md"; do
    [ -e "$ROOT/$f" ] || fail "missing pipeline file: $f"
done

# Kernel source points at the thyme mainline tree.
. "$ROOT/kernel-thyme/BUILD.env"
[[ "$KERNEL_REPO" == *linux-xiaomi-thyme-mainline* ]] || fail "KERNEL_REPO not the thyme tree: $KERNEL_REPO"
[ -f "$ROOT/kernel-thyme/$KERNEL_CONFIG" ] || fail "kernel config missing: $KERNEL_CONFIG"
grep -q '^CONFIG_DRM_MSM=y' "$ROOT/kernel-thyme/$KERNEL_CONFIG" || fail "thyme config lost DRM_MSM=y"
grep -q 'TOUCHSCREEN_ST_FTS' "$ROOT/kernel-thyme/$KERNEL_CONFIG" || fail "thyme config lost ST FTS touch"
grep -q '^CONFIG_EXT4_FS=y' "$ROOT/kernel-thyme/$KERNEL_CONFIG" || fail "thyme config lost EXT4 (initramfs-less boot)"
grep -q '^CONFIG_SND_SOC_CS35L41=y' "$ROOT/kernel-thyme/$KERNEL_CONFIG" || fail "thyme config lost CS35L41 amps"
# Overrides carry the Armada runtime + the wireless/gadget stack the board
# config lacks.
grep -q '^CONFIG_ATH11K=m' "$ROOT/kernel-thyme/thyme-armada.config.overrides" || fail "overrides lost ath11k"
grep -q '^CONFIG_USB_CONFIGFS_F_RNDIS=y' "$ROOT/kernel-thyme/thyme-armada.config.overrides" || fail "overrides lost USB gadget RNDIS"
grep -q '^CONFIG_SCHED_CLASS_EXT=y' "$ROOT/kernel-thyme/thyme-armada.config.overrides" || fail "overrides lost sched_ext"

# The device-validated UCM2 ships under the card name the DTS registers.
grep -q 'XIAOMI-UMI-WCD9380-CS35L41-VA-DMIC' \
    "$ROOT/system_files/usr/share/alsa/ucm2/conf.d/sm8250/XIAOMI-UMI-WCD9380-CS35L41-VA-DMIC.conf" \
    || fail "UCM2 card conf missing"

# Device firmware is vendored (umi DSP set + cirrus tuning + ath11k QCA6390).
[ -f "$ROOT/system_files/usr/lib/firmware/qcom/sm8250/umi/adsp.mbn" ] || fail "umi adsp.mbn missing"
[ -f "$ROOT/system_files/usr/lib/firmware/ath11k/QCA6390/hw2.0/amss.bin" ] || fail "ath11k QCA6390 amss.bin missing"
ls "$ROOT/system_files/usr/lib/firmware/cirrus/"*-thyme-* >/dev/null 2>&1 \
    || fail "cirrus thyme tuning missing"

# ---------------------------------------------------------------------------
# 2. device-env picks the thyme profile from the DTB model string
# ---------------------------------------------------------------------------
for model in "Xiaomi Mi 10S" "Xiaomi Mi 10S (thyme)"; do
    ARMADA_MODEL="$model" ARMADA_DEVICE_DIR="$DEV_DIR" \
        bash "$ROOT/system_files/usr/libexec/armada/device-env" \
        > "$WORK/env.out"
    grep -q 'ARMADA_DEVICE_ID=sm8250-xiaomi-thyme' "$WORK/env.out" \
        || fail "device-env did not map model '$model'"
    grep -q 'ARMADA_SOC_CLASS=SM8250' "$WORK/env.out" \
        || fail "device-env lost SoC class for '$model'"
done

# ---------------------------------------------------------------------------
# 3. Boot.img inputs: device DTB list + vendor-ABL geometry (header v1!)
# ---------------------------------------------------------------------------
grep -qx 'sm8250-xiaomi-thyme' "$ROOT/system_files/usr/lib/armada/supported-dtbs.$DEVICE" \
    || fail "DTB list does not name sm8250-xiaomi-thyme"
# The -logdump debug DTB shares msm-id/board-id with the main DTB; shipping
# both would make the ABL's DTB pick nondeterministic.
! grep -q 'logdump' "$ROOT/system_files/usr/lib/armada/supported-dtbs.$DEVICE" \
    || fail "DTB list ships the -logdump variant (ambiguous msm-id)"

# Same source order as the export scripts: device args first, then the
# global helpers (which carry the ROCKNIX geometry — the device geometry
# must be restored after).
# shellcheck disable=SC1090
. "$ROOT/system_files/usr/lib/armada/bootimg-args.$DEVICE"
device_args="${ARMADA_BOOTIMG_ARGS}"
device_max="${ARMADA_CMDLINE_MAX}"
# shellcheck disable=SC1090
. "$ROOT/system_files/usr/lib/armada/bootimg-args"
ARMADA_BOOTIMG_ARGS="${device_args}"
ARMADA_CMDLINE_MAX="${device_max}"

[[ "$(type -t armada_bootimg_cmdline)" == "function" ]] || fail "global bootimg helper missing"
[[ "$ARMADA_BOOTIMG_ARGS" == *"--header_version 1"* ]] || fail "header-v1 lost"
[[ "$ARMADA_BOOTIMG_ARGS" == *"--pagesize 2048"* ]] || fail "2048 pagesize lost"
[[ "$ARMADA_BOOTIMG_ARGS" == *"--kernel_offset 0x10000000"* ]] || fail "kernel_offset 0x10000000 lost"
[[ "$ARMADA_CMDLINE_MAX" == "512" ]] || fail "cmdline cap drift: $ARMADA_CMDLINE_MAX"

# The device profile's own cmdline helper (same contract as the global one).
# shellcheck disable=SC1090
. "$ROOT/system_files/usr/lib/armada/devices/$DEVICE.conf"
[[ "$(type -t armada_bootimg_cmdline)" == "function" ]] || fail "device bootimg helper missing"
out=$(armada_bootimg_cmdline \
    "console=ttyS0 ostree=/ostree/boot.0/abc rootflags=noatime,space_cache=v2 quiet")
[[ "$out" == ostree=/ostree/boot.0/abc* ]] || fail "ostree= not first: $out"
[[ "$out" != *ttyS0* ]] || fail "console=ttyS0 leaked into the boot cmdline: $out"
[[ "$out" == *rootflags=noatime* ]] || fail "rootflags dropped: $out"

# ---------------------------------------------------------------------------
# 4. Device profile carries the boot-partition (no ESP /KERNEL) mode
# ---------------------------------------------------------------------------
grep -q 'ARMADA_BOOTIMG_OUT=.*boot_' "$ROOT/system_files/usr/lib/armada/devices/$DEVICE.conf" \
    || fail "profile does not declare the boot partition target"
grep -q 'ARMADA_BOOT_PARTS="boot_a boot_b"' "$ROOT/system_files/usr/lib/armada/devices/$DEVICE.conf" \
    || fail "profile does not flash both A/B boot slots"
grep -q 'ARMADA_DTB_LIST=.*supported-dtbs.sm8250-xiaomi-thyme' \
    "$ROOT/system_files/usr/lib/armada/devices/$DEVICE.conf" \
    || fail "profile does not pin the device DTB list"

# Both export paths take the device.
grep -q -- '--device' "$ROOT/post_process/export-fastboot-images.sh" \
    || fail "export-fastboot-images.sh lost --device"
grep -q 'DEVICE="${5:-' "$ROOT/.github/scripts/armada-export-flashable.sh" \
    || fail "armada-export-flashable.sh lost the device argument"
grep -q 'sm8250-xiaomi-thyme' "$ROOT/.github/scripts/armada-export-flashable.sh" \
    || fail "armada-export-flashable.sh has no thyme branch"
grep -q 'sm8250-xiaomi-thyme' "$ROOT/.github/workflows/build-thyme-container.yml" \
    || fail "container workflow does not bake the thyme device"

# build.sh runs the thyme device fixes for the thyme device.
grep -q '52-thyme-device-fixes.sh' "$ROOT/build_files/build.sh" \
    || fail "build.sh lost the thyme device step"
grep -q 'ARMADA_DEVICE=sm8250-xiaomi-thyme' "$ROOT/Justfile" \
    || fail "Justfile build-thyme-image lost the device build arg"

echo "OK: thyme flashable pipeline"
