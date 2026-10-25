# Source and install releases

The signed development IPA used during local testing is private. It embeds
provisioning information and is not a durable public installer.

For a source release:

1. Freeze a reviewed source commit and record its full Git SHA. Keep the
   vendored common-c changes and all upstream notices in the tree.
2. Build from a fresh clone on a supported macOS/Xcode installation. Record
   the Xcode version, target iOS version, dependency lockfile revision, and
   build number. Test the resulting app on a device using your own signing.
3. Tag the source commit. Mark the release as a preview if an identified
   regression remains. State exactly what was tested.
4. Only attach a binary if its public safety and installation method have
   been verified. Unsigned output needs an explicit own-signing procedure;
   development provisioning may be device-limited and expire.
5. For every attached asset, compute `shasum -a 256 <asset>` and put the full
   digest and exact filename in the release notes. Re-download the published
   asset and compare its digest before announcing it.

Do not include signing keys, provisioning profiles, certificates, pairing
state, private network details, device identifiers, or local build logs in
source, tags, or release assets.
