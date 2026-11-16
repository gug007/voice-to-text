#!/usr/bin/env bash
set -euo pipefail

# Builds libtailscale (Tailscale's embeddable node, written in Go) as static
# archives for every platform the two apps ship on, and installs them with the
# TailscaleKit Swift bindings as a local Swift package in
# VoiceToText/Vendor/TailscaleKit (gitignored):
#
#   Package.swift                 one library product, TailscaleKit
#   libtailscale.xcframework      static archives: macOS (arm64 + x86_64),
#                                 iOS device (arm64), iOS simulator (arm64 +
#                                 x86_64), each with tailscale.h and a
#                                 `libtailscale` Clang module map
#   Sources/TailscaleKit          the bindings, copied from the same commit
#                                 and patched (see apply_patches below)
#
# The Mac project references the package by path (project.pbxproj) and the
# iPhone project through `packages:` in Mobile/project.yml, so the package has
# to exist before either project resolves its packages: run this once after a
# fresh clone, before opening Xcode. scripts/dev.sh, scripts/install.sh and the
# CI workflows call it first. It skips the build when the installed package was
# built from this commit by this version of the script.
#
# Needs git, Go (`brew install go`; the go.mod at the pinned commit names its
# own toolchain, which Go downloads on first use) and Xcode's command-line
# tools with the iOS SDKs.
#
# usage: ./scripts/build-tailscale.sh
#   TAILSCALE_SRC=<checkout>  build from an existing checkout of the pinned
#                             commit instead of cloning one

TS_REPO="https://github.com/tailscale/libtailscale"
TS_COMMIT="dacde75057ff350e146505829beff446e6823966"

# Both apps' deployment targets. The bindings' Listener types need macOS 15 /
# iOS 18 themselves, so neither can go lower without changes upstream.
MACOS_MIN="15.0"
IOS_MIN="18.0"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
OUT_DIR="$REPO_ROOT/VoiceToText/Vendor/TailscaleKit"
STAMP="$OUT_DIR/.build-stamp"
STAMP_VALUE="$TS_COMMIT $(shasum -a 256 "${BASH_SOURCE[0]}" | cut -c1-16)"

installed_is_current() {
    [ -f "$STAMP" ] && [ "$(cat "$STAMP")" = "$STAMP_VALUE" ] || return 1
    [ -f "$OUT_DIR/Package.swift" ] && [ -f "$OUT_DIR/libtailscale.xcframework/Info.plist" ] &&
        [ -f "$OUT_DIR/Sources/TailscaleKit/TailscaleNode.swift" ]
}

if installed_is_current; then
    echo "✓ libtailscale ${TS_COMMIT:0:12} is already built in $OUT_DIR"
    exit 0
fi

for tool in git go xcodebuild xcrun lipo; do
    if ! command -v "$tool" >/dev/null 2>&1; then
        echo "✗ $tool not found; building libtailscale needs git, Go and Xcode" >&2
        [ "$tool" = go ] && echo "  (Go: brew install go)" >&2
        exit 1
    fi
done

WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/libtailscale-build.XXXXXX")"
trap 'rm -rf "$WORK_DIR"' EXIT

if [ -n "${TAILSCALE_SRC:-}" ]; then
    SRC="$(cd "$TAILSCALE_SRC" && pwd)"
    ACTUAL_COMMIT="$(git -C "$SRC" rev-parse HEAD)"
    if [ "$ACTUAL_COMMIT" != "$TS_COMMIT" ]; then
        echo "✗ $SRC is at $ACTUAL_COMMIT, expected $TS_COMMIT" >&2
        exit 1
    fi
    if [ -n "$(git -C "$SRC" status --porcelain --untracked-files=no)" ]; then
        echo "✗ $SRC has local changes to tracked files" >&2
        exit 1
    fi
    echo "→ using libtailscale checkout at $SRC"
