# Modern App Extension

This directory contains the macOS 12+ implementation of GLTFQuickLook. The host
is a menu-bar application that embeds a preview extension and a thumbnail
extension. Unlike the legacy `.qlgenerator`, the host stays open so it can prepare
sidecar-dependent models before sandboxed Quick Look processes request them.

## Runtime Model

GLB documents and self-contained glTF files are rendered directly. A `.gltf` that
references external buffers or textures is converted into a self-contained cache.
The cache is stored in an extended attribute on the source document, never by
rewriting the original model.

The app watches `~/Downloads` by default and any additional folders selected from
the `GLTFQL` menu. Relevant file changes trigger a targeted, debounced preparation
rather than a full-library rescan.

Optional compatibility processing includes:

- Unreal material reconstruction from sibling `Materials` and `Textures` trees.
- Removal of uniform pure-red vertex colors used as export artifacts.
- Inlining of external buffers, images, and data dependencies.
- Normalization of integer skin weights rejected by SceneKit.
- Compaction of exceptional uModel exports with at least 100 animations or 10,000
  accessors; the prepared cache retains the first 10 animations.

The interactive SceneKit view is transparent and lets the Quick Look host provide
the correct Light or Dark Mode background.

## Build

Install XcodeGen and generate the project from the repository root:

```bash
brew install xcodegen
xcodegen generate --spec ModernAppExtension/project.yml
open ModernAppExtension/GLTFQuickLook.xcodeproj
```

GLTFSceneKit is pinned in `project.yml` to the revision used by the release build.
The `GLTFQuickLook` scheme builds the host and both extensions. `GLTFCachePrep` is
the command-line preparation utility used for diagnostics.

For a reproducible ad hoc signed artifact:

```bash
Scripts/package-release.sh
```

Artifacts are written to `dist/`. The public beta is Apple Silicon only; other
architectures may be built from source but are not part of the tested binary.

## Gatekeeper

The public beta is ad hoc signed and not notarized. Users can approve it from
**System Settings > Privacy & Security > Open Anyway**. If macOS keeps the embedded
extensions quarantined, remove quarantine from the complete bundle:

```bash
xattr -dr com.apple.quarantine /Applications/GLTFQuickLook.app
open /Applications/GLTFQuickLook.app
```

## Cache Limitations

Prepared caches depend on extended attributes. Filesystems that do not support
large extended attributes can reject or discard them. Copying a glTF file through
some archives, cloud providers, or Windows-oriented volumes can also remove the
cache; using **Reanalyser les dossiers** regenerates it without modifying the source
model.

The host scans only local folders configured by the user plus `~/Downloads`. It
does not upload model data or include analytics.
