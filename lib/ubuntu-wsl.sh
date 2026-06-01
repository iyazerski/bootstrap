#!/usr/bin/env bash

bootstrap_ubuntu_wsl() {
  log_header "Preparing administrator access"
  ensure_sudo_session

  log_header "Installing Ubuntu Homebrew prerequisites"
  ensure_ubuntu_homebrew_prerequisites

  log_header "Installing Homebrew packages"
  ensure_homebrew
  ensure_uv
  run_brew_bundle_file "$BOOTSTRAP_DIR/packages/Brewfile"
  ensure_ubuntu_git_credential_manager

  log_header "Installing runtimes"
  ensure_python_314

  log_header "Configuring shell"
  ensure_ubuntu_zsh_default

  ensure_common_configs

  log_header "Reconciling Ubuntu WSL config files"
  ensure_ubuntu_wsl_configs

  log_header "Installing Node dependencies"
  ensure_configured_zsh_command_available node
  ensure_configured_zsh_command_available npm
  run_brew_bundle_file_with_configured_zsh "$BOOTSTRAP_DIR/packages/Brewfile.npm"

  log_header "Configuring Git credentials"
  ensure_git_credential_manager_configured
}

ensure_ubuntu_homebrew_prerequisites() {
  local package
  local package_file
  local missing_file

  require_command sudo
  require_command apt-get
  require_command dpkg-query

  package_file="$BOOTSTRAP_DIR/packages/ubuntu-apt.txt"
  [ -f "$package_file" ] || die "Missing package list: $package_file"

  missing_file="$(mktemp)"

  while IFS= read -r package || [ -n "$package" ]; do
    case "$package" in
      ''|\#*)
        continue
        ;;
    esac

    if dpkg-query -W -f='${Status}' "$package" 2>/dev/null | grep -Fq 'install ok installed'; then
      log_ok "Homebrew prerequisite is installed: $package"
    else
      printf '%s\n' "$package" >> "$missing_file"
    fi
  done < "$package_file"

  if [ -s "$missing_file" ]; then
    log_change "Installing missing Homebrew prerequisites."
    sudo apt-get update
    xargs sudo apt-get install -y < "$missing_file"
  else
    log_ok "Ubuntu Homebrew prerequisites are installed."
  fi

  rm "$missing_file"
}

ensure_ubuntu_git_credential_manager() {
  local architecture
  local deb_file
  local download_url
  local release_architecture
  local release_file

  if command -v git-credential-manager >/dev/null 2>&1; then
    log_ok "Git Credential Manager is installed."
    return
  fi

  require_command curl
  require_command dpkg
  require_command jq
  require_command sudo

  architecture="$(dpkg --print-architecture)"

  case "$architecture" in
    amd64)
      release_architecture="x64"
      ;;
    arm64)
      release_architecture="arm64"
      ;;
    *)
      die "Unsupported Ubuntu architecture for Git Credential Manager: $architecture"
      ;;
  esac

  release_file="$(mktemp)"
  deb_file="$(mktemp --suffix=.deb)"

  log_change "Installing Git Credential Manager from the official GitHub release."
  curl -fsSL https://api.github.com/repos/git-ecosystem/git-credential-manager/releases/latest -o "$release_file"

  download_url="$(jq -r --arg release_architecture "$release_architecture" '
    .assets[]
    | select(.name | test("^gcm-linux-" + $release_architecture + "-.*[.]deb$"))
    | .browser_download_url
  ' "$release_file" | head -n 1)"

  rm "$release_file"

  [ -n "$download_url" ] || die "Could not find a Git Credential Manager .deb for Ubuntu architecture: $architecture"

  curl -fL "$download_url" -o "$deb_file"
  sudo apt-get install -y "$deb_file"
  rm "$deb_file"

  ensure_command_available git-credential-manager
}

ensure_ubuntu_zsh_default() {
  local current_shell
  local zsh_path

  ensure_command_available zsh
  zsh_path="$(command -v zsh)"

  [ -x "$zsh_path" ] || die "Homebrew zsh is missing at $zsh_path."

  ensure_root_file_line "$zsh_path" /etc/shells

  current_shell="$(getent passwd "$USER" | awk -F: '{print $7}')"

  if [ "$current_shell" = "$zsh_path" ]; then
    log_ok "Default shell is Homebrew zsh."
    return
  fi

  log_change "Changing default shell to $zsh_path"
  ensure_sudo_session
  sudo chsh -s "$zsh_path" "$USER"
}
