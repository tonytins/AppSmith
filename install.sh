#!/bin/sh

BUILD_MODE=debug # Change to release for a release build
PROJECT="$PWD/AppSmith"
PROGRAM=appsmith

BUILD_DIR="$PROJECT/.build/$BUILD_MODE"
EXEC_PATH="$BUILD_DIR/$PROGRAM"
BIN_DIR="$HOME/.local/bin"
INSTALL_DIR="$BIN_DIR/$PROGRAM"

if [ ! -d "$BUILD_DIR" ]; then
    echo "Executable not found."
    exit 1
fi

if [ ! -d "$BIN_DIR" ]; then
    echo "Creating local bin directory."
    mkdir -p "$BIN_DIR"
fi

cp "$EXEC_PATH" "$INSTALL_DIR"
chmod +x "$INSTALL_DIR"

echo "Installed $PROGRAM to $INSTALL_DIR"
