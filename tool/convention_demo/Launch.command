#!/bin/zsh
set -eu
export PATH="/opt/homebrew/bin:/usr/local/bin:$HOME/flutter/bin:$PATH"
export DEVELOPER_DIR=/Library/Developer/CommandLineTools
cd "$(dirname "$0")/../.."
python3 tool/convention_demo/launch.py
