# GLTFQuickLook Modern App Extension

This folder contains the modern macOS App Extension implementation of GLTFQuickLook for macOS 10.15 (Catalina) and newer, including full support for Apple Silicon (M1/M2/M3) and upcoming macOS versions like Sequoia.

Apple deprecated `.qlgenerator` plugins and requires QuickLook extensions to be embedded inside a macOS application bag (`.app`).

## Installation

1. Download the latest `GLTFQuickLook.app` release.
2. Drag and drop `GLTFQuickLook.app` into your `/Applications` folder.
3. Open the app once (it will launch and exit immediately, registering the QuickLook extensions with macOS).
4. Select any `.gltf` or `.glb` file in Finder and press `Space` to preview.

## Quick Look Appearance

The interactive preview uses a transparent SceneKit view and a non-opaque backing
layer so the Quick Look host supplies the background in Light and Dark Mode.
This does not change scene lighting, materials, prepared caches, or Finder
thumbnail generation. The exact background or translucency is controlled by
macOS and its accessibility settings.

Verified on 2026-08-30 with `d2330e5c88fe40f1.glb` (Slippy Hollow) and
`SM_TH08_RainbowMushrooms01.gltf` (Crash): both render visible geometry with zero
background alpha under Aqua and Dark Aqua, including an appearance change on
the same view.

## Oversized Animated Exports

Quick Look caches automatically compact exceptional uModel character exports
that contain at least 100 animation clips or 10,000 accessors. The source file
is never modified: its full animation set remains available to other software.
The prepared cache retains the first 10 animations and only the accessors,
buffer views, and binary ranges required by the mesh, skin, textures, and those
clips.

Normalized integer skin weights are converted to float data inside the cache,
because SceneKit otherwise refuses to construct the skinner. Ordinary glTF
files remain unchanged. Cache resource fingerprints are sorted to prevent
unchanged documents from being regenerated repeatedly.

Verified on 2026-09-02 with `SK_CP3701_Crash.gltf` and `SK_CP3705_Neo.gltf`.
Crash's prepared cache fell from about 397 MB to 14.8 MB; both files produced
textured system thumbnails with working skins.

## Build Setup

To build this modern extension from source, you need [XcodeGen](https://github.com/yonaskolb/XcodeGen) and macOS 12.0+ with Xcode.

```bash
# Install XcodeGen
brew install xcodegen

# Generate the Xcode Project
xcodegen

# Open the project
open GLTFQuickLook.xcodeproj
```

You can then build the `GLTFQuickLook` scheme directly from Xcode. Swift Package Manager will automatically fetch `GLTFSceneKit`.
