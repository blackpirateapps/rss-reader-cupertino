part of rss_reader_cupertino_app;

class FeedRepository {
  static Future<FeedLoadResult> fetch(Uri uri) async {
    final response = await http.get(
      uri,
      headers: const {
        'User-Agent': 'rss-reader-cupertino/0.2 (+flutter)',
        'Accept': 'application/rss+xml, application/atom+xml, application/xml, text/xml;q=0.9, */*;q=0.8',
      },
    );

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('HTTP ${response.statusCode} while loading feed.');
    }

    final body = _decodeHttpResponseBody(response);

    try {
      return _parseRss(body);
    } catch (_) {
      // Fall through to Atom parsing.
    }

    try {
      return _parseAtom(body);
    } catch (_) {
      throw Exception('Failed to parse feed. Supported formats: RSS and Atom.');
    }
  }

  static FeedLoadResult _parseRss(String body) {
    final feed = RssFeed.parse(body);
    final items = feed.items ?? const <RssItem>[];
    final hasMetadata = (feed.title ?? '').trim().isNotEmpty ||
        (feed.description ?? '').trim().isNotEmpty;
    if (items.isEmpty && !hasMetadata) {
      throw Exception('Not an RSS feed.');
    }
    final articles = items
        .map(
          (item) => FeedArticle(
            title: _nonEmpty(item.title, fallback: 'Untitled article'),
            summary: (item.description ?? '').trim(),
            link: (item.link ?? '').trim().isEmpty ? null : item.link!.trim(),
            publishedLabel: _nullIfBlank(item.pubDate?.toString()),
          ),
        )
        .toList();

    return FeedLoadResult(
      title: _nonEmpty(feed.title, fallback: 'RSS Feed'),
      description: _nullIfBlank(feed.description),
      articles: articles,
      feedTypeLabel: 'RSS',
    );
  }

  static FeedLoadResult _parseAtom(String body) {
    final dynamic atom = AtomFeed.parse(body);

    final rawTitle = _dynamicRead(() => atom.title);
    final rawSubtitle = _firstNonNullDynamic([
      () => _dynamicRead(() => atom.subtitle),
      () => _dynamicRead(() => atom.description),
      () => _dynamicRead(() => atom.tagline),
    ]);
    final rawItems = _firstNonNullDynamic([
      () => _dynamicRead(() => atom.items),
      () => _dynamicRead(() => atom.entries),
    ]);

    final items = rawItems is Iterable
        ? rawItems.cast<dynamic>().toList()
        : const <dynamic>[];
    final hasMetadata = (_atomTextToString(rawTitle) ?? '').trim().isNotEmpty ||
        (_atomTextToString(rawSubtitle) ?? '').trim().isNotEmpty;
    if (items.isEmpty && !hasMetadata) {
      throw Exception('Not an Atom feed.');
    }
    final articles = <FeedArticle>[];

    for (final dynamic item in items) {
      final dynamic titleValue = _firstNonNullDynamic([
        () => _dynamicRead(() => item.title),
        () => _dynamicRead(() => item.id),
      ]);
      final dynamic summaryValue = _firstNonNullDynamic([
        () => _dynamicRead(() => item.summary),
        () => _dynamicRead(() => item.content),
        () => _dynamicRead(() => item.description),
      ]);
      final dynamic publishedValue = _firstNonNullDynamic([
        () => _dynamicRead(() => item.published),
        () => _dynamicRead(() => item.updated),
        () => _dynamicRead(() => item.pubDate),
      ]);

      final link = _extractAtomLink(item);
      final title = _nonEmpty(_atomTextToString(titleValue), fallback: 'Untitled article');
      final summary = (_atomTextToString(summaryValue) ?? '').trim();
      final publishedLabel = _nullIfBlank(_atomTextToString(publishedValue));

      articles.add(
        FeedArticle(
          title: title,
          summary: summary,
          link: link,
          publishedLabel: publishedLabel,
        ),
      );
    }

    return FeedLoadResult(
      title: _nonEmpty(_atomTextToString(rawTitle), fallback: 'Atom Feed'),
      description: _nullIfBlank(_atomTextToString(rawSubtitle)),
      articles: articles,
      feedTypeLabel: 'Atom',
    );
  }

  static dynamic _dynamicRead(dynamic Function() getter) {
    try {
      return getter();
    } catch (_) {
      return null;
    }
  }

  static dynamic _firstNonNullDynamic(List<dynamic Function()> readers) {
    for (final read in readers) {
      final value = read();
      if (value != null) return value;
    }
    return null;
  }

  static String? _extractAtomLink(dynamic item) {
    final direct = _nullIfBlank(_atomTextToString(_dynamicRead(() => item.link)));
    if (direct != null) return direct;

    final linksValue = _dynamicRead(() => item.links);
    if (linksValue is Iterable) {
      for (final dynamic linkValue in linksValue) {
        final href = _nullIfBlank(_atomTextToString(_dynamicRead(() => linkValue.href)));
        if (href != null) {
          return href;
        }
      }
    }

    return null;
  }
}

