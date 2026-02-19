#!/usr/bin/env bash
set -euo pipefail

INSTALL_DIR="${INSTALL_DIR:-}"
REF="${REF:-main}"
GIT_HOST="${GIT_HOST:-github.com}"
REPO="${REPO:-}"
PACKAGE="${PACKAGE:-}"
BINARY="${BINARY:-}"

fail() {
  echo "error: $*" >&2
  exit 1
}

need_cmd() {
  command -v "$1" >/dev/null 2>&1 || fail "'$1' is required but not installed"
}

is_sourced() {
  [[ "${BASH_SOURCE[0]}" != "${0}" ]]
}

append_path_line_if_missing() {
  local rc_file="$1"
  local line="export PATH=\"$INSTALL_DIR:\$PATH\""
  [ -f "$rc_file" ] || touch "$rc_file"
  grep -F "$line" "$rc_file" >/dev/null 2>&1 || echo "$line" >> "$rc_file"
}

select_rc_file() {
  local shell_name

  if [ -n "${ZSH_VERSION:-}" ]; then
    shell_name="zsh"
  elif [ -n "${BASH_VERSION:-}" ] && is_sourced; then
    shell_name="bash"
  else
    shell_name="${SHELL##*/}"
  fi

  case "$shell_name" in
    zsh)
      echo "$HOME/.zshrc"
      ;;
    bash)
      if [ "$OS" = "Darwin" ] && [ -f "$HOME/.bash_profile" ]; then
        echo "$HOME/.bash_profile"
      else
        echo "$HOME/.bashrc"
      fi
      ;;
    *)
      echo "$HOME/.profile"
      ;;
  esac
}

infer_binary_from_repo() {
  case "$REPO" in
    */*) echo "${REPO#*/}" ;;
    *) fail "REPO must be in owner/repo format" ;;
  esac
}

find_built_binary() {
  local release_dir="$1"
  local expected="$2"

  if [ -x "$release_dir/$expected" ]; then
    echo "$release_dir/$expected"
    return
  fi

  local candidates=()
  while IFS= read -r path; do
    candidates+=("$path")
  done < <(find "$release_dir" -maxdepth 1 -type f -perm -111 ! -name '*.d' ! -name '*.rlib' ! -name '*.rmeta' ! -name '*.so' ! -name '*.dylib' ! -name '*.dll')

  if [ "${#candidates[@]}" -eq 1 ]; then
    echo "${candidates[0]}"
    return
  fi

  fail "could not determine built binary in $release_dir (set BINARY explicitly)"
}

if [ -z "$REPO" ]; then
  fail "REPO is required (format: owner/repo). Example: export REPO=fradesa/sdkraft"
fi

REPO_NAME="$(infer_binary_from_repo)"

if [ -z "$BINARY" ]; then
  BINARY="$REPO_NAME"
fi

need_cmd git
need_cmd cargo

OS="$(uname -s)"
case "$OS" in
  Linux|Darwin) ;;
  *) fail "unsupported OS: $OS (supported: Linux/macOS)" ;;
esac

if [ -z "$INSTALL_DIR" ]; then
  INSTALL_DIR="$HOME/.${REPO_NAME}/bin"
fi

REPO_SSH_URL="git@${GIT_HOST}:${REPO}.git"
TMP_ROOT="$HOME/.${REPO_NAME}/tmp"

mkdir -p "$TMP_ROOT"
TMP_DIR="$TMP_ROOT"
rm -rf "$TMP_DIR"
mkdir -p "$TMP_DIR"
trap 'rm -rf "$TMP_DIR"' EXIT

echo "Cloning ${REPO_SSH_URL} (ref: ${REF})"
git clone --depth 1 --branch "$REF" "$REPO_SSH_URL" "$TMP_DIR/repo" \
  || fail "git clone failed (check SSH auth and repository/ref)"

echo "Building project with cargo"
(
  cd "$TMP_DIR/repo"
  if [ -n "$PACKAGE" ]; then
    cargo build -p "$PACKAGE" --release --locked
  else
    cargo build --release --locked
  fi
)

BIN_SRC="$(find_built_binary "$TMP_DIR/repo/target/release" "$BINARY")"
mkdir -p "$INSTALL_DIR"
cp "$BIN_SRC" "$INSTALL_DIR/$BINARY"
chmod +x "$INSTALL_DIR/$BINARY"

RC_TO_UPDATE="$(select_rc_file)"

append_path_line_if_missing "$RC_TO_UPDATE"
export PATH="$INSTALL_DIR:$PATH"
hash -r || true

echo "Installed $BINARY to $INSTALL_DIR/$BINARY"

if is_sourced; then
  # shellcheck disable=SC1090
  source "$RC_TO_UPDATE" || true
  echo "PATH updated and $BINARY is available in this shell."
else
  echo "PATH persisted in $RC_TO_UPDATE"
  echo "To use $BINARY immediately in this shell, run:"
  echo "  source \"$RC_TO_UPDATE\""
fi
