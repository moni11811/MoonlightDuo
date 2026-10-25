# Source provenance

This tree was prepared from the finalized build 11 source-only snapshot,
`moonlight-native-source-build11.tar.gz`, SHA-256
`bc83dfc1fb6ae5a58322c6f2fe66341f43a36fae2582e3f9701fb8a08e67a7c8`.
The archive itself and its development Git metadata are not published.

- Moonlight iOS/tvOS base: `02dc9780496eeeac6d01c8bbdccb8b6fe71ef28a`
- X1Kit base: `6e842ae9d5a21916d7c9693c7385d1ac672bc4fa`
- moonlight-common-c base: `f900dd4767759c7b9d0e93bcea666b55c69ea62f`, with local modifications
- Nested common-c dependencies and packaged libraries: vendored as supplied
  in the verified build 11 source snapshot
- Swift package lockfile: restored from the pinned Moonlight upstream revision
  because the source-only snapshot omitted it; it pins OpenSSL-Package
  `a3809db22a45e3ff658377a24da252982a306b9b`

`X1Kit/` and `moonlight-common/moonlight-common-c/` are committed as ordinary
source directories so the modified common-c files remain available. They are
not Git submodules in this repository; the upstream `.gitmodules` file is
therefore omitted. Their upstream URLs are
<https://github.com/cgutman/X1Kit> and
<https://github.com/moonlight-stream/moonlight-common-c>.

## Publication edits

- Removed generated `xcuserdata` and Xcode source-control workspace metadata.
- Removed explicit Xcode development-team settings. Builders choose their own
  signing team and bundle identifier locally.
- Replaced a private host-name comparison with a generic safe-resize bootstrap
  flag. On the configured Duo host this enables the same path; this privacy
  edit means the published source is not byte-for-byte identical to the
  installed, privately signed build 10 IPA. Rebuild and test this source on
  your own device before relying on it.
- Excluded the signed IPA and all provisioning material.

Upstream licenses remain in `LICENSE.txt`, `X1Kit/LICENSE.md`,
`moonlight-common/moonlight-common-c/LICENSE.txt`, and the applicable nested
dependency directories. The original Moonlight README is retained as
`UPSTREAM_README.md`.
