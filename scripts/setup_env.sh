#!/usr/bin/env bash
# ==============================================================================
# OneTake ML Environment Setup Script
# ==============================================================================
# Automates setting up the Python virtual environment and dependencies on any
# fresh computer (macOS or Linux).
#
# Usage:
#   chmod +x scripts/setup_env.sh
#   ./scripts/setup_env.sh
# ==============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"
VENV_PATH="$SCRIPT_DIR/.venv"

echo "======================================================="
echo " OneTake ML & Parsing Pipeline Environment Setup"
echo " Target Directory: $REPO_ROOT"
echo "======================================================="

# 1. Detect Python 3
PYTHON_BIN=""
for candidate in python3.14 python3.13 python3.12 python3.11 python3.10 python3; do
    if command -v "$candidate" >/dev/null 2>&1; then
        PYTHON_BIN="$candidate"
        break
    fi
done

if [ -z "$PYTHON_BIN" ]; then
    echo "[-] Error: Python 3 (3.10+) is required but was not found on this machine."
    echo "    On macOS:  brew install python"
    echo "    On Ubuntu: sudo apt-get install python3 python3-venv python3-pip"
    exit 1
fi

PY_VERSION=$("$PYTHON_BIN" -c 'import sys; print(f"{sys.version_info.major}.{sys.version_info.minor}")')
echo "[+] Detected Python: $PYTHON_BIN (v$PY_VERSION)"

# 2. Create or verify virtual environment
if [ ! -d "$VENV_PATH" ]; then
    echo "[+] Creating virtual environment at: $VENV_PATH"
    "$PYTHON_BIN" -m venv "$VENV_PATH"
else
    echo "[+] Virtual environment already exists at: $VENV_PATH"
fi

# 3. Upgrade pip in venv
echo "[+] Upgrading pip..."
"$VENV_PATH/bin/pip" install --upgrade pip setuptools wheel >/dev/null 2>&1 || true

# 4. Install requirements
REQ_FILE="$SCRIPT_DIR/requirements.txt"
if [ -f "$REQ_FILE" ]; then
    echo "[+] Installing dependencies from $REQ_FILE..."
    "$VENV_PATH/bin/pip" install -r "$REQ_FILE"
else
    echo "[-] Warning: $REQ_FILE not found, installing core dependencies directly..."
    "$VENV_PATH/bin/pip" install torch torchvision coremltools pillow numpy reportlab pypdf requests tqdm
fi

# 5. Initialize dataset directory structure
echo "[+] Initializing dataset directories..."
mkdir -p "$REPO_ROOT/dataset/sides" "$REPO_ROOT/dataset/notices" "$REPO_ROOT/dataset/headshots/front" "$REPO_ROOT/dataset/headshots/left_profile" "$REPO_ROOT/dataset/headshots/right_profile" "$REPO_ROOT/OneTake/Models"

# 6. Verify environment
echo "[+] Verifying PyTorch and CoreML installation..."
"$VENV_PATH/bin/python" -c "
import torch, PIL, reportlab
device = 'mps' if torch.backends.mps.is_available() else ('cuda' if torch.cuda.is_available() else 'cpu')
print(f'    PyTorch: {torch.__version__} (Acceleration device: {device})')
print(f'    Pillow:  {PIL.__version__}')
"

echo "======================================================="
echo " Environment setup complete!"
echo " Python binary: $VENV_PATH/bin/python"
echo " Run tests:     $VENV_PATH/bin/python scripts/evaluate_dataset.py"
echo "======================================================="
