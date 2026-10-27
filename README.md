# MacTetris

Tetris for macOS, plus a standalone browser version.

## Native macOS version

Requires macOS 13 or later and Swift 5.9 or later (Xcode Command Line Tools).

```sh
swift run -c release Tetris
```

Build the executable with `swift build -c release`; the output is `.build/release/Tetris`.
The icon generator is in `tool/make_icon.swift`.

## Web version

Open `web/index.html` in a modern browser. No dependencies or build step are required.

Controls: left/right to move, up/X to rotate clockwise, Z counterclockwise,
down for soft drop, Space for hard drop, C to hold, P to pause,
R to restart, and M to mute. The web version also supports touch controls.

Generated builds and local settings are excluded from version control.