else
    SRC="$WORK_DIR/src"
    echo "→ fetching libtailscale ${TS_COMMIT:0:12}"
    git init --quiet "$SRC"
    git -C "$SRC" remote add origin "$TS_REPO"
    git -C "$SRC" fetch --quiet --depth 1 origin "$TS_COMMIT"
    git -C "$SRC" -c advice.detachedHead=false checkout --quiet FETCH_HEAD
    ACTUAL_COMMIT="$(git -C "$SRC" rev-parse HEAD)"
    if [ "$ACTUAL_COMMIT" != "$TS_COMMIT" ]; then
        echo "✗ fetched $ACTUAL_COMMIT, expected $TS_COMMIT" >&2
        exit 1
    fi
fi

ARCHIVES="$WORK_DIR/archives"
mkdir -p "$ARCHIVES"

# One c-archive per GOOS/GOARCH. `-trimpath` keeps the builder's paths out of
# the binary; `-w` drops DWARF, which the app's own dSYM never uses.
go_archive() {
    local out="$1" goos="$2" goarch="$3" cc="$4" cflags="$5"
    echo "→ building $(basename "$out") ($goos/$goarch)"
    (
        cd "$SRC"
        env GOOS="$goos" GOARCH="$goarch" CGO_ENABLED=1 CC="$cc" \
            CGO_CFLAGS="$cflags" CGO_LDFLAGS="$cflags" \
            MACOSX_DEPLOYMENT_TARGET="$MACOS_MIN" \
            go build -trimpath -ldflags=-w -tags "$( [ "$goos" = ios ] && echo ios )" \
            -buildmode=c-archive -o "$out" . >"$out.log" 2>&1
    ) || {
        cat "$out.log" >&2
        exit 1
    }
}

# Upstream's iOS clang wrappers pin an old minimum; these pin the apps' own.
clang_wrapper() {
    local name="$1" sdk="$2" arch="$3" target="$4"
    local path="$WORK_DIR/$name"
    cat >"$path" <<EOF
#!/bin/sh
exec "$(xcrun --sdk "$sdk" --find clang)" -arch $arch -isysroot "$(xcrun --sdk "$sdk" --show-sdk-path)" $target "\$@"
EOF
    chmod +x "$path"
    echo "$path"
}

MAC_FLAGS="-mmacos-version-min=$MACOS_MIN"
go_archive "$ARCHIVES/macos-arm64.a" darwin arm64 "$(clang_wrapper cc-macos-arm64 macosx arm64 "$MAC_FLAGS")" "$MAC_FLAGS"
go_archive "$ARCHIVES/macos-x86_64.a" darwin amd64 "$(clang_wrapper cc-macos-x86_64 macosx x86_64 "$MAC_FLAGS")" "$MAC_FLAGS"
go_archive "$ARCHIVES/ios-arm64.a" ios arm64 \
    "$(clang_wrapper cc-ios-arm64 iphoneos arm64 "-mios-version-min=$IOS_MIN")" ""
go_archive "$ARCHIVES/ios-sim-arm64.a" ios arm64 \
    "$(clang_wrapper cc-ios-sim-arm64 iphonesimulator arm64 "-mios-simulator-version-min=$IOS_MIN")" ""
go_archive "$ARCHIVES/ios-sim-x86_64.a" ios amd64 \
    "$(clang_wrapper cc-ios-sim-x86_64 iphonesimulator x86_64 "-mios-simulator-version-min=$IOS_MIN")" ""

echo "→ assembling libtailscale.xcframework"
for platform in macos ios-sim; do
    mkdir -p "$ARCHIVES/$platform"
done
mkdir -p "$ARCHIVES/ios"
lipo -create -output "$ARCHIVES/macos/libtailscale.a" "$ARCHIVES/macos-arm64.a" "$ARCHIVES/macos-x86_64.a"
lipo -create -output "$ARCHIVES/ios-sim/libtailscale.a" "$ARCHIVES/ios-sim-arm64.a" "$ARCHIVES/ios-sim-x86_64.a"
cp "$ARCHIVES/ios-arm64.a" "$ARCHIVES/ios/libtailscale.a"
for arch in arm64 x86_64; do
    lipo "$ARCHIVES/macos/libtailscale.a" -verify_arch "$arch"
done

