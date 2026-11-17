#!/usr/bin/env bash

PI_AGENT_DIR="${PI_CODING_AGENT_DIR:-$HOME/.pi/agent}"
PI_NPM_PACKAGE="@earendil-works/pi-coding-agent"
# The `pi` that scripts, skills and apps run.
PI_LAUNCHER="$HOME/.local/bin/pi"
# The launcher's second line, which tells it apart from a `pi` bootstrap did not write.
PI_LAUNCHER_MARK="# bootstrap's pi launcher: runs pi, installed with Bun, on Bun, so that it needs no Node.js."
PI_PACKAGES=(
  npm:pi-web-access
  git:github.com/iyazerski/dev-flows-plugin
)
# The largest context window, in tokens, any model may use, so compaction starts before requests grow past it.
PI_CONTEXT_WINDOW=250000
PI_AGENTS_MD="$HOME/.agents/AGENTS.md"

ensure_pi_configured() {
  local pi_script

  ensure_command_available bun
  ensure_command_available jq
  ensure_command_available git

  pi_script="$(bun pm bin -g)/pi"
  ensure_pi_installed "$pi_script"
  ensure_pi_launcher "$pi_script"
  check_other_pis "$pi_script"

  ensure_json_value "$PI_AGENT_DIR/settings.json" .npmCommand '["bun"]'
  # Keeps eligible prompt caches warm between runs, so a pause of over 5 minutes does not rewrite the whole context.
  ensure_json_value "$PI_AGENT_DIR/settings.json" .cacheWarming '"idle"'
  ensure_pi_packages
  # pi-web-access's tools are then reached only from codemode scripts, and their schemas are not sent with every request.
  ensure_json_value "$PI_AGENT_DIR/web-search.json" .toolExposure '"deferred"'
  ensure_json_value "$PI_AGENT_DIR/web-search.json" .toolActivation '"none"'
  cap_pi_context_windows
  ensure_pi_agents_md
  ensure_pi_mcp_server lspyx lspyx mcp serve
  ensure_pi_mcp_server gopls gopls mcp
  # gopls watches every file under the working folder, one open file each on macOS, and runs out in big non-Go repos.
  # Go projects turn it back on in .pi/mcp.json.
  ensure_json_value "$PI_AGENT_DIR/mcp.json" .mcpServers.gopls.enabled false
}

# Run pi without project-local files, so a project's settings never leak into the setup.
run_pi() {
  (cd "$HOME" && "$PI_LAUNCHER" "$@" --no-approve)
}

ensure_pi_installed() {
  if [ -e "$1" ] && bun "$1" --version >/dev/null 2>&1; then
    log_ok "pi is installed with Bun."
    return
  fi

  log_change "Installing $PI_NPM_PACKAGE with Bun."
  # Like pi's own installers and `pi update`: pi needs none of its dependencies' install scripts.
  bun add --global --ignore-scripts "$PI_NPM_PACKAGE"
  bun "$1" --version >/dev/null 2>&1 || die "pi did not install to $1"
}

# The `pi` Bun links starts with `#!/usr/bin/env node`, so it does not run without Node.js. The launcher runs it on Bun.
ensure_pi_launcher() {
  local content

  # Absolute paths, so it runs also where Bun's bin directory is not on PATH. `pi update` keeps both paths.
  content="#!/bin/sh
$PI_LAUNCHER_MARK
exec '$(command -v bun)' '$1' \"\$@\""

  if [ -f "$PI_LAUNCHER" ] && [ "$(cat "$PI_LAUNCHER")" = "$content" ]; then
    log_ok "pi launcher is up to date: $PI_LAUNCHER"
    return
  fi

  if [ -e "$PI_LAUNCHER" ] || [ -L "$PI_LAUNCHER" ]; then
    if [ -L "$PI_LAUNCHER" ] || [ "$(sed -n 2p "$PI_LAUNCHER")" != "$PI_LAUNCHER_MARK" ]; then
      die "$PI_LAUNCHER is not bootstrap's pi launcher. Move it away and run bootstrap again."
    fi
  fi

  log_change "Writing the pi launcher $PI_LAUNCHER"
  mkdir -p "$(dirname "$PI_LAUNCHER")"
  # Through a temporary file, so apps never start a half-written launcher.
  printf '%s\n' "$content" > "$PI_LAUNCHER.tmp.$$"
  chmod 755 "$PI_LAUNCHER.tmp.$$"
  mv -f "$PI_LAUNCHER.tmp.$$" "$PI_LAUNCHER"
}

# Another `pi` on PATH would run in place of the launcher wherever PATH is ordered differently, as in apps.
check_other_pis() {
  local dir
  local others
  local pi_script

  pi_script="$(realpath "$1")"
  others=()

  while IFS= read -r dir; do
    if [ -z "$dir" ] || [ "$dir/pi" = "$PI_LAUNCHER" ]; then
      continue
    fi

    if { [ -x "$dir/pi" ] || [ -L "$dir/pi" ]; } && [ "$(realpath "$dir/pi" 2>/dev/null)" != "$pi_script" ]; then
      others+=("$dir/pi")
    fi
  done < <(tr ':' '\n' <<< "$PATH")

  if [ "${#others[@]}" -ne 0 ]; then
    die "Another pi is installed at ${others[*]}. Remove it with the tool that installed it and run bootstrap again."
  fi

  log_ok "No other pi is on PATH."
}