class AppController extends ChangeNotifier {
  AppController._(this._prefs);

  static const _keyDarkMode = 'settings.darkMode';
  static const _keySavedFeeds = 'library.savedFeeds';
  static const _keyArticleHistory = 'library.articleHistory';
  static const _keyReadArticleKeys = 'library.readArticleKeys';
  static const _keyBookmarkedArticles = 'library.bookmarkedArticles';

  final SharedPreferences _prefs;

  bool _isDarkMode = false;
  List<String> _savedFeeds = <String>[];
  List<ArticleHistoryEntry> _articleHistory = <ArticleHistoryEntry>[];
  List<BookmarkedArticleEntry> _bookmarkedArticles = <BookmarkedArticleEntry>[];
  Set<String> _readArticleKeys = <String>{};
  String _activeFeedUrl = '';
  int _feedSelectionTick = 0;

  static Future<AppController> create() async {
    final prefs = await SharedPreferences.getInstance();
    final controller = AppController._(prefs);
    controller._loadFromPrefs();
    return controller;
  }

  bool get isDarkMode => _isDarkMode;
  List<String> get savedFeeds => List.unmodifiable(_savedFeeds);
  List<ArticleHistoryEntry> get articleHistory => List.unmodifiable(_articleHistory);
  List<BookmarkedArticleEntry> get bookmarkedArticles =>
      List.unmodifiable(_bookmarkedArticles);
  int get readArticleCount => _readArticleKeys.length;
  String get activeFeedUrl => _activeFeedUrl;
  int get feedSelectionTick => _feedSelectionTick;

  void _loadFromPrefs() {
    _isDarkMode = _prefs.getBool(_keyDarkMode) ?? false;

    final feeds = _prefs.getStringList(_keySavedFeeds) ?? const <String>[];
    _savedFeeds = feeds.where((value) => value.trim().isNotEmpty).toList();

    final encodedHistory =
        _prefs.getStringList(_keyArticleHistory) ?? const <String>[];
    _articleHistory = encodedHistory
        .map((value) {
          try {
            final decoded = jsonDecode(value);
            if (decoded is Map<String, dynamic>) {
              return ArticleHistoryEntry.fromJson(decoded);
            }
            if (decoded is Map) {
              return ArticleHistoryEntry.fromJson(decoded.cast<String, dynamic>());
            }
          } catch (_) {
            return null;
          }
          return null;
        })
        .whereType<ArticleHistoryEntry>()
        .toList();

    final encodedBookmarks =
        _prefs.getStringList(_keyBookmarkedArticles) ?? const <String>[];
    _bookmarkedArticles = encodedBookmarks
        .map((value) {
          try {
            final decoded = jsonDecode(value);
            if (decoded is Map<String, dynamic>) {
              return BookmarkedArticleEntry.fromJson(decoded);
            }
            if (decoded is Map) {
              return BookmarkedArticleEntry.fromJson(
                decoded.cast<String, dynamic>(),
              );
            }
          } catch (_) {
            return null;
          }
          return null;
        })
        .whereType<BookmarkedArticleEntry>()
        .toList();

    final readKeys = _prefs.getStringList(_keyReadArticleKeys) ?? const <String>[];
    _readArticleKeys = readKeys.where((value) => value.trim().isNotEmpty).toSet();

    if (_savedFeeds.isNotEmpty) {
      _activeFeedUrl = _savedFeeds.first;
    }
  }

  void setDarkMode(bool enabled) {
    if (_isDarkMode == enabled) return;
    _isDarkMode = enabled;
    _prefs.setBool(_keyDarkMode, _isDarkMode);
    notifyListeners();
  }

