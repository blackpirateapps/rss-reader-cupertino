# RSS Reader Cupertino (Android)

A lightweight RSS reader built with Flutter using **Cupertino widgets** (no Material UI in the app code).

## Features

- Cupertino-style interface on Android
- Paste any RSS feed URL and load articles
- Pull to refresh
- Article detail view with link copy action

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
