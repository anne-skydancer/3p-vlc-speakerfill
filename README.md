# 3p-vlc-speakerfill

Windows x64 autobuild package for Vulkanstorm: the `speakerfill_output` VLC audio output module, prebuilt so
the viewer build no longer needs a MinGW compiler.

## What it is

VLC 3.0.21's `modules/audio_output/wasapi.c` (LGPL-2.1-or-later), with a string-replacement patch
(`prepare_speakerfill.cmake`) that adds the Vulkanstorm speaker-fill layout selection and music clock
reporting, built into the plugin DLL `libspeakerfill_output_plugin.dll`. The package does not change the
module's behaviour, the patch or the VLC version; it only moves the build out of the viewer.

The viewer's `vlc_speakerfill` audio filter plugin (`vlc_speakerfill.cpp`) stays in the viewer repository
and is built with MSVC as before.

## Why it exists

VLC's module is GNU C and cannot be built with MSVC. It was previously compiled during every Windows viewer
build with MinGW gcc. Building it here once removes that toolchain requirement from the viewer.

## Temporary

This package is deleted when the Rust audio engine (which performs speaker fill itself) reaches
`vkstorm-release`; the viewer then drops `vlc-speakerfill` from its `autobuild.xml`.

## Contents

```
lib/release/libspeakerfill_output_plugin.dll
share/vlc-speakerfill/source/                      hash-checked VLC sources + generated speakerfill_output.c (source offer)
share/vlc-speakerfill/prepare_speakerfill.cmake    the transformation
share/vlc-speakerfill/build-info.txt               package version and compiler version
LICENSES/vlc-speakerfill.txt                       VLC COPYING.LIB (LGPL-2.1), SHA-256 pinned
VERSION.txt
```

## Build

Dependency: the `vlc-bin` package (same URL and hash as the viewer) supplies the VLC plugin headers
and the `libvlccore` import library.

Compiler: `x86_64-w64-mingw32-gcc` must be on PATH; the build fails if it is missing and never falls back
to another compiler. CI installs llvm-mingw 20260616 (LLVM 22.1.8, UCRT, x86_64) pinned by SHA-256, the
toolchain the module was validated with. The compiler version is printed in the CI log and stored in
`share/vlc-speakerfill/build-info.txt`. The windows-2025 image also ships gcc 15.2.0 / binutils 2.46, but
that has not been validated with this module.

```
autobuild install -A 64
autobuild build -A 64 -c release        # downloads sources, patches, compiles, smoke-tests
autobuild package -A 64 -c release --archive-format tzst
```

The smoke test checks that the DLL exports `vlc_entry__3_0_0f`, `vlc_entry_license__3_0_0f` and
`vlc_entry_copyright__3_0_0f` and imports `libvlccore.dll`. The behavioural test is the viewer's
`vlc_speakerfill_test`.

## Releasing / bumping

1. Change `VERSION.txt` (`<VLC version>.<package revision>`, e.g. `3.0.21.2`) and commit.
2. The owner creates and pushes tag `v<VERSION>` (e.g. `v3.0.21.1`); the workflow builds and publishes a
   GitHub release with the `.tar.zst` and its SHA-256.
3. In the viewer's `autobuild.xml` put the release URL, the SHA-256 (`hash_algorithm` `sha256`) and the
   version in the `vlc-speakerfill` entry.

Changing the VLC version also requires new SHA-256 pins in `prepare_speakerfill.cmake` and `build.cmake`,
the `vlc-bin` entry in `autobuild.xml`, and the `3_0_0f` symbol names in `build.cmake`.