  void recordFeed(String url) {
    final trimmed = url.trim();
    if (trimmed.isEmpty) return;

    _activeFeedUrl = trimmed;
    _savedFeeds = [
      trimmed,
      for (final existing in _savedFeeds)
        if (existing != trimmed) existing,
    ];
    if (_savedFeeds.length > 20) {
      _savedFeeds = _savedFeeds.take(20).toList();
    }
    _prefs.setStringList(_keySavedFeeds, _savedFeeds);
    notifyListeners();
  }

  void selectFeed(String url) {
    final trimmed = url.trim();
    if (trimmed.isEmpty) return;
    _activeFeedUrl = trimmed;
    _feedSelectionTick += 1;
    recordFeed(trimmed);
  }

  void removeSavedFeed(String url) {
    _savedFeeds = _savedFeeds.where((value) => value != url).toList();
    if (_activeFeedUrl == url) {
      _activeFeedUrl = _savedFeeds.isEmpty ? '' : _savedFeeds.first;
      _feedSelectionTick += 1;
    }
    _prefs.setStringList(_keySavedFeeds, _savedFeeds);
    notifyListeners();
  }

  void clearSavedFeeds() {
    _savedFeeds = <String>[];
    _activeFeedUrl = '';
    _feedSelectionTick += 1;
    _prefs.setStringList(_keySavedFeeds, _savedFeeds);
    notifyListeners();
  }

  FeedImportResult importFeedsFromText(String rawText) {
    final lines = const LineSplitter().convert(rawText);
    final existing = _savedFeeds.toSet();
    final imported = <String>[];
    final seenInFile = <String>{};
    var invalidLineCount = 0;
    var duplicateLineCount = 0;

    for (final line in lines) {
      final normalized = _normalizedFeedUrl(line);
      if (normalized == null) {
        if (line.trim().isNotEmpty) {
          invalidLineCount += 1;
        }
        continue;
      }
      if (!seenInFile.add(normalized) || existing.contains(normalized)) {
        duplicateLineCount += 1;
        continue;
      }
      imported.add(normalized);
    }

    if (imported.isEmpty) {
      return FeedImportResult(
        totalLineCount: lines.length,
        importedCount: 0,
        invalidLineCount: invalidLineCount,
        duplicateLineCount: duplicateLineCount,
      );
    }

    _savedFeeds = [
      ...imported,
      ..._savedFeeds,
    ];
    if (_savedFeeds.length > 20) {
      _savedFeeds = _savedFeeds.take(20).toList();
    }
    _activeFeedUrl = _savedFeeds.first;
    _feedSelectionTick += 1;
    _prefs.setStringList(_keySavedFeeds, _savedFeeds);
    notifyListeners();

    final actualImportedCount =
        imported.where((url) => _savedFeeds.contains(url)).length;
    return FeedImportResult(
      totalLineCount: lines.length,
      importedCount: actualImportedCount,
      invalidLineCount: invalidLineCount,
      duplicateLineCount: duplicateLineCount,
    );
  }

  String exportFeedsAsText() => _savedFeeds.join('\n');

  void recordArticle(ArticleHistoryEntry entry) {
    _articleHistory = [
      entry,
      for (final existing in _articleHistory)
        if (!_sameArticle(entry, existing)) existing,
    ];
    if (_articleHistory.length > 50) {
      _articleHistory = _articleHistory.take(50).toList();
    }
    _persistArticleHistory();
    notifyListeners();
  }

  void clearArticleHistory() {
    _articleHistory = <ArticleHistoryEntry>[];
    _persistArticleHistory();
    notifyListeners();
  }

  bool isArticleBookmarked(FeedArticle article) {
    final key = _articleBookmarkKey(article);
    return _bookmarkedArticles.any((entry) => entry.bookmarkKey == key);
  }

  void toggleArticleBookmark(FeedArticle article) {
    final key = _articleBookmarkKey(article);
    final existingIndex =
        _bookmarkedArticles.indexWhere((entry) => entry.bookmarkKey == key);
    if (existingIndex >= 0) {
      _bookmarkedArticles = [
        for (var i = 0; i < _bookmarkedArticles.length; i++)
          if (i != existingIndex) _bookmarkedArticles[i],
      ];
    } else {
      final entry = BookmarkedArticleEntry.fromFeedArticle(article);
      _bookmarkedArticles = [
        entry,
        for (final existing in _bookmarkedArticles)
          if (existing.bookmarkKey != entry.bookmarkKey) existing,
      ];
      if (_bookmarkedArticles.length > 200) {
        _bookmarkedArticles = _bookmarkedArticles.take(200).toList();
      }
    }
    _persistBookmarkedArticles();
    notifyListeners();
  }