# Set a JSON value at a path in a file, creating the file if needed: ensure_json_value <file> <jq path> <JSON value>
ensure_json_value() {
  local file
  local path
  local value
  local updated

  file="$1"
  path="$2"
  value="$3"

  if [ -f "$file" ] && jq -e --argjson value "$value" "$path == \$value" "$file" >/dev/null; then
    log_ok "$file has $path set to $value"
    return
  fi

  log_change "Setting $path to $value in $file"
  mkdir -p "$(dirname "$file")"
  [ -f "$file" ] || printf '{}\n' > "$file"
  updated="$(jq --argjson value "$value" "$path = \$value" "$file")" || die "$file is not valid JSON."
  # Write in place, not with mv, so the file keeps its permissions: pi's config files may hold API keys.
  printf '%s\n' "$updated" > "$file"
}

ensure_pi_packages() {
  local source
  local installed

  # `pi list` prints each package's source indented by two spaces, and its install path on the next line.
  installed="$(run_pi list)"

  for source in "${PI_PACKAGES[@]}"; do
    if grep -Fxq "  $source" <<< "$installed"; then
      log_ok "pi package is installed: $source"
    else
      log_change "Installing pi package: $source"
      run_pi install "$source"
    fi
  done
}

# Print each available model with a context window above PI_CONTEXT_WINDOW as `provider<TAB>model`, one per line.
pi_models_over_context_window() {
  # `pi --list-models` prints a table with the provider, model and context window in the first three columns, and
  # the window rounded to thousands (`272K`) or millions (`1M`).
  run_pi --list-models | awk -v limit="$PI_CONTEXT_WINDOW" '
    NR == 1 { if ($1 != "provider" || $3 != "context") exit 1; next }
    {
      size = $3 + 0
      if ($3 ~ /M$/) size *= 1000000; else if ($3 ~ /K$/) size *= 1000
      if (size > limit) printf "%s\t%s\n", $1, $2
    }' || die "Could not read the model list from \`pi --list-models\`."
}

cap_pi_context_windows() {
  local models
  local models_json
  local updated

  models="$(pi_models_over_context_window)"

  if [ -z "$models" ]; then
    log_ok "No pi model has a context window above $PI_CONTEXT_WINDOW tokens."
    return
  fi

  models_json="$PI_AGENT_DIR/models.json"
  log_change "Capping the context window at $PI_CONTEXT_WINDOW tokens in $models_json for: $(tr '\t\n' '/ ' <<< "$models")"
  mkdir -p "$PI_AGENT_DIR"
  [ -f "$models_json" ] || printf '{}\n' > "$models_json"
  # modelOverrides applies only to built-in and extension models, so a model this file defines is changed in place.
  updated="$(jq --arg models "$models" --argjson limit "$PI_CONTEXT_WINDOW" '
    reduce ($models | split("\n")[] | split("\t")) as [$provider, $id] (.;
      if any(.providers[$provider].models[]?; .id == $id) then
        .providers[$provider].models |= map(if .id == $id then .contextWindow = $limit else . end)
      else
        .providers[$provider].modelOverrides[$id].contextWindow = $limit
      end)' "$models_json")" || die "$models_json is not valid JSON."
  printf '%s\n' "$updated" > "$models_json"
}

# Skills in ~/.agents/skills need no link: pi reads that directory itself, and a link would load every skill twice.
ensure_pi_agents_md() {
  local target

  target="$PI_AGENT_DIR/AGENTS.md"

  if [ ! -f "$PI_AGENTS_MD" ]; then
    log_ok "No $PI_AGENTS_MD to link."
    return
  fi

  if [ -L "$target" ] && [ "$(realpath "$target")" = "$(realpath "$PI_AGENTS_MD")" ]; then
    log_ok "$target links to $PI_AGENTS_MD"
    return
  fi

  if [ -e "$target" ] || [ -L "$target" ]; then
    die "$target exists and is not a link to $PI_AGENTS_MD. Merge it into $PI_AGENTS_MD, remove it and run bootstrap again."
  fi

  log_change "Linking $target to $PI_AGENTS_MD"
  mkdir -p "$PI_AGENT_DIR"
  ln -s "$PI_AGENTS_MD" "$target"
}

# Add an MCP server to pi's mcp.json unless it is there, so local changes to it stay: ensure_pi_mcp_server <name> <command...>
ensure_pi_mcp_server() {
  local mcp_json
  local name

  mcp_json="$PI_AGENT_DIR/mcp.json"
  name="$1"
  shift

  if [ -f "$mcp_json" ] && jq -e --arg name "$name" '.mcpServers[$name]' "$mcp_json" >/dev/null; then
    log_ok "pi MCP server is configured: $name"
    return
  fi

  log_change "Adding pi MCP server: $name"
  # Not through run_pi: `mcp` commands reject --no-approve. Without --local, `mcp add` edits the user-level file.
  (cd "$HOME" && "$PI_LAUNCHER" mcp add "$name" -- "$@" >/dev/null)
}
