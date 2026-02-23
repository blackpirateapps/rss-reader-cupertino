# AI Handoff Notes

## Project Summary

This repository contains a Flutter Android RSS reader with a Cupertino-style UI (no Material-themed app screens).

Current major features:
- RSS + Atom feed parsing
- Unread article timeline aggregated across saved feeds
- Feed filters for All / Unread / Read in the Feed tab (Unread default)
- Swipe-to-mark-read on articles
- Native Cupertino article detail preview (single scroll, no embedded reader WebView)
- In-app article web view (`webview_flutter`) for source pages
- Saved feeds, read marks, and recent article history (local persistence via `shared_preferences`)
- Feed URL backup import/export (plain text file, one URL per line)
- Settings page with dark mode toggle
- GitHub Actions workflow that builds a release APK artifact

## Important Constraints

- The local machine used during development did not have Flutter installed, so changes were made without local execution/testing.
- CI (`.github/workflows/build-apk.yml`) is the primary validation path.
- The repo intentionally does not commit the `android/` directory. CI generates it using `flutter create --platforms=android ...`.
- `flutter analyze` is run in CI before the APK build. Treat analyzer warnings/info seriously because CI will stop before build if analysis fails.

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
- Read keys are generated from article link when available; otherwise a fallback key uses source + title + published label

## Feed Tab UX (Current)

The feed tab no longer contains a feed URL input.

Current behavior:
- Feed source is selected/added in the **Library** tab
- Feed tab aggregates unread articles from all saved feeds (or default feed if none are saved)
- Feed fetch currently loops feeds sequentially (not parallel)
- Feed tab shows:
  - Search field (article filtering within the unread aggregate list)
  - Cupertino pill/segmented filters for All / Unread / Read (default Unread)
  - Loaded feed count indicator
  - Refresh and quick-add (`+`) buttons in nav bar
  - Feed header card and article list
  - Swipe gesture (`end-to-start`) on article rows to mark as read
- Aggregated article rows include source feed title (when available)

Search behavior:
- Filters by title, summary, published label, or link (case-insensitive)
- Also matches source feed title
- If no matches are found, feed header remains visible and an in-list “No articles match ...” card is shown
- If all unread items are gone and no search is active, feed tab shows an “All caught up” card

## Library Tab UX (Current)

Saved Feeds section:
- Header action is `Add`
- Add flow uses a Cupertino dialog with URL validation
- Tapping a saved feed selects it and switches to the Feed tab
- Delete button removes a saved feed
- Even though Feed tab is aggregated, selecting a feed still updates `activeFeedUrl` and triggers a refresh (kept for compatibility and future use)

Recent Articles section:
- Shows locally stored history
- Tapping an entry opens the article detail screen
- `Clear` action removes history

Storage / settings behavior:
- Settings page can clear:
  - Saved feeds
  - Recent article history
  - Read article marks

Article reader:
- `ArticleScreen` now uses a native Cupertino scroll view with a single title/header and native text preview of feed content
- “Read Full Story” opens the source URL page in the dedicated browser WebView screen
- Copy link is an icon-only action in the article header card

Feed backup import/export:
- Library tab includes import/export actions for feed URLs
- Backup format is plain text (`.txt`), one feed URL per line
- Import skips invalid/non-URL lines and duplicate URLs already saved

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
- Aggregation attaches source metadata (`sourceTitle`, `sourceUrl`) to each `FeedArticle`

### RSS `pubDate` Type Gotcha

`webfeed_plus` may expose `RssItem.pubDate` as `DateTime` (not `String`) depending on version/runtime.
The code now normalizes with `item.pubDate?.toString()` before storing display text.

### Date Sorting Limitation (Current)

Unread feed sorting uses `_tryParseArticleDate()` with `DateTime.parse(...)`.
- ISO timestamps sort correctly
- Non-ISO RSS pubDate strings may fail parsing and then fall back to title-based ordering

If ordering quality becomes an issue, add a proper RFC822 parser (e.g. `intl` `DateFormat`) and/or store parsed dates in `FeedArticle`.

## Content Sanitization Notes

`_plainText()` strips basic HTML tags and decodes common entities, including quote apostrophe entities such as:
- `&rsquo;`
- `&lsquo;`
- `&#8217;`

Separate from `_plainText()`, article detail rendering uses `_buildArticleHtmlDocument(...)` to wrap feed HTML in a minimal style sheet for readable dark/light rendering and responsive images.

## CI / Analyzer Compatibility Gotchas (Already Addressed)

Several fixes were required due to Flutter stable version differences and analyzer behavior:
- `CupertinoButton.minSize` -> `minimumSize: const Size.square(...)`
- `CupertinoTheme.of(context).brightness` can be nullable on some SDK versions, so code coalesces to `Brightness.light`
- `CupertinoTabBar` cannot be `const` in this code path due to const-eval restrictions on the items list
- `cupertino_icons` dependency is required or icons may appear as missing glyph boxes
- Prefer `RegExp(..., caseSensitive: false)` over inline `(?i)` flags to satisfy Dart analyzer regex validation
- Placeholder `test/widget_test.dart` prevents generated default `MyApp` test analyzer failures after CI runs `flutter create`

## Files Most Likely to Be Edited Next

- `lib/main.dart` (currently contains all app logic/UI)
- `.github/workflows/build-apk.yml` (CI behavior)
- `pubspec.yaml` (dependencies)
- `docs/AI_HANDOFF.md` (keep in sync after feature changes)

## Suggested Future Refactor (Optional)

As features grow, split `lib/main.dart` into:
- `app/` (app shell, theme, state)
- `features/feed/`
- `features/library/`
- `features/settings/`
- `data/` (repository + models)

This would reduce merge conflicts and make future AI edits safer.
