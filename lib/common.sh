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

# fnm comes from the Brewfile. Its default version is the one login shells, GUI apps, and global npm packages use.
ensure_node_lts() {
  ensure_command_available fnm

  if fnm exec --using=default node --version >/dev/null 2>&1; then
    log_ok "Node.js is available through fnm."
    return
  fi

  log_change "Installing the latest Node.js LTS through fnm."
  fnm install --lts
  fnm default lts-latest
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

run_brew_bundle_file_with_configured_zsh() {
  local brewfile

  brewfile="$1"

  [ -f "$brewfile" ] || die "Missing Brewfile: $brewfile"

  ensure_configured_zsh_command_available brew

  if zsh -ic 'brew bundle check --file="$1" >/dev/null' bootstrap-brew-bundle "$brewfile"; then
    log_ok "Homebrew bundle is satisfied: $brewfile"
    return
  fi

  log_change "Installing Homebrew bundle: $brewfile"
  zsh -ic 'brew bundle install --file="$1"' bootstrap-brew-bundle "$brewfile"
}

ensure_configured_zsh_command_available() {
  local command_name

  command_name="$1"

  ensure_command_available zsh

  zsh -ic 'command -v "$1" >/dev/null' bootstrap-zsh-command "$command_name" || die "$command_name is missing after zsh config. Check $HOME/.zshrc."
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
