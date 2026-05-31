#!/usr/bin/env bash
set -euo pipefail

BOOTSTRAP_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

. "$BOOTSTRAP_DIR/lib/common.sh"
. "$BOOTSTRAP_DIR/lib/configs.sh"

main() {
  if [ "$#" -ne 0 ]; then
    die "bootstrap.sh does not accept arguments yet."
  fi

  detect_platform
  log_header "Bootstrapping $BOOTSTRAP_PLATFORM"

  case "$BOOTSTRAP_PLATFORM" in
    macos)
      . "$BOOTSTRAP_DIR/lib/macos.sh"
      bootstrap_macos
      ;;
    ubuntu-wsl)
      . "$BOOTSTRAP_DIR/lib/ubuntu-wsl.sh"
      bootstrap_ubuntu_wsl
      ;;
    *)
      die "Unsupported platform: $BOOTSTRAP_PLATFORM"
      ;;
  esac

  log_success "Bootstrap complete."
}

main "$@"
