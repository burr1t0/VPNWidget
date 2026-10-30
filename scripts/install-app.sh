#!/bin/bash
# Builds VPNWidget.app (host app with the agent + widget extension) and installs it into ~/Applications.
#   scripts/install-app.sh
set -euo pipefail

cd "$(dirname "$0")/.."
APP_DIR="$HOME/Applications"
# The ".noindex" suffix keeps Spotlight out of the build folder, so a search for the app does not find two copies.
DERIVED="build.noindex/xcode"
LSREGISTER=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister

# The signing team comes from the Apple Development certificate in the keychain, so no personal ID lives in the repo.
# Override with VPNWIDGET_TEAM=<Team ID> if you have several certificates.
TEAM="${VPNWIDGET_TEAM:-$(security find-certificate -c "Apple Development" -p 2>/dev/null \
    | openssl x509 -noout -subject 2>/dev/null | sed -n 's/.*OU=\([A-Z0-9]\{10\}\).*/\1/p' | head -1)}"
if [[ -z "$TEAM" ]]; then
    echo "Не найден сертификат Apple Development. Войдите в Xcode с Apple ID или задайте VPNWIDGET_TEAM=<Team ID>." >&2
    exit 1
fi

xcodegen generate
mkdir -p build
if ! xcodebuild -project VPNWidget.xcodeproj -scheme VPNWidget -configuration Release \
    -derivedDataPath "$DERIVED" -allowProvisioningUpdates DEVELOPMENT_TEAM="$TEAM" build > build/xcodebuild.log 2>&1; then
    grep -E "error:" build/xcodebuild.log | head -10 >&2
    echo "Сборка не удалась, полный лог: build/xcodebuild.log" >&2
    exit 1
fi
tail -1 build/xcodebuild.log

if [[ "${1:-}" == "--build-only" ]]; then exit 0; fi

pkill -x VPNWidget 2>/dev/null || true
# The widget extension is a separate long-lived process; if it is left running, the system keeps showing the old build.
pkill -x VPNWidgetExtension 2>/dev/null || true
mkdir -p "$APP_DIR"
rm -rf "$APP_DIR/VPNWidget.app"
BUILT="$DERIVED/Build/Products/Release/VPNWidget.app"
cp -R "$BUILT" "$APP_DIR/"

"$LSREGISTER" -u "$BUILT" 2>/dev/null || true
"$LSREGISTER" -f "$APP_DIR/VPNWidget.app"
open "$APP_DIR/VPNWidget.app"
echo "Готово: $APP_DIR/VPNWidget.app"
