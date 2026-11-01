#!/bin/zsh
# Runs the narrated Logsperity training tour in the iPhone simulator (about 17 minutes).
#   demo/run-demo.sh            # just run it (film the screen with your camera)
#   demo/run-demo.sh --record   # also save a screen recording to demo/Logsperity-training.mov (video only)
#   demo/run-demo.sh --voice-check   # just hear the narrator, to set the volume
# Turn the Mac's volume up: the narrator speaks through the Mac, and HERB speaks from the app in the simulator.
# The narrator uses the Mac's best English voice. For a more natural one, download a Premium or Enhanced voice in
# System Settings → Accessibility → Spoken Content → System voice → Manage Voices (e.g. "Zoe (Premium)"), or pick
# one by name:  VOICE="Evan (Enhanced)" demo/run-demo.sh
set -e
cd "${0:A:h}/.."
export PATH="/opt/homebrew/bin:$PATH"
export DEVELOPER_DIR=${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}
DEVICE=${DEVICE:-"iPhone 17"}
NARRATION=/tmp/logsperity-narration

if [[ -z "$VOICE" ]]; then
  VOICE=$(say -v '?' | grep -E "en_(US|GB)" | grep -E "\((Premium|Enhanced)" | head -1 | sed -E 's/  +en_.*//')
  [[ -z "$VOICE" ]] && VOICE="Daniel"
fi
echo "Narrator voice: $VOICE"

xcodegen -q
xcrun simctl boot "$DEVICE" 2>/dev/null || true
open "$DEVELOPER_DIR/Applications/Simulator.app" 2>/dev/null || open -a Simulator 2>/dev/null || true
TEST=TrainingTour/testTrainingTour
[[ "$1" == "--voice-check" ]] && TEST=TrainingTour/testVoiceCheck
[[ "$1" != "--voice-check" ]] && { xcrun simctl uninstall booted com.prosperitysimplified.logsperity 2>/dev/null || true; }  # start from the welcome screen

echo "Building the tour…"
xcodebuild build-for-testing -project Logsperity.xcodeproj -scheme LogsperityDemo \
  -destination "platform=iOS Simulator,name=$DEVICE" -derivedDataPath build/demo -quiet

# The tour drops each narration line here; speak it and answer with a .done file.
rm -rf $NARRATION && mkdir -p $NARRATION && touch $NARRATION/listening
(
  while [[ -e $NARRATION/listening ]]; do
    for f in $NARRATION/*.txt(N); do
      say -v "$VOICE" -r 185 -f "$f"
      touch "${f%.txt}.done" && rm -f "$f"
    done
    sleep 0.1
  done
) &
SPEAKER=$!

if [[ "$1" == "--record" ]]; then
  xcrun simctl io booted recordVideo --force demo/Logsperity-training.mov &
  REC=$!
fi
cleanup() {
  rm -f $NARRATION/listening
  kill $SPEAKER 2>/dev/null || true
  [[ -n "$REC" ]] && { kill -INT $REC 2>/dev/null; wait $REC 2>/dev/null || true; }
}
trap cleanup EXIT

echo "Starting the tour…"
xcodebuild test-without-building -project Logsperity.xcodeproj -scheme LogsperityDemo \
  -destination "platform=iOS Simulator,name=$DEVICE" -derivedDataPath build/demo -only-testing:LogsperityDemo/$TEST 2>&1 \
  | grep --line-buffered -E "🎙|⚠️|Narrator voice|Test Case|error" || true
