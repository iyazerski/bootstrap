# Bootstrap

Personal machine bootstrap for macOS and Ubuntu WSL.

## Usage

Run on any macOS or Ubuntu WSL machine:

```sh
curl -fsSL https://raw.githubusercontent.com/iyazerski/bootstrap/main/install.sh | sh
```

It needs only `curl`, `tar`, and `bash`. It downloads this repository's `main` branch to a temporary folder, runs `bootstrap.sh` from there, and then deletes the folder.

From a checkout of this repository, run `./bootstrap.sh` instead.

It is safe to run repeatedly. The script installs or adds what is missing and keeps existing local extras, including extra Homebrew packages. The Starship config is kept in sync with this repository's version.

The script may ask for your password when macOS or Ubuntu needs administrator access, for example to change the default shell.

## What It Does

- Installs Homebrew on macOS and Ubuntu WSL.
- Installs packages from `packages/Brewfile`.
- Installs Ubuntu WSL prerequisites from `packages/ubuntu-apt.txt`.
- Installs `uv` with Astral's official installer.
- Installs Python 3.14 with `uv`.
- Installs Rust with `rustup`'s official installer, before the Brewfile, so its `cargo` packages don't pull in Homebrew's `rust`.
- Installs Bun with its official installer into `~/.bun`, with zsh completions.
- Installs global Bun packages from `packages/bun-global.txt`.
- Sets up pi with [pi-setup](https://github.com/iyazerski/pi-setup): Pi-Bolt, pi packages, and MCP tools.
- Configures Git Credential Manager.
- Sets Homebrew `zsh` as the default shell.
- Adds missing lines from `config/` files into local config files:
  - `~/.zshrc`
  - `~/.gitconfig`
  - `~/.aliases`
  - `~/.config/git/ignore`
- Replaces `~/.config/starship.toml` with `config/starship.toml` when changed.
