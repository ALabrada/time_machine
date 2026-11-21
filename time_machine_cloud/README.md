# time_machine_cloud

Pure-Dart cloud storage and sync backends for History Lens. It wraps Dropbox,
Google Drive, Nextcloud, Yandex Disk and Supabase behind a common `CloudBase`
interface, so the Flutter app and the proxy server share one implementation.

## Contents

- **Cloud backends** — `DropBoxCloud`, `GoogleDriveCloud`, `NextCloudCloud`,
  `YandexDiskCloud` and `SupabaseCloud`, all built on `FileCloudBase`.
- **OAuth** — authorization-code + PKCE consent and token refresh with
  injectable token stores.
- **Web support** — `BackendProxyCloud` talks to the proxy server instead of
  the providers directly.
- **Sync** — cloud change events and a sync provider for keeping local data in
  step.

## Usage

Add `time_machine_cloud` as a path dependency and import
`package:time_machine_cloud/time_machine_cloud.dart`.

## Additional information

Part of the History Lens monorepo — see the
[GitHub repository](https://github.com/ALabrada/time_machine).
