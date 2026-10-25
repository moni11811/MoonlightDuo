# MoonlightDuo

Custom Moonlight iOS client for the Duo streaming setup.

> **Publication status:** The finalized custom source and a reinstallable release have not been published yet. This repository currently contains documentation only. Do not use a stock Moonlight build as a substitute for the custom client.

## Source and dependencies

The custom client is based on [Moonlight iOS/tvOS](https://github.com/moonlight-stream/moonlight-ios) revision `02dc9780496eeeac6d01c8bbdccb8b6fe71ef28a`. The source publication will preserve its license and notices, the `X1Kit` and `moonlight-common-c` submodule references, and the Xcode Swift package resolution. The exact custom commit will be recorded here after the final build is frozen and reviewed.

Once source is published:

```sh
git clone --recursive https://github.com/moni11811/MoonlightDuo.git
cd MoonlightDuo
git submodule update --init --recursive
open Moonlight.xcodeproj
```

In Xcode, choose the Moonlight iOS target and your device. Under **Signing & Capabilities**, select your own Apple development team and set a unique bundle identifier if needed, then build and run. Signing credentials, provisioning profiles, and device registration belong in your own Apple account and must stay out of this repository. Apple's development provisioning can expire, so an IPA signed for one device is not an indefinite public installer.

## Releases and verification

No public install artifact is available yet. A future release must identify the matching source commit, build number, build environment, artifact format, and SHA-256 checksum. Verify a downloaded file before using it:

```sh
shasum -a 256 path/to/downloaded-file
```

Compare the entire 64-character output with the checksum in that release. If the artifact is unsigned, sign it with your own Apple account before installation. If it is a development-signed IPA, its provisioning and device eligibility must be checked before use.

## Upstream

Moonlight is developed by the [Moonlight team](https://github.com/moonlight-stream/moonlight-ios). The upstream project and its dependencies retain their respective licenses and notices. This repository is an independent customization, not the upstream Moonlight distribution.
