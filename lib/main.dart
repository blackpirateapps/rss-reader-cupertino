import 'dart:convert';

import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:webfeed_plus/webfeed_plus.dart';
import 'package:webview_flutter/webview_flutter.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final controller = await AppController.create();
  runApp(RssReaderApp(controller: controller));
}

class RssReaderApp extends StatelessWidget {
  const RssReaderApp({super.key, required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        return AppScope(
          controller: controller,
          child: CupertinoApp(
            title: 'RSS Reader',
            debugShowCheckedModeBanner: false,
            theme: CupertinoThemeData(
              brightness: controller.isDarkMode ? Brightness.dark : Brightness.light,
              primaryColor: CupertinoColors.activeBlue,
              scaffoldBackgroundColor: controller.isDarkMode
                  ? const Color(0xFF000000)
                  : const Color(0xFFF2F2F7),
              barBackgroundColor: controller.isDarkMode
                  ? const Color(0xFF111111)
                  : CupertinoColors.systemBackground,
            ),
            home: const HomeShell(),
          ),
        );
      },
    );
  }
}

class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  late final CupertinoTabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = CupertinoTabController(initialIndex: 0);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = AppScope.of(context);

    return CupertinoTabScaffold(
      controller: _tabController,
      tabBar: CupertinoTabBar(
        items: [
          BottomNavigationBarItem(
            icon: Icon(CupertinoIcons.list_bullet),
            label: 'Feed',
          ),
          BottomNavigationBarItem(
            icon: Icon(CupertinoIcons.book),
            label: 'Library',
          ),
          BottomNavigationBarItem(
            icon: Icon(CupertinoIcons.settings),
            label: 'Settings',
          ),
        ],
      ),
      tabBuilder: (context, index) {
        if (index == 0) {
          return CupertinoTabView(
            builder: (_) => FeedScreen(controller: controller),
          );
        }
        if (index == 1) {
          return CupertinoTabView(
            builder: (_) => LibraryScreen(
              controller: controller,
              onOpenFeed: (url) {
                controller.selectFeed(url);
                _tabController.index = 0;
              },
            ),
          );
        }
        return CupertinoTabView(
          builder: (_) => SettingsScreen(controller: controller),
        );
      },
    );
  }
}

class FeedScreen extends StatefulWidget {
  const FeedScreen({super.key, required this.controller});

  final AppController controller;

  @override
  State<FeedScreen> createState() => _FeedScreenState();
}

class _FeedScreenState extends State<FeedScreen> {
  static const _defaultFeed = 'https://hnrss.org/frontpage';

  final TextEditingController _searchController = TextEditingController();

