#!/usr/bin/env sh
set -eu
if (set -o pipefail) 2>/dev/null; then
  set -o pipefail
fi

INSTALL_DIR="${INSTALL_DIR:-}"
INSTALL_ROOT="${INSTALL_ROOT:-}"
REF="${REF:-main}"
GIT_HOST="${GIT_HOST:-github.com}"
REPO="${REPO:-}"
PACKAGE="${PACKAGE:-}"
BINARY="${BINARY:-}"
REPO_URL="${REPO_URL:-}"

fail() {
  echo "error: $*" >&2
  exit 1
}

need_cmd() {
  command -v "$1" >/dev/null 2>&1 || fail "'$1' is required but not installed"
}

append_path_line_if_missing() {
  rc_file="$1"
  line="export PATH=\"$INSTALL_DIR:\$PATH\""
  [ -f "$rc_file" ] || touch "$rc_file"
  grep -F "$line" "$rc_file" >/dev/null 2>&1 || echo "$line" >> "$rc_file"
}

select_rc_file() {
  shell_name="${SHELL##*/}"

  if [ -z "$shell_name" ] || [ "$shell_name" = "$SHELL" ]; then
    if [ -n "${ZSH_VERSION:-}" ]; then
      shell_name="zsh"
    elif [ -n "${BASH_VERSION:-}" ]; then
      shell_name="bash"
    else
      shell_name="sh"
    fi
  fi

  case "$shell_name" in
    zsh)
      echo "$HOME/.zprofile"
      ;;
    bash)
      if [ "$OS" = "Darwin" ]; then
        echo "$HOME/.bash_profile"
      else
        echo "$HOME/.profile"
      fi
      ;;
    *)
      echo "$HOME/.profile"
      ;;
  esac
}

infer_repo_name() {
  case "$REPO" in
    */*) echo "${REPO#*/}" ;;
    *) fail "REPO must be in owner/repo format" ;;
  esac
}

if [ -z "$REPO" ]; then
  fail "REPO is required (format: owner/repo). Example: export REPO=fradesa/sdkraft"
fi

REPO_NAME="$(infer_repo_name)"

if [ -z "$BINARY" ]; then
  BINARY="$REPO_NAME"
fi

if [ -z "$PACKAGE" ]; then
  PACKAGE="$BINARY"
fi

need_cmd cargo

OS="$(uname -s)"
case "$OS" in
  Linux|Darwin) ;;
  *) fail "unsupported OS: $OS (supported: Linux/macOS)" ;;
esac

if [ -z "$INSTALL_ROOT" ]; then
  INSTALL_ROOT="$HOME/.${REPO_NAME}"
fi

CARGO_BIN_DIR="$INSTALL_ROOT/bin"

if [ -z "$INSTALL_DIR" ]; then
  INSTALL_DIR="$CARGO_BIN_DIR"
fi

if [ -z "$REPO_URL" ]; then
  REPO_URL="https://${GIT_HOST}/${REPO}.git"
fi

echo "Installing ${PACKAGE} (${BINARY}) from ${REPO_URL} (ref: ${REF})"

cargo install \
  --git "$REPO_URL" \
  --branch "$REF" \
  --locked \
  --force \
  --root "$INSTALL_ROOT" \
  --bin "$BINARY" \
  "$PACKAGE" \
  || fail "cargo install failed"

[ -x "$CARGO_BIN_DIR/$BINARY" ] || fail "installed binary not found at $CARGO_BIN_DIR/$BINARY"

if [ "$INSTALL_DIR" != "$CARGO_BIN_DIR" ]; then
  mkdir -p "$INSTALL_DIR"
  cp "$CARGO_BIN_DIR/$BINARY" "$INSTALL_DIR/$BINARY"
  chmod +x "$INSTALL_DIR/$BINARY"
fi

RC_TO_UPDATE="$(select_rc_file)"

append_path_line_if_missing "$RC_TO_UPDATE"
export PATH="$INSTALL_DIR:$PATH"
hash -r || true

echo "Installed $BINARY to $INSTALL_DIR/$BINARY"
echo "PATH persisted in $RC_TO_UPDATE"
echo "To use $BINARY immediately in this shell, run:"
echo "  . \"$RC_TO_UPDATE\""
