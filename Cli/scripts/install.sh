#!/bin/sh
set -eu

DIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
BIN_DIR=${EMBR_BIN_DIR:-"$HOME/.local/bin"}
TARGET="$BIN_DIR/embr"

build_native() {
  swift build -c release --package-path "$DIR" --product embr >&2
  echo "$(swift build -c release --package-path "$DIR" --show-bin-path)/embr"
}

build_docker() {
  if ! command -v docker >/dev/null 2>&1; then
    echo "neither a Swift toolchain nor docker is available" >&2
    exit 1
  fi
  docker run --rm \
    --user "$(id -u):$(id -g)" \
    -e HOME=/tmp/embr-home \
    -v "$DIR/..:/work" \
    -w /work/Cli \
    swift:6.4.1-jammy \
    bash -lc 'mkdir -p "$HOME" && swift build -c release --static-swift-stdlib --product embr >&2 && swift build -c release --show-bin-path | tail -1'
}

case "$(uname -s)" in
  Darwin)
    BIN=$(build_native)
    ;;
  Linux)
    if command -v swift >/dev/null 2>&1; then
      BIN=$(build_native)
    else
      BIN_PATH=$(build_docker)
      BIN="$DIR/.build/release/embr"
      if [ ! -f "$BIN" ]; then
        BIN=$(find "$DIR/.build" -type f -name embr -perm -111 | head -1)
      fi
      if [ -z "$BIN" ] || [ ! -f "$BIN" ]; then
        echo "docker build did not produce a binary (looked under $DIR/.build, reported $BIN_PATH)" >&2
        exit 1
      fi
    fi
    ;;
  *)
    echo "unsupported platform: $(uname -s)" >&2
    exit 1
    ;;
esac

mkdir -p "$BIN_DIR"
install -m 0755 "$BIN" "$TARGET"
if command -v strip >/dev/null 2>&1; then
  case "$(uname -s)" in
    Darwin) strip -x "$TARGET" 2>/dev/null || true ;;
    Linux) strip --strip-unneeded "$TARGET" 2>/dev/null || true ;;
  esac
fi
echo "installed $TARGET"
"$TARGET" --version
"$TARGET" doctor --json >/dev/null || true
