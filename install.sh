#!/bin/sh
# Download this repository and run bootstrap.sh from it, on a machine without a checkout.
#
#   curl -fsSL https://raw.githubusercontent.com/iyazerski/bootstrap/main/install.sh | sh
#
# bootstrap.sh needs bash and the lib/, config/ and packages/ files next to it, so it can't be piped to sh itself.
# The archive needs only curl and tar, not git, which a clean macOS lacks until the Xcode tools are installed.
set -eu

ARCHIVE_URL="https://github.com/iyazerski/bootstrap/archive/refs/heads/main.tar.gz"

fail() {
	printf '[error] %s\n' "$1" >&2
	exit 1
}

# Everything runs from main, called on the last line: sh has then read the whole script, so commands that read stdin
# can't swallow the rest of it from the curl pipe.
main() {
	command -v curl >/dev/null 2>&1 || fail "curl is needed"
	command -v tar >/dev/null 2>&1 || fail "tar is needed"
	command -v bash >/dev/null 2>&1 || fail "bash is needed"

	dir=$(mktemp -d)
	trap 'rm -rf "$dir"' EXIT

	printf '==> Downloading %s\n' "$ARCHIVE_URL"
	curl -fsSL "$ARCHIVE_URL" | tar -xz -C "$dir" --strip-components=1

	bash "$dir/bootstrap.sh"
}

main
