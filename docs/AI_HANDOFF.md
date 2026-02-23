# AI Handoff Notes

## Project Summary

This repository contains a Flutter Android RSS reader with a Cupertino-style UI (no Material-themed app screens).

Current major features:
- RSS + Atom feed parsing
- Unread article timeline aggregated across saved feeds
- Swipe-to-mark-read on articles
- Formatted article reader (HTML/images rendered via embedded WebView)
- In-app article web view (`webview_flutter`) for source pages
- Saved feeds, read marks, and recent article history (local persistence via `shared_preferences`)
- Settings page with dark mode toggle
- GitHub Actions workflow that builds a release APK artifact

## Important Constraints

- The local machine used during development did not have Flutter installed, so changes were made without local execution/testing.
- CI (`.github/workflows/build-apk.yml`) is the primary validation path.
- The repo intentionally does not commit the `android/` directory. CI generates it using `flutter create --platforms=android ...`.

## CI / Build Workflow (Key Behavior)

Workflow file: `.github/workflows/build-apk.yml`

What it does:
1. Checks out code
2. Sets up Java 17
3. Sets up Flutter stable
4. Generates `android/` if missing (`flutter create --platforms=android ...`)
5. Ensures Android `INTERNET` permission in generated manifest
6. Runs `flutter pub get`
7. Runs `flutter analyze`
8. Builds release APK
9. Uploads APK artifact

### Why `test/widget_test.dart` exists

`flutter create .` can introduce a default widget test referencing `MyApp`, which does not exist in this app. A placeholder `test/widget_test.dart` was added to prevent analyzer failures in CI.

## App Architecture Overview

Main file: `lib/main.dart`

High-level structure:
- `main()` initializes `SharedPreferences` via `AppController.create()`
- `RssReaderApp` wraps the app in `AppScope` (an `InheritedNotifier`) and builds `CupertinoApp`
- `HomeShell` uses `CupertinoTabScaffold` with tabs:
  - Feed
  - Library
  - Settings

### State / Persistence (`AppController`)

`AppController` handles app-level state and persistence:
- Dark mode setting (`settings.darkMode`)
- Saved feeds list (`library.savedFeeds`)
- Recent article history (`library.articleHistory`)
- Read article keys (`library.readArticleKeys`)
- Active feed URL and a `feedSelectionTick` counter to notify Feed tab when selection changes

Feed list behavior:
- `recordFeed(url)` saves/reorders feed URLs (deduplicated, capped)
- `selectFeed(url)` sets active feed and increments `feedSelectionTick`

Article history behavior:
- Records opened articles with title/link/summary/feed title/opened timestamp
- Deduplicates by link when available

Read/unread behavior:
- Feed tab hides articles whose read key is present in `readArticleKeys`
- Swiping an article row marks it as read
- Settings page includes a way to clear read marks

## Feed Tab UX (Current)

The feed tab no longer contains a feed URL input.

Current behavior:
- Feed source is selected/added in the **Library** tab
- Feed tab aggregates unread articles from all saved feeds (or default feed if none are saved)
- Feed tab shows:
  - Search field (article filtering within the unread aggregate list)
  - Loaded feed count indicator
  - Refresh button in nav bar
  - Feed header card and article list
  - Swipe gesture (`end-to-start`) on article rows to mark as read

Search behavior:
- Filters by title, summary, published label, or link (case-insensitive)
- Also matches source feed title
- If no matches are found, feed header remains visible and an in-list “No articles match ...” card is shown

## Library Tab UX (Current)

Saved Feeds section:
- Header action is `Add`
- Add flow uses a Cupertino dialog with URL validation
- Tapping a saved feed selects it and switches to the Feed tab
- Delete button removes a saved feed

Recent Articles section:
- Shows locally stored history
- Tapping an entry opens the article detail screen
- `Clear` action removes history

Article reader:
- `ArticleScreen` now renders feed-provided HTML content in an embedded WebView so formatting/images can display
- “Open In App” still opens the source URL page in the dedicated browser WebView screen

## Design / Theming Notes

- App uses `CupertinoThemeData` and dynamic colors; no Material-themed UI screens/components are used for the app UX.
- `cupertino_icons` dependency was added to fix missing icon glyphs (boxes/squares appearing instead of icons).
- Several text styles now resolve dynamic colors explicitly using helper functions to improve readability in dark mode:
  - `_labelColor(context)`
  - `_secondaryLabelColor(context)`

## Parsing Notes

`FeedRepository`:
- Tries RSS parsing first (`RssFeed.parse`)
- Falls back to Atom parsing (`AtomFeed.parse`) using defensive dynamic access
- Atom parsing is intentionally tolerant because `webfeed_plus` Atom models vary between versions

### RSS `pubDate` Type Gotcha

`webfeed_plus` may expose `RssItem.pubDate` as `DateTime` (not `String`) depending on version/runtime.
The code now normalizes with `item.pubDate?.toString()` before storing display text.

## Content Sanitization Notes

`_plainText()` strips basic HTML tags and decodes common entities, including quote apostrophe entities such as:
- `&rsquo;`
- `&lsquo;`
- `&#8217;`

## Files Most Likely to Be Edited Next

- `lib/main.dart` (currently contains all app logic/UI)
- `.github/workflows/build-apk.yml` (CI behavior)
- `pubspec.yaml` (dependencies)

## Suggested Future Refactor (Optional)

As features grow, split `lib/main.dart` into:
- `app/` (app shell, theme, state)
- `features/feed/`
- `features/library/`
- `features/settings/`
- `data/` (repository + models)

This would reduce merge conflicts and make future AI edits safer.