  void removeBookmarkedArticle(String bookmarkKey) {
    final next = _bookmarkedArticles
        .where((entry) => entry.bookmarkKey != bookmarkKey)
        .toList();
    if (next.length == _bookmarkedArticles.length) return;
    _bookmarkedArticles = next;
    _persistBookmarkedArticles();
    notifyListeners();
  }

  void clearBookmarkedArticles() {
    if (_bookmarkedArticles.isEmpty) return;
    _bookmarkedArticles = <BookmarkedArticleEntry>[];
    _persistBookmarkedArticles();
    notifyListeners();
  }

  bool isArticleRead(String articleKey) => _readArticleKeys.contains(articleKey);

  void markArticleRead(String articleKey) {
    if (articleKey.trim().isEmpty) return;
    final added = _readArticleKeys.add(articleKey);
    if (!added) return;
    if (_readArticleKeys.length > 2000) {
      final trimmed = _readArticleKeys.toList().reversed.take(1500).toSet();
      _readArticleKeys = trimmed;
    }
    _persistReadArticleKeys();
    notifyListeners();
  }

  void clearReadArticles() {
    if (_readArticleKeys.isEmpty) return;
    _readArticleKeys = <String>{};
    _persistReadArticleKeys();
    notifyListeners();
  }

  bool _sameArticle(ArticleHistoryEntry a, ArticleHistoryEntry b) {
    if ((a.link ?? '').isNotEmpty && (b.link ?? '').isNotEmpty) {
      return a.link == b.link;
    }
    return a.title == b.title && a.feedTitle == b.feedTitle;
  }

  void _persistArticleHistory() {
    final encoded = _articleHistory
        .map((entry) => jsonEncode(entry.toJson()))
        .toList();
    _prefs.setStringList(_keyArticleHistory, encoded);
  }

  void _persistReadArticleKeys() {
    _prefs.setStringList(_keyReadArticleKeys, _readArticleKeys.toList());
  }

  void _persistBookmarkedArticles() {
    final encoded = _bookmarkedArticles
        .map((entry) => jsonEncode(entry.toJson()))
        .toList();
    _prefs.setStringList(_keyBookmarkedArticles, encoded);
  }
}

class FeedImportResult {
  const FeedImportResult({
    required this.totalLineCount,
    required this.importedCount,
    required this.invalidLineCount,
    required this.duplicateLineCount,
  });

  final int totalLineCount;
  final int importedCount;
  final int invalidLineCount;
  final int duplicateLineCount;

  String get summaryMessage {
    final parts = <String>[
      'Imported $importedCount feed URL${importedCount == 1 ? '' : 's'}.',
    ];
    if (duplicateLineCount > 0) {
      parts.add('Skipped $duplicateLineCount duplicate line${duplicateLineCount == 1 ? '' : 's'}.');
    }
    if (invalidLineCount > 0) {
      parts.add('Skipped $invalidLineCount invalid line${invalidLineCount == 1 ? '' : 's'}.');
    }
    if (totalLineCount == 0) {
      parts.add('File was empty.');
    }
    return parts.join(' ');
  }
}

class AppScope extends InheritedNotifier<AppController> {
  const AppScope({
    super.key,
    required AppController controller,
    required super.child,
  }) : super(notifier: controller);

  static AppController of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<AppScope>();
    if (scope == null || scope.notifier == null) {
      throw StateError('AppScope not found in widget tree.');
    }
    return scope.notifier!;
  }
}

class FeedLoadResult {
  const FeedLoadResult({
    required this.title,
    required this.description,
    required this.articles,
    required this.feedTypeLabel,
  });

  final String title;
  final String? description;
  final List<FeedArticle> articles;
  final String feedTypeLabel;
}

class FeedArticle {
  const FeedArticle({
    required this.title,
    required this.summary,
    required this.link,
    required this.publishedLabel,
    this.sourceTitle,
    this.sourceUrl,
  });

  final String title;
  final String summary;
  final String? link;
  final String? publishedLabel;
  final String? sourceTitle;
  final String? sourceUrl;

