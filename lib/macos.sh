#!/usr/bin/env bash

bootstrap_macos() {
  log_header "Installing macOS packages"
  ensure_homebrew
  ensure_uv
  ensure_rustup
  run_brew_bundle_file "$BOOTSTRAP_DIR/packages/Brewfile"

  log_header "Installing runtimes"
  ensure_python_314
  ensure_bun

  log_header "Configuring shell"
  ensure_macos_zsh_default

  ensure_common_configs

  log_header "Reconciling macOS config files"
  ensure_macos_configs

  log_header "Installing global Bun packages"
  ensure_bun_global_packages

  log_header "Setting up pi"
  ensure_pi_setup

  log_header "Configuring Git credentials"
  ensure_git_credential_manager_configured
}

ensure_macos_zsh_default() {
  local current_shell
  local zsh_path

  zsh_path="$(brew --prefix)/bin/zsh"

  [ -x "$zsh_path" ] || die "Homebrew zsh is missing at $zsh_path."

  ensure_root_file_line "$zsh_path" /etc/shells

  current_shell="$(dscl . -read "/Users/$USER" UserShell | awk '{print $2}')"

  if [ "$current_shell" = "$zsh_path" ]; then
    log_ok "Default shell is Homebrew zsh."
    return
  fi

  log_change "Changing default shell to $zsh_path"
  ensure_sudo_session
  sudo chsh -s "$zsh_path" "$USER"
}
