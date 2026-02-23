# RSS Reader Cupertino (Android)

A lightweight RSS reader built with Flutter using **Cupertino widgets** (no Material UI in the app code).

## Features

- Cupertino-style interface on Android (no Material UI in app screens)
- RSS and Atom feed support
- In-app article web view
- Saved feeds and recent article history (local persistence)
- Settings page with dark mode toggle
- Pull to refresh

## Local development (when Flutter is available)

This repo starts minimal. If `android/` is missing, generate it once:

```bash
flutter create --platforms=android --org com.example.rssreadercupertino .
flutter pub get
flutter run
```

## CI build

GitHub Actions workflow: `.github/workflows/build-apk.yml`

It installs Flutter, generates Android platform files if needed, and builds a release APK artifact.