  FeedArticle copyWith({
    String? title,
    String? summary,
    String? link,
    String? publishedLabel,
    String? sourceTitle,
    String? sourceUrl,
  }) {
    return FeedArticle(
      title: title ?? this.title,
      summary: summary ?? this.summary,
      link: link ?? this.link,
      publishedLabel: publishedLabel ?? this.publishedLabel,
      sourceTitle: sourceTitle ?? this.sourceTitle,
      sourceUrl: sourceUrl ?? this.sourceUrl,
    );
  }
}

class ArticleHistoryEntry {
  const ArticleHistoryEntry({
    required this.title,
    required this.link,
    required this.summary,
    required this.publishedLabel,
    required this.feedTitle,
    required this.openedAt,
  });

  final String title;
  final String? link;
  final String summary;
  final String? publishedLabel;
  final String? feedTitle;
  final DateTime openedAt;

  Map<String, dynamic> toJson() {
    return {
      'title': title,
      'link': link,
      'summary': summary,
      'publishedLabel': publishedLabel,
      'feedTitle': feedTitle,
      'openedAt': openedAt.toIso8601String(),
    };
  }

  static ArticleHistoryEntry fromJson(Map<String, dynamic> json) {
    DateTime parsed;
    try {
      parsed = DateTime.parse((json['openedAt'] ?? '').toString());
    } catch (_) {
      parsed = DateTime.now();
    }

    return ArticleHistoryEntry(
      title: _nonEmpty(json['title']?.toString(), fallback: 'Untitled article'),
      link: _nullIfBlank(json['link']?.toString()),
      summary: (json['summary'] ?? '').toString(),
      publishedLabel: _nullIfBlank(json['publishedLabel']?.toString()),
      feedTitle: _nullIfBlank(json['feedTitle']?.toString()),
      openedAt: parsed,
    );
  }

  FeedArticle toFeedArticle() {
    return FeedArticle(
      title: title,
      summary: summary,
      link: link,
      publishedLabel: publishedLabel,
      sourceTitle: feedTitle,
    );
  }
}

class BookmarkedArticleEntry {
  const BookmarkedArticleEntry({
    required this.bookmarkKey,
    required this.title,
    required this.link,
    required this.summary,
    required this.publishedLabel,
    required this.feedTitle,
    required this.sourceUrl,
    required this.savedAt,
  });

  final String bookmarkKey;
  final String title;
  final String? link;
  final String summary;
  final String? publishedLabel;
  final String? feedTitle;
  final String? sourceUrl;
  final DateTime savedAt;

  factory BookmarkedArticleEntry.fromFeedArticle(FeedArticle article) {
    return BookmarkedArticleEntry(
      bookmarkKey: _articleBookmarkKey(article),
      title: article.title,
      link: article.link,
      summary: article.summary,
      publishedLabel: article.publishedLabel,
      feedTitle: article.sourceTitle,
      sourceUrl: article.sourceUrl,
      savedAt: DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'bookmarkKey': bookmarkKey,
      'title': title,
      'link': link,
      'summary': summary,
      'publishedLabel': publishedLabel,
      'feedTitle': feedTitle,
      'sourceUrl': sourceUrl,
      'savedAt': savedAt.toIso8601String(),
    };
  }

  static BookmarkedArticleEntry fromJson(Map<String, dynamic> json) {
    DateTime parsed;
    try {
      parsed = DateTime.parse((json['savedAt'] ?? '').toString());
    } catch (_) {
      parsed = DateTime.now();
    }
    final article = FeedArticle(
      title: _nonEmpty(json['title']?.toString(), fallback: 'Untitled article'),
      summary: (json['summary'] ?? '').toString(),
      link: _nullIfBlank(json['link']?.toString()),
      publishedLabel: _nullIfBlank(json['publishedLabel']?.toString()),
      sourceTitle: _nullIfBlank(json['feedTitle']?.toString()),
      sourceUrl: _nullIfBlank(json['sourceUrl']?.toString()),
    );
    return BookmarkedArticleEntry(
      bookmarkKey: _nullIfBlank(json['bookmarkKey']?.toString()) ??
          _articleBookmarkKey(article),
      title: article.title,
      link: article.link,
      summary: article.summary,
      publishedLabel: article.publishedLabel,
      feedTitle: article.sourceTitle,
      sourceUrl: article.sourceUrl,
      savedAt: parsed,
    );
  }

  FeedArticle toFeedArticle() {
    return FeedArticle(
      title: title,
      summary: summary,
      link: link,
      publishedLabel: publishedLabel,
      sourceTitle: feedTitle,
      sourceUrl: sourceUrl,
    );
  }
}