  bool _isLoading = false;
  String? _error;
  FeedLoadResult? _feed;
  DateTime? _lastLoadedAt;
  int _seenFeedSelectionTick = 0;
  String _currentFeedUrl = _defaultFeed;
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _currentFeedUrl = widget.controller.activeFeedUrl.isEmpty
        ? _defaultFeed
        : widget.controller.activeFeedUrl;
    _seenFeedSelectionTick = widget.controller.feedSelectionTick;
    widget.controller.addListener(_handleControllerChange);
    _loadFeed();
  }

  @override
  void didUpdateWidget(covariant FeedScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_handleControllerChange);
      _seenFeedSelectionTick = widget.controller.feedSelectionTick;
      widget.controller.addListener(_handleControllerChange);
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_handleControllerChange);
    _searchController.dispose();
    super.dispose();
  }

  void _handleControllerChange() {
    if (!mounted) return;
    final hasFeedSelectionChange =
        _seenFeedSelectionTick != widget.controller.feedSelectionTick;

    if (!hasFeedSelectionChange) {
      setState(() {});
      return;
    }

    _seenFeedSelectionTick = widget.controller.feedSelectionTick;
    final nextUrl = widget.controller.activeFeedUrl;
    if (nextUrl.isEmpty) {
      setState(() {});
      return;
    }

    _currentFeedUrl = nextUrl;
    _loadFeed();
  }

  Future<void> _loadFeed() async {
    final rawUrl = _currentFeedUrl.trim();
    if (rawUrl.isEmpty) {
      setState(() {
        _error = 'Add an RSS or Atom feed URL in Library.';
      });
      return;
    }

    final uri = Uri.tryParse(rawUrl);
    if (uri == null || !uri.hasScheme) {
      setState(() {
        _error = 'Invalid URL.';
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final result = await FeedRepository.fetch(uri);
      widget.controller.recordFeed(uri.toString());
      if (!mounted) return;
      setState(() {
        _currentFeedUrl = uri.toString();
        _feed = result;
        _lastLoadedAt = DateTime.now();
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString().replaceFirst('Exception: ', '');
      });
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  void _openArticle(FeedArticle article) {
    widget.controller.recordArticle(
      ArticleHistoryEntry(
        title: article.title,
        link: article.link,
        summary: article.summary,
        publishedLabel: article.publishedLabel,
        feedTitle: _feed?.title,
        openedAt: DateTime.now(),
      ),
    );

    Navigator.of(context).push(
      CupertinoPageRoute<void>(
        builder: (_) => ArticleScreen(article: article),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return CupertinoPageScaffold(
      navigationBar: CupertinoNavigationBar(
        middle: const Text('RSS Reader'),
        trailing: CupertinoButton(
          padding: EdgeInsets.zero,
          minimumSize: const Size.square(28),
          onPressed: _isLoading ? null : _loadFeed,
          child: _isLoading
              ? const CupertinoActivityIndicator(radius: 8)
              : const Icon(CupertinoIcons.refresh),
        ),
      ),
      child: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 6),
              child: CupertinoSearchTextField(
                controller: _searchController,
                placeholder: 'Search articles in current feed',
                onChanged: (value) {
                  setState(() {
                    _searchQuery = value;
                  });
                },
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
              child: Row(
                children: [
                  const Icon(
                    CupertinoIcons.link,
                    size: 14,
                    color: CupertinoColors.systemGrey,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      _currentFeedUrl.isEmpty
                          ? 'No feed selected. Add one in Library.'
                          : _hostOnly(_currentFeedUrl),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        color: _secondaryLabelColor(context),
                      ),
                    ),
                  ),
                  if (_searchQuery.trim().isNotEmpty)
                    Text(
                      '${_filteredArticles(_feed?.articles ?? const <FeedArticle>[]).length} matches',
                      style: TextStyle(
                        fontSize: 12,
                        color: _secondaryLabelColor(context),
                      ),
                    ),
                ],
              ),
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: CupertinoColors.systemRed.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: CupertinoColors.systemRed.withValues(alpha: 0.25),
                    ),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(10),
                    child: Row(
                      children: [
                        const Icon(
                          CupertinoIcons.exclamationmark_triangle,
                          color: CupertinoColors.systemRed,
                          size: 18,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            _error!,
                            style: const TextStyle(
                              color: CupertinoColors.systemRed,
                              fontSize: 13,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            Expanded(child: _buildFeedBody()),
          ],
        ),
      ),
    );
  }

  Widget _buildFeedBody() {
    final allArticles = _feed?.articles ?? const <FeedArticle>[];
    final articles = _filteredArticles(allArticles);

    if (_isLoading && allArticles.isEmpty) {
      return const Center(child: CupertinoActivityIndicator(radius: 14));
    }

    if (allArticles.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            'No articles yet. Add a feed URL in Library and open it.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: _secondaryLabelColor(context),
              fontSize: 15,
            ),
          ),
        ),
      );
    }

    return CustomScrollView(
      physics: const BouncingScrollPhysics(
        parent: AlwaysScrollableScrollPhysics(),
      ),
      slivers: [
        CupertinoSliverRefreshControl(onRefresh: _loadFeed),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 4, 12, 10),
            child: _FeedHeaderCard(
              title: _feed?.title ?? 'Feed',
              subtitle: _feed?.description,
              itemCount: articles.length,
              lastLoadedAt: _lastLoadedAt,
              feedTypeLabel: _feed?.feedTypeLabel ?? 'Feed',
            ),
          ),
        ),
        if (articles.isEmpty)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 20),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: _cardColor(context),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: _borderColor(context)),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Text(
                    'No articles match "${_searchQuery.trim()}".',
                    style: TextStyle(
                      fontSize: 14,
                      color: _secondaryLabelColor(context),
                    ),
                  ),
                ),
              ),
            ),
          ),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 16),
          sliver: SliverList(
            delegate: SliverChildBuilderDelegate(
              (context, index) {
                final article = articles[index];
                return Padding(
                  padding:
                      EdgeInsets.only(bottom: index == articles.length - 1 ? 0 : 8),
                  child: _ArticleTile(
                    article: article,
                    onTap: () => _openArticle(article),
                  ),
                );
              },
              childCount: articles.length,
            ),
          ),
        ),
      ],
    );
  }

  List<FeedArticle> _filteredArticles(List<FeedArticle> articles) {
    final query = _searchQuery.trim().toLowerCase();
    if (query.isEmpty) return articles;
    return articles.where((article) => _matchesSearchQuery(article, query)).toList();
  }

  bool _matchesSearchQuery(FeedArticle article, String query) {
    final haystacks = <String>[
      article.title,
      article.summary,
      article.publishedLabel ?? '',
      article.link ?? '',
    ];
    for (final value in haystacks) {
      if (value.toLowerCase().contains(query)) {
        return true;
      }
    }
    return false;
  }
}

