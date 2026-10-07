# iPhone Mirror

A tiny macOS app that mirrors your iPhone's screen live over a USB cable, inside Apple's official iPhone 17 Pro frame. Good for recording app demos.

It uses the same screen-capture feed QuickTime uses for a cable-connected iPhone. You get full resolution at 60 fps, drawn as each frame arrives. No AirPlay, no streaming service.

## Build

```bash
./fetch-bezels.sh   # downloads Apple's bezel images (not included, see below)
./build.sh          # builds "iPhone Mirror.app"
open "iPhone Mirror.app"
```

You need macOS 14+ and Xcode command line tools. `fetch-bezels.sh` needs Python 3 with Pillow (`pip3 install pillow`).

## Use

1. Plug the iPhone **directly** into the Mac. Through a USB hub it may freeze or show nothing.
2. Unlock it and tap **Trust** if it asks. Allow camera access when macOS prompts: macOS treats the phone's screen as a camera.
3. The phone appears within a few seconds. iOS only sends a frame when something changes, so a still or locked phone stays black until you touch it.

| Key | Does |
|-----|------|
| B | cream 16:9 background (for recording) / phone only |
| C | frame color: silver, deep blue, orange, black, white |
| 1 / 2 / 3 | small / medium / full-height |
| T | keep on top of other windows |
| Q, ⌘Q, right-click → Quit | quit |

Drag anywhere to move it; resize from the edges.

## Limits

- View only: you can't tap the phone from the Mac. Apple's built-in iPhone Mirroring app does that.
- Portrait only.
- Frame rate is logged to `~/Library/Logs/iPhoneMirror.log`.

## Bezel images

The frames are Apple's Product Bezels from [Apple Design Resources](https://developer.apple.com/design/resources/). Apple's license doesn't allow redistributing them, so `fetch-bezels.sh` downloads them from Apple when you build.
