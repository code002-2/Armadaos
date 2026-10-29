#!/bin/bash
set -euxo pipefail

cd /ctx/build_files

# Device variant. The Containerfile defaults to sheng; the thyme pipeline
# overrides it (just build-thyme-image / build-thyme-container.yml).
DEVICE="${ARMADA_DEVICE:-sm8550-xiaomi-sheng}"

run_step() {
    local step="${1#./}"
    local start="${SECONDS}"

    "$@"
    printf '%s completed in %d seconds\n' "${step}" "$((SECONDS - start))"
}

device_steps() {
    case "${DEVICE}" in
        sm8550-xiaomi-sheng)
            run_step ./50-sheng-extra-features.sh
            run_step ./52-sheng-device-fixes.sh
            ;;
        sm8250-xiaomi-thyme)
            run_step ./52-thyme-device-fixes.sh
            ;;
        *) echo "ERROR: unknown ARMADA_DEVICE: ${DEVICE}" >&2; exit 1 ;;
    esac
}

run_step ./10-base-packages.sh
run_step ./20-install-kernel.sh
run_step ./30-install-steam-session.sh
run_step ./40-vendor-system-files.sh
run_step ./45-install-decky-plugins.sh
device_steps
run_step ./50-create-user.sh
run_step ./52-configure-os-release.sh
run_step ./55-generate-initramfs.sh
run_step ./60-set-default-target.sh
run_step ./70-cleanup.sh
run_step ./80-finalize-update-state.sh
