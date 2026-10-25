# MoonlightDuo

Custom Moonlight iOS client for the Duo streaming setup.

> **Publication status:** The privacy-reviewed build 11 source is published here as a preview. No public pre-signed installer is available. Build and sign this fork with your own Apple account for reinstallation. Build 11 changes the Gaming mode-switcher swipe reveal area and threshold, but the gesture has not yet been confirmed by hands-on testing.

## Source and dependencies

The custom client is based on [Moonlight iOS/tvOS](https://github.com/moonlight-stream/moonlight-ios) revision `02dc9780496eeeac6d01c8bbdccb8b6fe71ef28a`. `X1Kit` and the locally modified `moonlight-common-c` are vendored at the base revisions listed in [SOURCE_PROVENANCE.md](SOURCE_PROVENANCE.md), together with packaged build libraries. The upstream Xcode Swift package lockfile was restored at its pinned revision. The original upstream README and applicable licenses are retained.

```sh
git clone https://github.com/moni11811/MoonlightDuo.git
cd MoonlightDuo
open Moonlight.xcodeproj
```

Use a current Xcode capable of building the project for your target iOS version. Allow Xcode to resolve the Swift packages pinned in `Moonlight.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved`. Choose the Moonlight iOS target and your device. Under **Signing & Capabilities**, select your own Apple development team and set a unique bundle identifier if needed, then build and run. Signing credentials, provisioning profiles, and device registration belong in your own Apple account and must stay out of this repository. Apple's development provisioning can expire, so an IPA signed for one device is not an indefinite public installer.

The source snapshot came from the installed build 11 development tree, but a private host-name comparison was replaced with a generic safe-resize bootstrap flag for publication. On the configured Duo host that selects the same path. The published source is not byte-identical to the privately signed IPA; rebuild and verify it on your device.

## Releases and verification

No public install artifact is available yet. Source releases identify the commit to check out. Any future binary release must identify the matching source commit, build number, build environment, artifact format, and SHA-256 checksum. Verify a downloaded file before using it:

```sh
shasum -a 256 path/to/downloaded-file
```

Compare the entire 64-character output with the checksum in that release. If the artifact is unsigned, sign it with your own Apple account before installation. If it is a development-signed IPA, its provisioning and device eligibility must be checked before use.

## Upstream

Moonlight is developed by the [Moonlight team](https://github.com/moonlight-stream/moonlight-ios). The upstream project and its dependencies retain their respective licenses and notices. This repository is an independent customization, not the upstream Moonlight distribution.
