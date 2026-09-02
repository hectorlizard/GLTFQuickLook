# Changelog

All notable changes to GLTFQuickLook are documented here.

## 1.1.0-beta.1 - 2026-09-02

### Added

- Autonomous extended-attribute caches for sidecar-based glTF documents.
- Continuous, targeted preparation of Downloads and user-selected folders.
- Unreal `.props.txt` material and texture reconstruction.
- Support for dense Sketchfab documents and oversized animated uModel exports.
- Preservation of the first 10 animations in compacted character caches.
- Skin-weight normalization and optional pure-red vertex-color cleanup.

### Fixed

- Finder thumbnail generation for prepared sidecar documents.
- Quick Look memory growth and repeated full-folder rescans.
- Scene framing and loading stability for large or dense models.
- Light and Dark Mode previews now use the native Quick Look background.

### Distribution

- Requires macOS 12 or later.
- The downloadable beta targets Apple Silicon and is ad hoc signed, not notarized.

## 1.0.1

- Added the first modern Quick Look App Extension implementation.
