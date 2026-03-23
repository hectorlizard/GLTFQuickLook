# GLTFQuickLook
macOS QuickLook plugin for glTF files. (.gltf/.glb)

![ScreenShot](https://github.com/magicien/GLTFQuickLook/blob/master/screenshot.png)

![ScreenShot2](https://github.com/magicien/GLTFQuickLook/blob/master/screenshot2.gif)

## System Requirements

- macOS 10.13 (High Sierra) or later

> **Note for macOS 10.15+ and Apple Silicon**: Apple has deprecated `.qlgenerator` plugins and they are fully unsupported in macOS 15 (Sequoia). There are now two versions of this project available:
> - **Legacy** (`.qlgenerator`): For macOS 10.13 and 10.14 (see instructions below).
> - **Modern** (App Extension): For macOS 10.15+, including native Apple Silicon support. See the [ModernAppExtension folder](ModernAppExtension/) for details.

## Install (Modern - macOS 10.15+)

1. Download the latest `GLTFQuickLook.app` release from [Releases](https://github.com/magicien/GLTFQuickLook/releases/latest).
2. Drag and drop `GLTFQuickLook.app` into your `/Applications` folder.
3. Open the app **once** (it will casually launch and exit, registering the extension with macOS).
4. Run `qlmanage -r` to reload QuickLook plugins.

## Install (Legacy - macOS 10.13, 10.14)

### Using [Homebrew Cask](https://github.com/phinze/homebrew-cask)

- Run `brew install gltfquicklook`
- Run `xattr -r -d com.apple.quarantine ~/Library/QuickLook/GLTFQuickLook.qlgenerator` to allow GLTFQuickLook.qlgenerator to run.

### Manually

1. Download **GLTFQuickLook_vX.X.X.zip** from [Releases](https://github.com/magicien/GLTFQuickLook/releases/latest).
2. Put **GLTFQuickLook.qlgenerator** (in the zip file) into `/Library/QuickLook` (for all users) or `~/Library/QuickLook` (only for the logged-in user).
3. Run `sudo xattr -r -d com.apple.quarantine /Library/QuickLook/GLTFQuickLook.qlgenerator` or `xattr -r -d com.apple.quarantine ~/Library/QuickLook/GLTFQuickLook.qlgenerator` to allow GLTFQuickLook.qlgenerator to run.
4. Run `qlmanage -r` command to reload QuickLook plugins.

## Build

### Modern App Extension (Recommended for macOS 12+)
See the [ModernAppExtension/README.md](ModernAppExtension/README.md) for build instructions using `xcodegen` and Swift Package Manager.

### Legacy (.qlgenerator)
It needs to install [Carthage](https://github.com/Carthage/Carthage) to get frameworks.
```
$ git clone https://github.com/magicien/GLTFQuickLook.git
$ cd GLTFQuickLook
$ carthage bootstrap --platform mac
$ xcodebuild
```

## See also

- [GLTFSceneKit](https://github.com/magicien/GLTFSceneKit/) - glTF loader for SceneKit
