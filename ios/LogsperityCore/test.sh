#!/bin/sh
# Runs the engine's tests. With full Xcode installed, plain `swift test` works; with only the Command Line
# Tools, the Swift Testing framework lives outside the default search paths, so point the build at it.
cd "$(dirname "$0")"
CLT=/Library/Developer/CommandLineTools/Library/Developer
if xcode-select -p | grep -q CommandLineTools; then
  exec swift test -Xswiftc -F$CLT/Frameworks -Xlinker -F$CLT/Frameworks \
    -Xlinker -rpath -Xlinker $CLT/Frameworks -Xlinker -rpath -Xlinker $CLT/usr/lib "$@"
fi
exec swift test "$@"
