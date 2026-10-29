#!/bin/bash
# Double-click to start Morse Eye. Close the window (or Ctrl+C) to stop.
cd "$(dirname "$0")"
if [ ! -x .venv/bin/python ]; then
  echo "Run install.command first."; read -n 1 -s -r; exit 1
fi
exec .venv/bin/python -m morse_eye "$@"
