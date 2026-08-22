# Matrix E2EE Storage Review

Draft status: manual security verification required.

Inter Galactic uses Matrix E2EE and local Matrix storage. Public release requires a clear understanding of how session tokens, local databases, and E2EE keys are stored on iOS and other platforms.

## Data To Verify

- Matrix access tokens and refresh tokens;
- Matrix device ID and device display name;
- Olm and Megolm keys;
- cross-signing private material;
- key backup state and recovery data;
- encrypted room cache;
- attachments/media cache;
- local preferences and account registry;
- Spotify tokens if connected.

## iOS Questions

- Which data is in SQLite/Drift app support storage?
- Which data is in Keychain via `flutter_secure_storage`?
- Are local databases protected by iOS Data Protection classes?
- Does iCloud/iTunes backup include session or E2EE data?
- Does app group storage share sensitive data with the broadcast extension?
- Are logs prevented from exporting E2EE material?

## User-Facing Language

Tell users to keep recovery keys safe, use device lock protection, and understand that deleting local keys can make old encrypted messages unrecoverable.

TODO before release: run a focused storage audit against the exact iOS archive and Matrix SDK version.
