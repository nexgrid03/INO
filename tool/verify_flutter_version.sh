#!/usr/bin/env bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

VERSION_FILE="$PROJECT_ROOT/.flutter-version"
FVMRC_FILE="$PROJECT_ROOT/.fvmrc"

if [ ! -f "$VERSION_FILE" ]; then
  echo "ERROR: .flutter-version file not found at $VERSION_FILE"
  exit 1
fi

REQUIRED_VERSION=$(cat "$VERSION_FILE" | tr -d '\r\n ')

echo "=========================================="
echo " Flutter Version Verification"
echo "=========================================="
echo "Required Flutter version (.flutter-version): $REQUIRED_VERSION"

# If .fvmrc exists, verify consistency with .flutter-version
if [ -f "$FVMRC_FILE" ]; then
  FVMRC_VERSION=$(grep -o '"flutter"[[:space:]]*:[[:space:]]*"[^"]*"' "$FVMRC_FILE" | sed -E 's/.*"flutter"[[:space:]]*:[[:space:]]*"([^"]+)".*/\1/' | tr -d '\r\n ')
  echo "Configured FVM version (.fvmrc):             $FVMRC_VERSION"
  if [ -n "$FVMRC_VERSION" ] && [ "$FVMRC_VERSION" != "$REQUIRED_VERSION" ]; then
    echo "ERROR: .fvmrc version ($FVMRC_VERSION) does not match .flutter-version ($REQUIRED_VERSION)!"
    exit 1
  fi
fi

# Detect installed Flutter version (allow override via FLUTTER_INSTALLED_OVERRIDE for testing)
if [ -n "$FLUTTER_INSTALLED_OVERRIDE" ]; then
  INSTALLED_VERSION="$FLUTTER_INSTALLED_OVERRIDE"
else
  INSTALLED_VERSION=$(flutter --version 2>/dev/null | head -n 1 | awk '{print $2}')
fi

echo "Installed Flutter version (flutter CLI):     $INSTALLED_VERSION"
echo "=========================================="

if [ -z "$INSTALLED_VERSION" ]; then
  echo "ERROR: Could not detect installed Flutter version via 'flutter --version'."
  exit 1
fi

if [ "$INSTALLED_VERSION" != "$REQUIRED_VERSION" ]; then
  echo "ERROR: Flutter version mismatch! Expected $REQUIRED_VERSION but found $INSTALLED_VERSION"
  exit 1
fi

echo "SUCCESS: Flutter version matches required version ($REQUIRED_VERSION)."
exit 0