HEADERS="$WORK_DIR/headers"
mkdir -p "$HEADERS"
cp "$SRC/tailscale.h" "$HEADERS/"
cat >"$HEADERS/module.modulemap" <<'EOF'
module libtailscale {
    header "tailscale.h"
    export *
}
EOF

STAGE="$WORK_DIR/stage"
mkdir -p "$STAGE/Sources"
xcodebuild -create-xcframework \
    -library "$ARCHIVES/macos/libtailscale.a" -headers "$HEADERS" \
    -library "$ARCHIVES/ios/libtailscale.a" -headers "$HEADERS" \
    -library "$ARCHIVES/ios-sim/libtailscale.a" -headers "$HEADERS" \
    -output "$STAGE/libtailscale.xcframework" >"$WORK_DIR/xcframework.log" 2>&1 || {
    cat "$WORK_DIR/xcframework.log" >&2
    exit 1
}

echo "→ copying the TailscaleKit bindings"
cp -R "$SRC/swift/TailscaleKit" "$STAGE/Sources/TailscaleKit"
rm -rf "$STAGE/Sources/TailscaleKit/TailscaleKit.docc" "$STAGE/Sources/TailscaleKit/TailscaleKit.h"

# The bindings are written for upstream's framework target, whose umbrella
# header imports Foundation and exposes the C API to every Swift file. In a
# package the C API is its own module, so each file imports Foundation, and
# each one that calls the C API imports that too. The only other change:
# `LocalAPIClient.logout()` is internal upstream, and Sign Out needs it.
apply_patches() {
    local dir="$1" file
    for file in "$dir"/*.swift "$dir"/LocalAPI/*.swift; do
        if ! grep -q "^import Foundation$" "$file"; then
            /usr/bin/perl -0pi -e 's/^(import |#if )/import Foundation\n$1/m' "$file"
        fi
        if grep -q "tailscale_" "$file"; then
            /usr/bin/perl -0pi -e 's/^import Foundation$/import Foundation\nimport libtailscale/m' "$file"
        fi
        grep -q "^import Foundation$" "$file" || {
            echo "✗ couldn't add the Foundation import to $file" >&2
            exit 1
        }
        if grep -q "tailscale_" "$file" && ! grep -q "^import libtailscale$" "$file"; then
            echo "✗ couldn't add the libtailscale import to $file" >&2
            exit 1
        fi
    done
    /usr/bin/sed -i '' 's/^    func logout() async throws {$/    public func logout() async throws {/' "$dir/LocalAPI/LocalAPIClient.swift"
    grep -q "public func logout() async throws" "$dir/LocalAPI/LocalAPIClient.swift" || {
        echo "✗ couldn't make LocalAPIClient.logout public" >&2
        exit 1
    }
}
apply_patches "$STAGE/Sources/TailscaleKit"

# Go's runtime and Tailscale's packages call into these from the archive.
cat >"$STAGE/Package.swift" <<'EOF'
// swift-tools-version:6.0
// Generated by scripts/build-tailscale.sh; edit the script, not this file.
import PackageDescription

let package = Package(
    name: "TailscaleKit",
    platforms: [.macOS(.v15), .iOS(.v18)],
    products: [
        .library(name: "TailscaleKit", targets: ["TailscaleKit"]),
    ],
    targets: [
        .binaryTarget(name: "libtailscale", path: "libtailscale.xcframework"),
        .target(
            name: "TailscaleKit",
            dependencies: ["libtailscale"],
            path: "Sources/TailscaleKit",
            linkerSettings: [
                .linkedFramework("CoreFoundation"),
                .linkedFramework("Security"),
                .linkedFramework("IOKit", .when(platforms: [.macOS])),
                .linkedLibrary("resolv"),
            ]
        ),
    ]
)
EOF
cp "$SRC/LICENSE" "$STAGE/LICENSE"

echo "→ installing into $OUT_DIR"
rm -rf "$OUT_DIR"
mkdir -p "$(dirname "$OUT_DIR")"
mv "$STAGE" "$OUT_DIR"
echo "$STAMP_VALUE" >"$STAMP"
echo "✓ libtailscale ${TS_COMMIT:0:12} built into $OUT_DIR"
