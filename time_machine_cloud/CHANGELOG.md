## 1.0.0

* Pure-Dart cloud storage and sync backends behind a common `CloudBase`
  interface.
* Dropbox, Google Drive, Nextcloud, Yandex Disk and Supabase implementations
  built on `FileCloudBase`.
* OAuth authorization-code + PKCE consent and token-refresh flows with
  injectable token stores.
* `BackendProxyCloud` for the web build, talking to the proxy server instead of
  the providers directly.