class LibraryScreen extends StatelessWidget {
  const LibraryScreen({
    super.key,
    required this.controller,
    required this.onOpenFeed,
  });

  final AppController controller;
  final ValueChanged<String> onOpenFeed;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        return CupertinoPageScaffold(
          navigationBar: const CupertinoNavigationBar(
            middle: Text('Library'),
          ),
          child: SafeArea(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
              children: [
                _SectionCard(
                  title: 'Saved Feeds',
                  actionLabel: 'Add',
                  onAction: () => _showAddFeedDialog(context),
                  child: controller.savedFeeds.isEmpty
                      ? const _EmptySectionMessage(
                          message: 'No feeds saved yet. Tap Add to save a feed URL.',
                        )
                      : Column(
                          children: [
                            for (var i = 0; i < controller.savedFeeds.length; i++)
                              _LibraryRow(
                                title: _hostOnly(controller.savedFeeds[i]),
                                subtitle: controller.savedFeeds[i],
                                onTap: () => onOpenFeed(controller.savedFeeds[i]),
                                trailing: CupertinoButton(
                                  padding: EdgeInsets.zero,
                                  minimumSize: const Size.square(28),
                                  onPressed: () =>
                                      controller.removeSavedFeed(controller.savedFeeds[i]),
                                  child: const Icon(
                                    CupertinoIcons.delete,
                                    color: CupertinoColors.systemRed,
                                    size: 18,
                                  ),
                                ),
                                isLast: i == controller.savedFeeds.length - 1,
                              ),
                          ],
                        ),
                ),
                const SizedBox(height: 12),
                _SectionCard(
                  title: 'Recent Articles',
                  actionLabel:
                      controller.articleHistory.isEmpty ? null : 'Clear',
                  onAction: controller.articleHistory.isEmpty
                      ? null
                      : () => _confirm(
                            context,
                            title: 'Clear History',
                            message: 'Remove recent article history?',
                            confirmLabel: 'Clear',
                            onConfirm: controller.clearArticleHistory,
                          ),
                  child: controller.articleHistory.isEmpty
                      ? const _EmptySectionMessage(
                          message: 'Opened articles will be saved locally here.',
                        )
                      : Column(
                          children: [
                            for (var i = 0; i < controller.articleHistory.length; i++)
                              _LibraryRow(
                                title: controller.articleHistory[i].title,
                                subtitle: _historySubtitle(controller.articleHistory[i]),
                                onTap: () {
                                  final entry = controller.articleHistory[i];
                                  Navigator.of(context).push(
                                    CupertinoPageRoute<void>(
                                      builder: (_) => ArticleScreen(
                                        article: entry.toFeedArticle(),
                                      ),
                                    ),
                                  );
                                },
                                trailing: controller.articleHistory[i].link == null ||
                                        controller.articleHistory[i].link!.isEmpty
                                    ? null
                                    : const Icon(
                                        CupertinoIcons.globe,
                                        size: 18,
                                        color: CupertinoColors.systemGrey,
                                      ),
                                isLast: i == controller.articleHistory.length - 1,
                              ),
                          ],
                        ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _showAddFeedDialog(BuildContext context) {
    final textController = TextEditingController(text: 'https://');
    showCupertinoDialog<void>(
      context: context,
      builder: (dialogContext) => CupertinoAlertDialog(
        title: const Text('Add Feed URL'),
        content: Padding(
          padding: const EdgeInsets.only(top: 12),
          child: CupertinoTextField(
            controller: textController,
            keyboardType: TextInputType.url,
            placeholder: 'https://example.com/feed.xml',
            autofocus: true,
          ),
        ),
        actions: [
          CupertinoDialogAction(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Cancel'),
          ),
          CupertinoDialogAction(
            onPressed: () {
              final raw = textController.text.trim();
              final uri = Uri.tryParse(raw);
              final isValid = uri != null && uri.hasScheme && uri.host.isNotEmpty;
              if (!isValid) {
                Navigator.of(dialogContext).pop();
                _showInfoDialog(
                  context,
                  title: 'Invalid URL',
                  message: 'Enter a valid feed URL (for example: https://site.com/feed.xml).',
                );
                return;
              }

              Navigator.of(dialogContext).pop();
              onOpenFeed(uri.toString());
            },
            child: const Text('Add'),
          ),
        ],
      ),
    );
  }

  String _historySubtitle(ArticleHistoryEntry entry) {
    final parts = <String>[];
    if (entry.feedTitle != null && entry.feedTitle!.trim().isNotEmpty) {
      parts.add(entry.feedTitle!.trim());
    }
    parts.add(_formatDateTime(entry.openedAt));
    return parts.join('  |  ');
  }

  void _confirm(
    BuildContext context, {
    required String title,
    required String message,
    required String confirmLabel,
    required VoidCallback onConfirm,
  }) {
    showCupertinoDialog<void>(
      context: context,
      builder: (dialogContext) => CupertinoAlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          CupertinoDialogAction(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Cancel'),
          ),
          CupertinoDialogAction(
            isDestructiveAction: true,
            onPressed: () {
              Navigator.of(dialogContext).pop();
              onConfirm();
            },
            child: Text(confirmLabel),
          ),
        ],
      ),
    );
  }

  void _showInfoDialog(
    BuildContext context, {
    required String title,
    required String message,
  }) {
    showCupertinoDialog<void>(
      context: context,
      builder: (dialogContext) => CupertinoAlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          CupertinoDialogAction(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }
}

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key, required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        return CupertinoPageScaffold(
          navigationBar: const CupertinoNavigationBar(
            middle: Text('Settings'),
          ),
          child: SafeArea(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
              children: [
                _SectionCard(
                  title: 'Appearance',
                  child: _LibraryRow(
                    title: 'Dark Mode',
                    subtitle: controller.isDarkMode
                        ? 'Use dark Cupertino colors'
                        : 'Use light Cupertino colors',
                    onTap: () => controller.setDarkMode(!controller.isDarkMode),
                    trailing: CupertinoSwitch(
                      value: controller.isDarkMode,
                      onChanged: controller.setDarkMode,
                    ),
                    isLast: true,
                  ),
                ),
                const SizedBox(height: 12),
                _SectionCard(
                  title: 'Storage',
                  child: Column(
                    children: [
                      _LibraryRow(
                        title: 'Saved Feeds',
                        subtitle: '${controller.savedFeeds.length} stored locally',
                        onTap: controller.savedFeeds.isEmpty
                            ? null
                            : controller.clearSavedFeeds,
                        trailing: controller.savedFeeds.isEmpty
                            ? null
                            : const Icon(
                                CupertinoIcons.delete,
                                color: CupertinoColors.systemRed,
                                size: 18,
                              ),
                        isLast: false,
                      ),
                      _LibraryRow(
                        title: 'Recent Article History',
                        subtitle:
                            '${controller.articleHistory.length} entries stored locally',
                        onTap: controller.articleHistory.isEmpty
                            ? null
                            : controller.clearArticleHistory,
                        trailing: controller.articleHistory.isEmpty
                            ? null
                            : const Icon(
                                CupertinoIcons.delete,
                                color: CupertinoColors.systemRed,
                                size: 18,
                              ),
                        isLast: true,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                _SectionCard(
                  title: 'About',
                  child: Column(
                    children: const [
                      _StaticInfoRow(
                        label: 'UI',
                        value: 'Cupertino only',
                        isLast: false,
                      ),
                      _StaticInfoRow(
                        label: 'Feeds',
                        value: 'RSS + Atom',
                        isLast: false,
                      ),
                      _StaticInfoRow(
                        label: 'Article View',
                        value: 'In-app WebView',
                        isLast: true,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class ArticleScreen extends StatelessWidget {
  const ArticleScreen({super.key, required this.article});

  final FeedArticle article;

  @override
  Widget build(BuildContext context) {
    return CupertinoPageScaffold(
      navigationBar: CupertinoNavigationBar(
        middle: Text(
          article.title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ),
      child: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text(
              article.title,
              style: const TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.w700,
              ),
            ),
            if (article.publishedLabel != null && article.publishedLabel!.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                article.publishedLabel!,
                style: TextStyle(
                  fontSize: 13,
                  color: _secondaryLabelColor(context),
                ),
              ),
            ],
            if (article.link != null && article.link!.isNotEmpty) ...[
              const SizedBox(height: 12),
              DecoratedBox(
                decoration: BoxDecoration(
                  color: _cardColor(context),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Link',
                        style: TextStyle(
                          fontSize: 12,
                          color: _secondaryLabelColor(context),
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        article.link!,
                        style: const TextStyle(fontSize: 13),
                      ),
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          CupertinoButton(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 8,
                            ),
                            color: CupertinoColors.activeBlue,
                            borderRadius: BorderRadius.circular(10),
                            onPressed: () {
                              final uri = Uri.tryParse(article.link!);
                              if (uri == null) return;
                              Navigator.of(context).push(
                                CupertinoPageRoute<void>(
                                  builder: (_) => ArticleWebViewScreen(
                                    title: article.title,
                                    uri: uri,
                                  ),
                                ),
                              );
                            },
                            child: const Text('Open In App'),
                          ),
                          CupertinoButton(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 8,
                            ),
                            color: _secondaryButtonColor(context),
                            borderRadius: BorderRadius.circular(10),
                            onPressed: () {
                              Clipboard.setData(ClipboardData(text: article.link!));
                              showCupertinoDialog<void>(
                                context: context,
                                builder: (dialogContext) => CupertinoAlertDialog(
                                  title: const Text('Copied'),
                                  content: const Text(
                                    'Article link copied to clipboard.',
                                  ),
                                  actions: [
                                    CupertinoDialogAction(
                                      onPressed: () =>
                                          Navigator.of(dialogContext).pop(),
                                      child: const Text('OK'),
                                    ),
                                  ],
                                ),
                              );
                            },
                            child: const Text('Copy Link'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ],
            const SizedBox(height: 16),
            Text(
              article.summary.trim().isEmpty
                  ? 'No description provided by the feed.'
                  : _plainText(article.summary),
              style: TextStyle(
                fontSize: 15,
                height: 1.35,
                color: _labelColor(context),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class ArticleWebViewScreen extends StatefulWidget {
  const ArticleWebViewScreen({
    super.key,
    required this.title,
    required this.uri,
  });

  final String title;
  final Uri uri;

  @override
  State<ArticleWebViewScreen> createState() => _ArticleWebViewScreenState();
}

class _ArticleWebViewScreenState extends State<ArticleWebViewScreen> {
  late final WebViewController _webViewController;
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _webViewController = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageStarted: (_) {
            if (!mounted) return;
            setState(() {
              _isLoading = true;
              _error = null;
            });
          },
          onPageFinished: (_) {
            if (!mounted) return;
            setState(() {
              _isLoading = false;
            });
          },
          onWebResourceError: (error) {
            if (!mounted) return;
            setState(() {
              _isLoading = false;
              _error = error.description;
            });
          },
        ),
      )
      ..loadRequest(widget.uri);
  }

  @override
  Widget build(BuildContext context) {
    return CupertinoPageScaffold(
      navigationBar: CupertinoNavigationBar(
        middle: Text(
          widget.title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: CupertinoButton(
          padding: EdgeInsets.zero,
          minimumSize: const Size.square(28),
          onPressed: () {
            _webViewController.reload();
          },
          child: const Icon(CupertinoIcons.refresh),
        ),
      ),
      child: SafeArea(
        child: Column(
          children: [
            if (_error != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: CupertinoColors.systemRed.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: CupertinoColors.systemRed.withValues(alpha: 0.25),
                    ),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(10),
                    child: Row(
                      children: [
                        const Icon(
                          CupertinoIcons.exclamationmark_triangle,
                          color: CupertinoColors.systemRed,
                          size: 18,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            _error!,
                            style: const TextStyle(
                              color: CupertinoColors.systemRed,
                              fontSize: 13,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            Expanded(
              child: Stack(
                children: [
                  WebViewWidget(controller: _webViewController),
                  if (_isLoading)
                    const Center(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: CupertinoColors.systemBackground,
                          borderRadius: BorderRadius.all(Radius.circular(12)),
                        ),
                        child: Padding(
                          padding: EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 10,
                          ),
                          child: CupertinoActivityIndicator(radius: 12),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            DecoratedBox(
              decoration: BoxDecoration(
                color: _cardColor(context),
                border: Border(top: BorderSide(color: _borderColor(context))),
              ),
              child: SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
                  child: Row(
                    children: [
                      CupertinoButton(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 6,
                        ),
                        onPressed: () async {
                          final canGoBack = await _webViewController.canGoBack();
                          if (canGoBack) {
                            _webViewController.goBack();
                          }
                        },
                        child: const Icon(CupertinoIcons.back),
                      ),
                      const SizedBox(width: 4),
                      CupertinoButton(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 6,
                        ),
                        onPressed: () async {
                          final canGoForward = await _webViewController.canGoForward();
                          if (canGoForward) {
                            _webViewController.goForward();
                          }
                        },
                        child: const Icon(CupertinoIcons.forward),
                      ),
                      const Spacer(),
                      CupertinoButton(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 6,
                        ),
                        color: _secondaryButtonColor(context),
                        borderRadius: BorderRadius.circular(10),
                        onPressed: () {
                          Clipboard.setData(
                            ClipboardData(text: widget.uri.toString()),
                          );
                        },
                        child: const Text('Copy URL'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

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

    final body = response.body;

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

  final SharedPreferences _prefs;

  bool _isDarkMode = false;
  List<String> _savedFeeds = <String>[];
  List<ArticleHistoryEntry> _articleHistory = <ArticleHistoryEntry>[];
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
  });

  final String title;
  final String summary;
  final String? link;
  final String? publishedLabel;
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
    );
  }
}

class _FeedHeaderCard extends StatelessWidget {
  const _FeedHeaderCard({
    required this.title,
    required this.subtitle,
    required this.itemCount,
    required this.lastLoadedAt,
    required this.feedTypeLabel,
  });

  final String title;
  final String? subtitle;
  final int itemCount;
  final DateTime? lastLoadedAt;
  final String feedTypeLabel;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: _cardColor(context),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
              ),
            ),
            if (subtitle != null && subtitle!.trim().isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(
                _plainTextPreview(subtitle!, 140),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 13,
                  color: _secondaryLabelColor(context),
                ),
              ),
            ],
            const SizedBox(height: 10),
            Text(
              '$feedTypeLabel  |  $itemCount articles${lastLoadedAt == null ? '' : '  |  Updated ${_formatTime(lastLoadedAt!)}'}',
              style: TextStyle(
                fontSize: 12,
                color: _secondaryLabelColor(context),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ArticleTile extends StatelessWidget {
  const _ArticleTile({required this.article, required this.onTap});

  final FeedArticle article;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: _cardColor(context),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      article.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (article.publishedLabel != null &&
                        article.publishedLabel!.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Text(
                        article.publishedLabel!,
                        style: TextStyle(
                          fontSize: 12,
                          color: _secondaryLabelColor(context),
                        ),
                      ),
                    ],
                    if (article.summary.trim().isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Text(
                        _plainTextPreview(article.summary, 180),
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 13,
                          color: _labelColor(context),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 10),
              const Padding(
                padding: EdgeInsets.only(top: 4),
                child: Icon(
                  CupertinoIcons.chevron_right,
                  size: 16,
                  color: CupertinoColors.systemGrey2,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({
    required this.title,
    required this.child,
    this.actionLabel,
    this.onAction,
  });

  final String title;
  final Widget child;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: _cardColor(context),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _borderColor(context)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    title,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                if (actionLabel != null)
                  CupertinoButton(
                    padding: EdgeInsets.zero,
                    minimumSize: const Size.square(28),
                    onPressed: onAction,
                    child: Text(actionLabel!),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            child,
          ],
        ),
      ),
    );
  }
}

class _LibraryRow extends StatelessWidget {
  const _LibraryRow({
    required this.title,
    required this.subtitle,
    required this.onTap,
    required this.isLast,
    this.trailing,
  });

  final String title;
  final String subtitle;
  final VoidCallback? onTap;
  final Widget? trailing;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    final row = Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: onTap == null
                        ? _secondaryLabelColor(context)
                        : _labelColor(context),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12,
                    color: _secondaryLabelColor(context),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          if (trailing != null) trailing!,
          if (onTap != null && trailing == null)
            const Padding(
              padding: EdgeInsets.only(top: 2),
              child: Icon(
                CupertinoIcons.chevron_right,
                size: 16,
                color: CupertinoColors.systemGrey2,
              ),
            ),
        ],
      ),
    );

    final content = Column(
      children: [
        if (onTap != null)
          GestureDetector(onTap: onTap, child: row)
        else
          row,
        if (!isLast)
          Container(
            height: 1,
            color: _borderColor(context),
          ),
      ],
    );

    return content;
  }
}

class _StaticInfoRow extends StatelessWidget {
  const _StaticInfoRow({
    required this.label,
    required this.value,
    required this.isLast,
  });

  final String label;
  final String value;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  label,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                value,
                style: TextStyle(
                  fontSize: 13,
                  color: _secondaryLabelColor(context),
                ),
              ),
            ],
          ),
        ),
        if (!isLast)
          Container(
            height: 1,
            color: _borderColor(context),
          ),
      ],
    );
  }
}

class _EmptySectionMessage extends StatelessWidget {
  const _EmptySectionMessage({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Text(
        message,
        style: TextStyle(
          fontSize: 13,
          color: _secondaryLabelColor(context),
        ),
      ),
    );
  }
}

Color _cardColor(BuildContext context) {
  return CupertinoDynamicColor.resolve(
    CupertinoColors.secondarySystemGroupedBackground,
    context,
  );
}

Color _borderColor(BuildContext context) {
  return CupertinoDynamicColor.resolve(
    CupertinoColors.separator,
    context,
  ).withValues(alpha: 0.35);
}

Color _secondaryButtonColor(BuildContext context) {
  return CupertinoDynamicColor.resolve(
    CupertinoColors.tertiarySystemFill,
    context,
  );
}

Color _labelColor(BuildContext context) {
  return CupertinoDynamicColor.resolve(
    CupertinoColors.label,
    context,
  );
}

Color _secondaryLabelColor(BuildContext context) {
  return CupertinoDynamicColor.resolve(
    CupertinoColors.secondaryLabel,
    context,
  );
}

String _hostOnly(String rawUrl) {
  final uri = Uri.tryParse(rawUrl);
  final host = uri?.host.trim() ?? '';
  if (host.isEmpty) return rawUrl;
  return host;
}

String _plainTextPreview(String value, int maxChars) {
  final text = _plainText(value).replaceAll(RegExp(r'\s+'), ' ').trim();
  if (text.length <= maxChars) return text;
  return '${text.substring(0, maxChars).trimRight()}...';
}

String _plainText(String value) {
  return value
      .replaceAll(RegExp(r'<[^>]*>'), ' ')
      .replaceAll('&nbsp;', ' ')
      .replaceAll('&amp;', '&')
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .replaceAll('&quot;', '"')
      .replaceAll('&ldquo;', '"')
      .replaceAll('&rdquo;', '"')
      .replaceAll('&lsquo;', "'")
      .replaceAll('&rsquo;', "'")
      .replaceAll('&#39;', "'")
      .replaceAll('&#8216;', "'")
      .replaceAll('&#8217;', "'")
      .replaceAll('&#8220;', '"')
      .replaceAll('&#8221;', '"')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
}

String _formatTime(DateTime dateTime) {
  final hour = dateTime.hour.toString().padLeft(2, '0');
  final minute = dateTime.minute.toString().padLeft(2, '0');
  return '$hour:$minute';
}

String _formatDateTime(DateTime dateTime) {
  final month = dateTime.month.toString().padLeft(2, '0');
  final day = dateTime.day.toString().padLeft(2, '0');
  final hour = dateTime.hour.toString().padLeft(2, '0');
  final minute = dateTime.minute.toString().padLeft(2, '0');
  return '${dateTime.year}-$month-$day $hour:$minute';
}

String _nonEmpty(String? value, {required String fallback}) {
  final trimmed = (value ?? '').trim();
  return trimmed.isEmpty ? fallback : trimmed;
}

String? _nullIfBlank(String? value) {
  final trimmed = (value ?? '').trim();
  return trimmed.isEmpty ? null : trimmed;
}

String? _atomTextToString(dynamic value) {
  if (value == null) return null;
  if (value is String) return value;
  final textValue = FeedRepository._firstNonNullDynamic([
    () => FeedRepository._dynamicRead(() => value.value),
    () => FeedRepository._dynamicRead(() => value.text),
    () => FeedRepository._dynamicRead(() => value.content),
  ]);
  if (textValue is String) return textValue;
  if (textValue != null) return textValue.toString();
  return value.toString();
}
