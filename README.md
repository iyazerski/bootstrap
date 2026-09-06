# Bootstrap

Personal machine bootstrap for macOS and Ubuntu WSL.

## Usage

Run from this repository:

```sh
./bootstrap.sh
```

It is safe to run repeatedly. The script installs or adds what is missing and keeps existing local extras, including extra Homebrew packages. The Starship config is kept in sync with this repository's version.

The script may ask for your password when macOS or Ubuntu needs administrator access, for example to change the default shell.

## What It Does

- Installs Homebrew on macOS and Ubuntu WSL.
- Installs packages from `packages/Brewfile`.
- Installs global npm packages from `packages/Brewfile.npm` after `zsh` is configured.
- Installs Ubuntu WSL prerequisites from `packages/ubuntu-apt.txt`.
- Installs `uv` with Astral's official installer.
- Installs Python 3.14 with `uv`.
- Configures Git Credential Manager.
- Sets Homebrew `zsh` as the default shell.
- Adds missing lines from `config/` files into local config files:
  - `~/.zshrc`
  - `~/.gitconfig`
  - `~/.aliases`
  - `~/.config/git/ignore`
- Replaces `~/.config/starship.toml` with `config/starship.toml` when changed.
