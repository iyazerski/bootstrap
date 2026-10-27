#!/usr/bin/env bash

log_header() {
  printf '\n==> %s\n' "$1"
}

log_ok() {
  printf '[ok] %s\n' "$1"
}

log_change() {
  printf '[change] %s\n' "$1"
}

log_success() {
  printf '[done] %s\n' "$1"
}

die() {
  printf '[error] %s\n' "$1" >&2
  exit 1
}

require_command() {
  command -v "$1" >/dev/null 2>&1 || die "Missing required command: $1"
}

ensure_sudo_session() {
  require_command sudo

  if sudo -n true 2>/dev/null; then
    log_ok "Administrator credentials are available."
    return
  fi

  log_change "Requesting administrator credentials."
  sudo -v -p "[sudo] Password for %u to continue bootstrap: "

  if sudo -n true 2>/dev/null; then
    log_ok "Administrator credentials are available."
    return
  fi

  die "Administrator credentials were not accepted."
}

detect_platform() {
  local kernel_name

  kernel_name="$(uname -s)"

  case "$kernel_name" in
    Darwin)
      BOOTSTRAP_PLATFORM="macos"
      ;;
    Linux)
      if ! grep -qiE '(microsoft|wsl)' /proc/version; then
        die "Linux support is currently limited to Ubuntu WSL."
      fi

      if ! grep -Eq '^ID="?ubuntu"?$' /etc/os-release; then
        die "Linux support is currently limited to Ubuntu WSL."
      fi

      BOOTSTRAP_PLATFORM="ubuntu-wsl"
      ;;
    *)
      die "Unsupported kernel: $kernel_name"
      ;;
  esac

  export BOOTSTRAP_PLATFORM
}

ensure_python_314() {
  if uv python find 3.14 >/dev/null 2>&1; then
    log_ok "Python 3.14 is available through uv."
    return
  fi

  log_change "Installing Python 3.14 through uv."
  uv python install 3.14
  uv python find 3.14 >/dev/null
}

# Bun lives in ~/.bun, where its installer and `bun upgrade` expect it. The zsh config adds it to PATH.
ensure_bun() {
  export BUN_INSTALL="$HOME/.bun"
  export PATH="$BUN_INSTALL/bin:$PATH"

  if command -v bun >/dev/null 2>&1; then
    log_ok "Bun is installed."
  else
    require_command curl
    require_command unzip

    log_change "Installing Bun with the official installer."
    # A non-zsh SHELL stops the installer from appending its own lines to ~/.zshrc: config/zshrc.* covers them.
    curl -fsSL https://bun.sh/install | SHELL=/bin/sh bash
    ensure_command_available bun
  fi

  if [ -s "$BUN_INSTALL/_bun" ]; then
    log_ok "Bun zsh completions exist."
  else
    SHELL=zsh bun completions > "$BUN_INSTALL/_bun"
    log_change "Created $BUN_INSTALL/_bun"
  fi
}

ensure_bun_global_packages() {
  local package
  local package_file
  local global_manifest
  local missing_packages

  ensure_command_available bun
  ensure_command_available jq

  package_file="$BOOTSTRAP_DIR/packages/bun-global.txt"
  [ -f "$package_file" ] || die "Missing package list: $package_file"

  global_manifest="$BUN_INSTALL/install/global/package.json"
  missing_packages=()

  while IFS= read -r package || [ -n "$package" ]; do
    case "$package" in
      ''|\#*)
        continue
        ;;
    esac

    if [ -f "$global_manifest" ] && jq -e --arg package "$package" '.dependencies[$package]' "$global_manifest" >/dev/null; then
      log_ok "Global Bun package is installed: $package"
    else
      missing_packages+=("$package")
    fi
  done < "$package_file"

  if [ "${#missing_packages[@]}" -eq 0 ]; then
    log_ok "Global Bun packages are installed."
    return
  fi

  log_change "Installing global Bun packages: ${missing_packages[*]}"
  bun add --global "${missing_packages[@]}"
}

# pi-setup's script installs Pi-Bolt, pi packages and MCP tools. It skips what is in place, so it runs every time.
ensure_pi_setup() {
  require_command curl
  ensure_command_available git
  ensure_command_available jq
  ensure_command_available bun

  # The script prints its own status, including whether anything changed.
  curl -fsSL https://raw.githubusercontent.com/iyazerski/pi-setup/main/scripts/setup.sh | sh
}

# Install rustup before the Brewfile: its cargo entries otherwise make brew bundle install Homebrew's rust formula.
ensure_rustup() {
  if [ -f "$HOME/.cargo/env" ]; then
    . "$HOME/.cargo/env"
  fi

  if command -v rustup >/dev/null 2>&1; then
    log_ok "rustup is installed."
    return
  fi

  require_command curl

  log_change "Installing rustup with the official installer."
  # The zsh config already sources ~/.cargo/env, so the installer must not edit shell files.
  curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y --no-modify-path
  . "$HOME/.cargo/env"
  ensure_command_available cargo
}

ensure_uv() {
  if command -v uv >/dev/null 2>&1; then
    log_ok "uv is installed."
    return
  fi

  require_command curl

  log_change "Installing uv with the official installer."
  curl -LsSf https://astral.sh/uv/install.sh | sh
  export PATH="$HOME/.local/bin:$PATH"
  ensure_command_available uv
}

load_homebrew() {
  local brew_path

  if command -v brew >/dev/null 2>&1; then
    eval "$(brew shellenv)"
    return 0
  fi

  for brew_path in /opt/homebrew/bin/brew /usr/local/bin/brew /home/linuxbrew/.linuxbrew/bin/brew "$HOME/.linuxbrew/bin/brew"; do
    if [ -x "$brew_path" ]; then
      eval "$("$brew_path" shellenv)"
      return 0
    fi
  done

  return 1
}

ensure_homebrew() {
  if load_homebrew; then
    log_ok "Homebrew is installed."
    return
  fi

  require_command curl
  require_command bash

  log_change "Installing Homebrew."
  NONINTERACTIVE=1 /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
  load_homebrew || die "Homebrew installed, but brew is not available on PATH."
}

run_brew_bundle_file() {
  local brewfile

  brewfile="$1"

  [ -f "$brewfile" ] || die "Missing Brewfile: $brewfile"

  if brew bundle check --file="$brewfile" >/dev/null; then
    log_ok "Homebrew bundle is satisfied: $brewfile"
    return
  fi

  log_change "Installing Homebrew bundle: $brewfile"
  brew bundle install --file="$brewfile"
}

ensure_command_available() {
  command -v "$1" >/dev/null 2>&1 || die "$1 is missing after package installation. Add it to the platform package manifest."
}

ensure_git_credential_manager_configured() {
  ensure_command_available git-credential-manager

  git-credential-manager configure
  log_ok "Git Credential Manager is configured."
}

ensure_root_file_line() {
  local line
  local target_file

  line="$1"
  target_file="$2"

  if grep -Fxq "$line" "$target_file"; then
    log_ok "$target_file contains $line"
    return
  fi

  log_change "Adding $line to $target_file"
  ensure_sudo_session
  printf '%s\n' "$line" | sudo tee -a "$target_file" >/dev/null
}
