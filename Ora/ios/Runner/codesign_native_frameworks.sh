#!/bin/sh
set -eu

# Device installs fail if native-asset frameworks are copied with ad-hoc signatures.
# Re-sign any ad-hoc embedded frameworks with the app's signing identity.
if [ "${PLATFORM_NAME:-}" != "iphoneos" ]; then
  exit 0
fi

if [ -z "${EXPANDED_CODE_SIGN_IDENTITY:-}" ]; then
  exit 0
fi

frameworks_dir="${TARGET_BUILD_DIR}/${WRAPPER_NAME}/Frameworks"
if [ ! -d "$frameworks_dir" ]; then
  exit 0
fi

find "$frameworks_dir" -maxdepth 1 -type d -name "*.framework" | while IFS= read -r framework; do
  sig_info="$(/usr/bin/codesign -dv --verbose=4 "$framework" 2>&1 || true)"
  if printf '%s' "$sig_info" | /usr/bin/grep -q "Signature=adhoc"; then
    echo "Re-signing ad-hoc framework: $(basename "$framework")"
    /usr/bin/codesign --force --sign "$EXPANDED_CODE_SIGN_IDENTITY" --timestamp=none "$framework"
  fi
done
