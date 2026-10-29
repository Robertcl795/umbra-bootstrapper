#!/usr/bin/env bash
set -euo pipefail

nvim --headless "+Lazy! sync" +qa
