#!/usr/bin/env bash

ensure_config_lines() {
  local source_file
  local target_file
  local target_dir
  local temp_file
  local status

  source_file="$1"
  target_file="$2"

  [ -f "$source_file" ] || die "Missing config source: $source_file"

  target_dir="$(dirname "$target_file")"
  mkdir -p "$target_dir"
  touch "$target_file"

  temp_file="$(mktemp "${target_file}.tmp.XXXXXX")"

  if awk '
    NR == FNR {
      if ($0 != "") {
        source_count++
        source[source_count] = $0
      }
      next
    }

    {
      target_count++
      target[target_count] = $0
    }

    END {
      anchor = 0
      changed = 0

      for (i = 1; i <= source_count; i++) {
        line = source[i]
        found = 0

        for (j = anchor + 1; j <= target_count; j++) {
          if (target[j] == line) {
            found = j
            break
          }
        }

        if (found == 0) {
          for (j = 1; j <= anchor; j++) {
            if (target[j] == line) {
              found = j
              break
            }
          }
        }

        if (found != 0) {
          if (found > anchor) {
            anchor = found
          }
          continue
        }

        insert_at = anchor
        if (insert_at == 0) {
          insert_at = target_count
        }

        for (j = target_count; j > insert_at; j--) {
          target[j + 1] = target[j]
        }

        target[insert_at + 1] = line
        target_count++
        anchor = insert_at + 1
        changed = 1
      }

      for (j = 1; j <= target_count; j++) {
        print target[j]
      }

      if (changed == 1) {
        exit 3
      }
    }
  ' "$source_file" "$target_file" > "$temp_file"; then
    status=0
  else
    status="$?"
  fi

  case "$status" in
    0)
      rm "$temp_file"
      log_ok "$target_file already contains lines from $source_file"
      ;;
    3)
      cat "$temp_file" > "$target_file"
      rm "$temp_file"
      log_change "Added missing lines from $source_file to $target_file"
      ;;
    *)
      rm "$temp_file"
      die "Failed to reconcile $source_file into $target_file"
      ;;
  esac
}

overwrite_config_file() {
  local source_file
  local target_file
  local target_dir

  source_file="$1"
  target_file="$2"

  [ -f "$source_file" ] || die "Missing config source: $source_file"

  target_dir="$(dirname "$target_file")"
  mkdir -p "$target_dir"
  cp "$source_file" "$target_file"
  log_change "Overwrote $target_file with $source_file"
}

ensure_common_configs() {
  log_header "Reconciling config files"
  ensure_zsh_support_paths
  ensure_config_lines "$BOOTSTRAP_DIR/config/aliases" "$HOME/.aliases"
  overwrite_config_file "$BOOTSTRAP_DIR/config/starship.toml" "$HOME/.config/starship.toml"
  ensure_config_lines "$BOOTSTRAP_DIR/config/gitconfig" "$HOME/.gitconfig"
}

ensure_macos_configs() {
  ensure_config_lines "$BOOTSTRAP_DIR/config/zshrc.macos" "$HOME/.zshrc"
}

ensure_ubuntu_wsl_configs() {
  ensure_config_lines "$BOOTSTRAP_DIR/config/zshrc.ubuntu-wsl" "$HOME/.zshrc"
}

ensure_zsh_support_paths() {
  if [ -d "$HOME/.zsh/cache" ]; then
    log_ok "$HOME/.zsh/cache exists."
  else
    mkdir -p "$HOME/.zsh/cache"
    log_change "Created $HOME/.zsh/cache"
  fi

  if [ -f "$HOME/.secrets" ]; then
    log_ok "$HOME/.secrets exists."
  else
    touch "$HOME/.secrets"
    chmod 600 "$HOME/.secrets"
    log_change "Created empty $HOME/.secrets"
  fi
}
