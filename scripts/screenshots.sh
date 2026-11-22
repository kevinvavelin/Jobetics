#!/usr/bin/env bash
# Generates App Store screenshots (iPhone 6.9" + iPad 13") from the demo data.
# Usage: scripts/screenshots.sh [en|fr|es ...]   (default: en fr es)
# Requires the watchOS simulator runtime: xcodebuild -downloadPlatform watchOS
set -euo pipefail
cd "$(dirname "$0")/.."

LANGS=("${@:-en fr es}")
[[ $# -eq 0 ]] && LANGS=(en fr es)
OUT="Screenshots"
DERIVED="${DERIVED:-build/DerivedData}"
BUNDLE="fr.vavelinkevin.Jobetics"
IPHONE="iPhone 17 Pro Max"
IPAD="iPad Pro 13-inch (M5)"

xcodebuild -project Jobetics.xcodeproj -scheme Jobetics -configuration Debug \
  -destination "platform=iOS Simulator,name=$IPHONE" -derivedDataPath "$DERIVED" \
  CODE_SIGNING_ALLOWED=NO build -quiet
APP="$DERIVED/Build/Products/Debug-iphonesimulator/Jobetics.app"

udid() { xcrun simctl list devices available | grep -F "$1 (" | head -1 | grep -oE '[0-9A-F-]{36}'; }

prepare() {
  local id=$1
  xcrun simctl boot "$id" 2>/dev/null || true
  xcrun simctl bootstatus "$id" -b >/dev/null
  xcrun simctl status_bar "$id" override --time "9:41" --dataNetwork wifi --wifiBars 3 \
    --cellularMode active --cellularBars 4 --batteryState charged --batteryLevel 100
  xcrun simctl install "$id" "$APP"
}

shoot() { # device-id folder name lang appearance [launch args...]
  local id=$1 folder=$2 name=$3 lang=$4 appearance=$5; shift 5
  local region; case $lang in fr) region=fr_FR;; es) region=es_ES;; *) region=en_US;; esac
  xcrun simctl ui "$id" appearance "$appearance"
  xcrun simctl terminate "$id" "$BUNDLE" 2>/dev/null || true
  xcrun simctl launch "$id" "$BUNDLE" -demo -screenshots -AppleLanguages "($lang)" -AppleLocale "$region" "$@" >/dev/null
  sleep 4
  mkdir -p "$OUT/$lang/$folder"
  xcrun simctl io "$id" screenshot --type=png "$OUT/$lang/$folder/$name.png" >/dev/null
  # The framebuffer is captured in portrait: turn landscape iPad captures upright.
  [[ $folder == iPad ]] && sips -r 270 "$OUT/$lang/$folder/$name.png" >/dev/null
  echo "  ✓ $lang/$folder/$name"
}

PHONE_ID=$(udid "$IPHONE"); PAD_ID=$(udid "$IPAD")
prepare "$PHONE_ID"; prepare "$PAD_ID"

# iPad screenshots are taken in landscape (sidebar next to content). simctl can't rotate,
# so a one-line UI test does it; the orientation persists afterwards.
xcodebuild test -project Jobetics.xcodeproj -scheme Jobetics -destination "id=$PAD_ID" -derivedDataPath "$DERIVED" \
  -parallel-testing-enabled NO -only-testing:JobeticsUITests/OrientationHelper/testRotateToLandscape \
  CODE_SIGNING_ALLOWED=NO -quiet
xcrun simctl install "$PAD_ID" "$APP"

for lang in "${LANGS[@]}"; do
  echo "iPhone · $lang"
  shoot "$PHONE_ID" iPhone 01-home        "$lang" light -tab home
  shoot "$PHONE_ID" iPhone 02-jobs        "$lang" light -tab jobs
  shoot "$PHONE_ID" iPhone 03-job-detail  "$lang" light -deeplink jobetics://jobs/job-ios-redesign
  shoot "$PHONE_ID" iPhone 04-board       "$lang" light -tab board
  shoot "$PHONE_ID" iPhone 05-chat        "$lang" light -deeplink jobetics://chat/c-orbit
  shoot "$PHONE_ID" iPhone 06-focus       "$lang" light -deeplink jobetics://focus
  shoot "$PHONE_ID" iPhone 07-hiring      "$lang" light -tab home -mode hiring
  shoot "$PHONE_ID" iPhone 08-profile     "$lang" light -tab profile
  shoot "$PHONE_ID" iPhone 09-home-dark   "$lang" dark  -tab home

  echo "iPad · $lang"
  shoot "$PAD_ID" iPad 01-home            "$lang" light -tab home
  shoot "$PAD_ID" iPad 02-accounting      "$lang" light -tab accounting
  shoot "$PAD_ID" iPad 03-board           "$lang" light -tab board
  shoot "$PAD_ID" iPad 04-calendar        "$lang" light -tab calendar
  shoot "$PAD_ID" iPad 05-invoices        "$lang" light -tab invoices
  shoot "$PAD_ID" iPad 06-jobs            "$lang" light -tab jobs
  shoot "$PAD_ID" iPad 07-moderation      "$lang" light -tab admin
  shoot "$PAD_ID" iPad 08-portfolio       "$lang" dark  -tab portfolio
done

xcrun simctl status_bar "$PHONE_ID" clear; xcrun simctl status_bar "$PAD_ID" clear
echo "Screenshots written to $OUT/"
