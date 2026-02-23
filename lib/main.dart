import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html_parser;
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

enum FeedVisibilityFilter {
  all,
  unread,
  read,
}

class _FeedScreenState extends State<FeedScreen> {
  static const _defaultFeed = 'https://hnrss.org/frontpage';

  final TextEditingController _searchController = TextEditingController();

  bool _isLoading = false;
  String? _error;
  FeedLoadResult? _feed;
  DateTime? _lastLoadedAt;
  int _seenFeedSelectionTick = 0;
  String _searchQuery = '';
  int _loadedFeedCount = 0;
  FeedVisibilityFilter _visibilityFilter = FeedVisibilityFilter.unread;
  Set<String> _selectedSourceFeedUrls = <String>{};

  @override
  void initState() {
    super.initState();
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

    if (hasFeedSelectionChange) {
      _seenFeedSelectionTick = widget.controller.feedSelectionTick;
      final selected = _nullIfBlank(widget.controller.activeFeedUrl);
      _selectedSourceFeedUrls = selected == null ? <String>{} : <String>{selected};
      _loadFeed();
    } else {
      final availableSources = widget.controller.savedFeeds.toSet();
      _selectedSourceFeedUrls =
          _selectedSourceFeedUrls.where(availableSources.contains).toSet();
      setState(() {});
    }
  }

  Future<void> _loadFeed() async {
    final configuredFeedUrls = widget.controller.savedFeeds.isEmpty
        ? const <String>[_defaultFeed]
        : widget.controller.savedFeeds;

    setState(() {
      _isLoading = true;
      _error = null;
    });

    final combinedArticles = <FeedArticle>[];
    final loadedFeedTitles = <String>[];
    final failedFeeds = <String>[];

    try {
      for (final rawUrl in configuredFeedUrls) {
        final uri = Uri.tryParse(rawUrl.trim());
        if (uri == null || !uri.hasScheme) {
          failedFeeds.add(rawUrl);
          continue;
        }

        try {
          final result = await FeedRepository.fetch(uri);
          loadedFeedTitles.add(result.title);
          combinedArticles.addAll(
            result.articles.map(
              (article) => article.copyWith(
                sourceTitle: result.title,
                sourceUrl: uri.toString(),
              ),
            ),
          );
        } catch (_) {
          failedFeeds.add(_hostOnly(rawUrl));
        }
      }

      combinedArticles.sort(_compareArticleRecency);

      if (!mounted) return;
      setState(() {
        _loadedFeedCount = loadedFeedTitles.length;
        _feed = FeedLoadResult(
          title: 'Timeline',
          description: loadedFeedTitles.isEmpty
              ? 'No feeds loaded'
              : 'Across ${loadedFeedTitles.length} feed${loadedFeedTitles.length == 1 ? '' : 's'}',
          articles: combinedArticles,
          feedTypeLabel: 'Feeds',
        );
        _lastLoadedAt = DateTime.now();
        if (failedFeeds.isNotEmpty && loadedFeedTitles.isNotEmpty) {
          _error =
              '${failedFeeds.length} feed${failedFeeds.length == 1 ? '' : 's'} failed: ${failedFeeds.take(3).join(', ')}${failedFeeds.length > 3 ? '…' : ''}';
        } else if (failedFeeds.isNotEmpty) {
          _error =
              'Failed to load feed${failedFeeds.length == 1 ? '' : 's'}: ${failedFeeds.take(3).join(', ')}${failedFeeds.length > 3 ? '…' : ''}';
        }
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
    widget.controller.markArticleRead(_articleReadKey(article));
    widget.controller.recordArticle(
      ArticleHistoryEntry(
        title: article.title,
        link: article.link,
        summary: article.summary,
        publishedLabel: article.publishedLabel,
        feedTitle: article.sourceTitle ?? _feed?.title,
        openedAt: DateTime.now(),
      ),
    );

    Navigator.of(context).push(
      CupertinoPageRoute<void>(
        builder: (_) => ArticleScreen(article: article),
      ),
    );
  }

  void _showAddFeedDialog() {
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
              final normalized = _normalizedFeedUrl(textController.text);
              Navigator.of(dialogContext).pop();
              if (normalized == null) {
                _showSimpleDialog(
                  context,
                  title: 'Invalid URL',
                  message: 'Enter a valid http(s) feed URL.',
                );
                return;
              }
              widget.controller.selectFeed(normalized);
            },
            child: const Text('Add'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final allArticles = _feed?.articles ?? const <FeedArticle>[];
    final sourceFilteredArticles = _articlesForSourceFilter(allArticles);
    final visibleArticles = _articlesForCurrentFilter(sourceFilteredArticles);
    final matchingVisibleCount = _filteredVisibleArticles(visibleArticles).length;

    return CupertinoPageScaffold(
      navigationBar: CupertinoNavigationBar(
        middle: const Text('Feed'),
        trailing: SizedBox(
          width: 76,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              CupertinoButton(
                padding: EdgeInsets.zero,
                minimumSize: const Size.square(28),
                onPressed: _showAddFeedDialog,
                child: const Icon(CupertinoIcons.add),
              ),
              CupertinoButton(
                padding: EdgeInsets.zero,
                minimumSize: const Size.square(28),
                onPressed: _isLoading ? null : _loadFeed,
                child: _isLoading
                    ? const CupertinoActivityIndicator(radius: 8)
                    : const Icon(CupertinoIcons.refresh),
              ),
            ],
          ),
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
              child: Align(
                alignment: Alignment.centerLeft,
                child: CupertinoSlidingSegmentedControl<FeedVisibilityFilter>(
                  groupValue: _visibilityFilter,
                  onValueChanged: (value) {
                    if (value == null) return;
                    setState(() {
                      _visibilityFilter = value;
                    });
                  },
                  children: const {
                    FeedVisibilityFilter.all: Padding(
                      padding: EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      child: Text('All'),
                    ),
                    FeedVisibilityFilter.unread: Padding(
                      padding: EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      child: Text('Unread'),
                    ),
                    FeedVisibilityFilter.read: Padding(
                      padding: EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      child: Text('Read'),
                    ),
                  },
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
              child: Row(
                children: [
                  const Icon(
                    CupertinoIcons.list_bullet,
                    size: 14,
                    color: CupertinoColors.systemGrey,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      _loadedFeedCount == 0
                          ? 'No feeds loaded. Add feeds in Library.'
                          : '$_loadedFeedCount feed${_loadedFeedCount == 1 ? '' : 's'} loaded',
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
                      '$matchingVisibleCount matches',
                      style: TextStyle(
                        fontSize: 12,
                        color: _secondaryLabelColor(context),
                      ),
                    ),
                ],
              ),
            ),
            if (_sourceFilterOptions.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                child: SizedBox(
                  height: 34,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: _sourceFilterOptions.length + 1,
                    separatorBuilder: (_, __) => const SizedBox(width: 8),
                    itemBuilder: (context, index) {
                      if (index == 0) {
                        final allSelected = _selectedSourceFeedUrls.isEmpty;
                        return _FilterPill(
                          label: 'All Feeds',
                          selected: allSelected,
                          onTap: () {
                            setState(() {
                              _selectedSourceFeedUrls = <String>{};
                            });
                          },
                        );
                      }
                      final option = _sourceFilterOptions[index - 1];
                      final selected =
                          _selectedSourceFeedUrls.contains(option.sourceUrl);
                      return _FilterPill(
                        label: option.label,
                        selected: selected,
                        onTap: () {
                          setState(() {
                            final next = <String>{..._selectedSourceFeedUrls};
                            if (selected) {
                              next.remove(option.sourceUrl);
                            } else {
                              next.add(option.sourceUrl);
                            }
                            _selectedSourceFeedUrls = next;
                          });
                        },
                      );
                    },
                  ),
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
    final sourceFilteredArticles = _articlesForSourceFilter(allArticles);
    final visibleArticles = _articlesForCurrentFilter(sourceFilteredArticles);
    final articles = _filteredVisibleArticles(visibleArticles);
    final showSearchEmptyState =
        visibleArticles.isEmpty && _searchQuery.trim().isEmpty;
    final showNoMatchesState =
        articles.isEmpty && _searchQuery.trim().isNotEmpty;

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
              subtitle: _feedHeaderSubtitle(),
              itemCount: articles.length,
              lastLoadedAt: _lastLoadedAt,
              feedTypeLabel: _feedFilterLabel(_visibilityFilter),
            ),
          ),
        ),
        if (showSearchEmptyState)
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
                    _emptyStateMessageForFilter(),
                    style: TextStyle(
                      fontSize: 14,
                      color: _secondaryLabelColor(context),
                    ),
                  ),
                ),
              ),
            ),
          ),
        if (showNoMatchesState)
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
                final articleKey = _articleReadKey(article);
                final isRead = widget.controller.isArticleRead(articleKey);

                Widget item = _ArticleTile(
                  article: article,
                  onTap: () => _openArticle(article),
                  isRead: isRead,
                );
                if (!isRead) {
                  item = Dismissible(
                    key: ValueKey<String>('$articleKey::$index'),
                    direction: DismissDirection.endToStart,
                    background: const SizedBox.shrink(),
                    secondaryBackground: const _MarkReadSwipeBackground(
                      label: 'Mark Read',
                    ),
                    onDismissed: (_) {
                      widget.controller.markArticleRead(articleKey);
                    },
                    child: item,
                  );
                } else {
                  item = KeyedSubtree(
                    key: ValueKey<String>('$articleKey::$index'),
                    child: item,
                  );
                }

                return Padding(
                  padding:
                      EdgeInsets.only(bottom: index == articles.length - 1 ? 0 : 8),
                  child: item,
                );
              },
              childCount: articles.length,
            ),
          ),
        ),
      ],
    );
  }

  List<FeedArticle> _articlesForSourceFilter(List<FeedArticle> articles) {
    if (_selectedSourceFeedUrls.isEmpty) return articles;
    return articles.where((article) {
      final sourceUrl = _nullIfBlank(article.sourceUrl);
      return sourceUrl != null && _selectedSourceFeedUrls.contains(sourceUrl);
    }).toList();
  }

  List<FeedArticle> _articlesForCurrentFilter(List<FeedArticle> articles) {
    return articles.where((article) {
      final isRead = widget.controller.isArticleRead(_articleReadKey(article));
      switch (_visibilityFilter) {
        case FeedVisibilityFilter.all:
          return true;
        case FeedVisibilityFilter.unread:
          return !isRead;
        case FeedVisibilityFilter.read:
          return isRead;
      }
    }).toList();
  }

  List<FeedArticle> _filteredVisibleArticles(List<FeedArticle> articles) {
    final query = _searchQuery.trim().toLowerCase();
    if (query.isEmpty) return articles;
    return articles.where((article) => _matchesSearchQuery(article, query)).toList();
  }

  String _feedFilterLabel(FeedVisibilityFilter filter) {
    switch (filter) {
      case FeedVisibilityFilter.all:
        return 'All';
      case FeedVisibilityFilter.unread:
        return 'Unread';
      case FeedVisibilityFilter.read:
        return 'Read';
    }
  }

  String? _feedHeaderSubtitle() {
    final base = _feed?.description;
    if (_selectedSourceFeedUrls.isEmpty) return base;
    final selectedLabels = _sourceFilterOptions
        .where((option) => _selectedSourceFeedUrls.contains(option.sourceUrl))
        .map((option) => option.label)
        .toList();
    if (selectedLabels.isEmpty) return base;
    final sourceText = selectedLabels.length <= 2
        ? selectedLabels.join(', ')
        : '${selectedLabels.take(2).join(', ')} +${selectedLabels.length - 2}';
    if (base == null || base.trim().isEmpty) {
      return 'Sources: $sourceText';
    }
    return '$base  |  Sources: $sourceText';
  }

  String _emptyStateMessageForFilter() {
    final sourceScope = _selectedSourceFeedUrls.isEmpty
        ? ''
        : ' for the selected feed filter';
    switch (_visibilityFilter) {
      case FeedVisibilityFilter.all:
        return 'No articles available$sourceScope yet. Pull to refresh after adding feeds.';
      case FeedVisibilityFilter.unread:
        return 'All caught up$sourceScope. Swipe actions marked articles as read.';
      case FeedVisibilityFilter.read:
        return 'No read stories$sourceScope yet. Open articles to mark them read.';
    }
  }

  bool _matchesSearchQuery(FeedArticle article, String query) {
    final haystacks = <String>[
      article.title,
      article.summary,
      article.publishedLabel ?? '',
      article.link ?? '',
      article.sourceTitle ?? '',
    ];
    for (final value in haystacks) {
      if (value.toLowerCase().contains(query)) {
        return true;
      }
    }
    return false;
  }

  List<_SourceFilterOption> get _sourceFilterOptions {
    final byUrl = <String, _SourceFilterOption>{};
    for (final url in widget.controller.savedFeeds) {
      byUrl[url] = _SourceFilterOption(sourceUrl: url, label: _hostOnly(url));
    }
    for (final article in _feed?.articles ?? const <FeedArticle>[]) {
      final sourceUrl = _nullIfBlank(article.sourceUrl);
      if (sourceUrl == null) continue;
      final label = _nullIfBlank(article.sourceTitle) ?? _hostOnly(sourceUrl);
      byUrl[sourceUrl] = _SourceFilterOption(sourceUrl: sourceUrl, label: label);
    }
    final options = byUrl.values.toList();
    options.sort((a, b) => a.label.toLowerCase().compareTo(b.label.toLowerCase()));
    return options;
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
                  title: 'Feed Backup',
                  child: Column(
                    children: [
                      _LibraryRow(
                        title: 'Import Feed URLs',
                        subtitle: 'Text file, one URL per line (invalid lines are skipped)',
                        onTap: () => _importFeeds(context),
                        trailing: const Icon(
                          CupertinoIcons.square_arrow_down,
                          size: 18,
                          color: CupertinoColors.systemGrey,
                        ),
                        isLast: false,
                      ),
                      _LibraryRow(
                        title: 'Export Feed URLs',
                        subtitle:
                            '${controller.savedFeeds.length} saved feed${controller.savedFeeds.length == 1 ? '' : 's'} to plain text',
                        onTap: () => _exportFeeds(context),
                        trailing: const Icon(
                          CupertinoIcons.square_arrow_up,
                          size: 18,
                          color: CupertinoColors.systemGrey,
                        ),
                        isLast: true,
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
                                  controller.markArticleRead(
                                    _articleReadKey(entry.toFeedArticle()),
                                  );
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
              final normalized = _normalizedFeedUrl(textController.text);
              Navigator.of(dialogContext).pop();
              if (normalized == null) {
                _showSimpleDialog(
                  context,
                  title: 'Invalid URL',
                  message: 'Enter a valid feed URL (for example: https://site.com/feed.xml).',
                );
                return;
              }

              onOpenFeed(normalized);
            },
            child: const Text('Add'),
          ),
        ],
      ),
    );
  }

  Future<void> _importFeeds(BuildContext context) async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: const ['txt'],
        withData: true,
      );
      if (result == null || result.files.isEmpty) return;

      final file = result.files.single;
      String raw;
      if (file.bytes != null) {
        raw = utf8.decode(file.bytes!, allowMalformed: true);
      } else if (file.path != null && file.path!.isNotEmpty) {
        raw = await File(file.path!).readAsString();
      } else {
        if (!context.mounted) return;
        _showSimpleDialog(
          context,
          title: 'Import Failed',
          message: 'The selected file could not be read.',
        );
        return;
      }

      final importResult = controller.importFeedsFromText(raw);
      if (!context.mounted) return;
      _showSimpleDialog(
        context,
        title: 'Import Complete',
        message: importResult.summaryMessage,
      );
    } catch (e) {
      if (!context.mounted) return;
      _showSimpleDialog(
        context,
        title: 'Import Failed',
        message: e.toString().replaceFirst('Exception: ', ''),
      );
    }
  }

  Future<void> _exportFeeds(BuildContext context) async {
    try {
      final fileName = 'rss-feeds-${DateTime.now().toIso8601String().split('T').first}.txt';
      final savePath = await FilePicker.platform.saveFile(
        dialogTitle: 'Export Feed URLs',
        fileName: fileName,
      );
      if (savePath == null || savePath.trim().isEmpty) return;

      final exportText = controller.exportFeedsAsText();
      await File(savePath).writeAsString(exportText);
      if (!context.mounted) return;
      _showSimpleDialog(
        context,
        title: 'Export Complete',
        message:
            'Saved ${controller.savedFeeds.length} feed URL${controller.savedFeeds.length == 1 ? '' : 's'} to ${savePath.split(Platform.pathSeparator).last}.',
      );
    } catch (_) {
      if (!context.mounted) return;
      _showSimpleDialog(
        context,
        title: 'Export Failed',
        message:
            'Could not save the backup file. Try a local storage folder and a .txt filename.',
      );
    }
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
                        isLast: false,
                      ),
                      _LibraryRow(
                        title: 'Read Article Marks',
                        subtitle: '${controller.readArticleCount} hidden as read',
                        onTap: controller.readArticleCount == 0
                            ? null
                            : controller.clearReadArticles,
                        trailing: controller.readArticleCount == 0
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
                        value: 'Native preview + WebView',
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
    final metadataLabel = [
      if (article.sourceTitle != null && article.sourceTitle!.trim().isNotEmpty)
        article.sourceTitle!.trim(),
      if (article.publishedLabel != null && article.publishedLabel!.trim().isNotEmpty)
        article.publishedLabel!.trim(),
    ].join('  |  ');
    final hasLink = article.link != null && article.link!.trim().isNotEmpty;
    final bodyText = _articleBodyText(article.summary);

    return CupertinoPageScaffold(
      navigationBar: CupertinoNavigationBar(
        middle: Text(
          article.sourceTitle?.trim().isNotEmpty == true ? article.sourceTitle! : 'Article',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ),
      child: SafeArea(
        child: CustomScrollView(
          physics: const BouncingScrollPhysics(
            parent: AlwaysScrollableScrollPhysics(),
          ),
          slivers: [
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: _cardColor(context),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: _borderColor(context)),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          article.title,
                          style: TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.w700,
                            color: _labelColor(context),
                            height: 1.2,
                          ),
                        ),
                        if (metadataLabel.isNotEmpty) ...[
                          const SizedBox(height: 8),
                          Text(
                            metadataLabel,
                            style: TextStyle(
                              fontSize: 12,
                              color: _secondaryLabelColor(context),
                            ),
                          ),
                        ],
                        if (hasLink) ...[
                          const SizedBox(height: 12),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              CupertinoButton(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 10,
                                ),
                                color: CupertinoColors.activeBlue,
                                borderRadius: BorderRadius.circular(12),
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
                                child: const Text(
                                  'Read Full Story',
                                  style: TextStyle(color: CupertinoColors.white),
                                ),
                              ),
                              CupertinoButton(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 10,
                                ),
                                color: _secondaryButtonColor(context),
                                borderRadius: BorderRadius.circular(12),
                                onPressed: () {
                                  final uri = Uri.tryParse(article.link!);
                                  if (uri == null) return;
                                  Navigator.of(context).push(
                                    CupertinoPageRoute<void>(
                                      builder: (_) => ArticleReaderModeScreen(
                                        title: article.title,
                                        uri: uri,
                                      ),
                                    ),
                                  );
                                },
                                child: Text(
                                  'Reader Mode',
                                  style: TextStyle(color: _labelColor(context)),
                                ),
                              ),
                              CupertinoButton(
                                padding: EdgeInsets.zero,
                                minimumSize: const Size.square(40),
                                color: _secondaryButtonColor(context),
                                borderRadius: BorderRadius.circular(12),
                                onPressed: () {
                                  Clipboard.setData(ClipboardData(text: article.link!));
                                  _showSimpleDialog(
                                    context,
                                    title: 'Copied',
                                    message: 'Article link copied to clipboard.',
                                  );
                                },
                                child: Icon(
                                  CupertinoIcons.doc_on_doc,
                                  size: 18,
                                  color: _labelColor(context),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            ),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: _cardColor(context),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: _borderColor(context)),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Preview',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: _secondaryLabelColor(context),
                          ),
                        ),
                        const SizedBox(height: 10),
                        if (bodyText.isEmpty)
                          Text(
                            'No article content was provided by this feed entry.',
                            style: TextStyle(
                              color: _secondaryLabelColor(context),
                              fontSize: 14,
                            ),
                          )
                        else
                          Text(
                            bodyText,
                            style: TextStyle(
                              fontSize: 16,
                              color: _labelColor(context),
                              height: 1.4,
                            ),
                          ),
                      ],
                    ),
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
                        child: Text(
                          'Copy URL',
                          style: TextStyle(color: _labelColor(context)),
                        ),
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

class ArticleReaderModeScreen extends StatefulWidget {
  const ArticleReaderModeScreen({
    super.key,
    required this.title,
    required this.uri,
  });

  final String title;
  final Uri uri;

  @override
  State<ArticleReaderModeScreen> createState() => _ArticleReaderModeScreenState();
}

class _ArticleReaderModeScreenState extends State<ArticleReaderModeScreen> {
  WebViewController? _webViewController;
  bool _isLoading = true;
  String? _error;
  ReaderModeDocument? _readerDocument;

  @override
  void initState() {
    super.initState();
    _loadReaderMode();
  }

  Future<void> _loadReaderMode() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final doc = await ReaderModeRepository.fetch(widget.uri);
      if (!mounted) return;

      final controller = WebViewController()
        ..setJavaScriptMode(JavaScriptMode.disabled)
        ..setNavigationDelegate(
          NavigationDelegate(
            onNavigationRequest: (request) {
              final url = request.url;
              if (url == 'about:blank' || url.startsWith('data:')) {
                return NavigationDecision.navigate;
              }
              if (!mounted) return NavigationDecision.prevent;
              final target = Uri.tryParse(request.url);
              if (target == null) return NavigationDecision.prevent;
              if (target.scheme != 'http' && target.scheme != 'https') {
                return NavigationDecision.prevent;
              }
              Navigator.of(context).push(
                CupertinoPageRoute<void>(
                  builder: (_) => ArticleWebViewScreen(
                    title: doc.title,
                    uri: target,
                  ),
                ),
              );
              return NavigationDecision.prevent;
            },
          ),
        );
      await controller.loadHtmlString(
        _buildReaderModeHtmlDocument(doc, context),
      );
      if (!mounted) return;
      setState(() {
        _readerDocument = doc;
        _webViewController = controller;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString().replaceFirst('Exception: ', '');
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final title = _readerDocument?.siteName ??
        _readerDocument?.title ??
        widget.uri.host;

    return CupertinoPageScaffold(
      navigationBar: CupertinoNavigationBar(
        middle: Text(
          title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: CupertinoButton(
          padding: EdgeInsets.zero,
          minimumSize: const Size.square(28),
          onPressed: _isLoading ? null : _loadReaderMode,
          child: _isLoading
              ? const CupertinoActivityIndicator(radius: 8)
              : const Icon(CupertinoIcons.refresh),
        ),
      ),
      child: SafeArea(
        child: Column(
          children: [
            if (_error != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
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
                  if (_webViewController != null)
                    WebViewWidget(controller: _webViewController!)
                  else
                    Container(color: _cardColor(context)),
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
          ],
        ),
      ),
    );
  }
}

class ReaderModeDocument {
  const ReaderModeDocument({
    required this.title,
    required this.siteName,
    required this.sourceUrl,
    required this.contentHtml,
    this.byline,
  });

  final String title;
  final String siteName;
  final String sourceUrl;
  final String contentHtml;
  final String? byline;
}

class ReaderModeRepository {
  static Future<ReaderModeDocument> fetch(Uri uri) async {
    final response = await http.get(
      uri,
      headers: const {
        'User-Agent': 'rss-reader-cupertino/0.3 (+flutter reader-mode)',
        'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
      },
    );

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('HTTP ${response.statusCode} while loading article.');
    }

    final document = html_parser.parse(response.body);
    _removeReaderNoise(document);

    final contentNode = _extractReaderContentNode(document);
    if (contentNode == null) {
      throw Exception('Could not extract readable content from this page.');
    }

    _sanitizeReaderContent(contentNode, uri);
    final contentHtml = contentNode.innerHtml.trim();
    final contentText = contentNode.text.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (contentHtml.isEmpty || contentText.length < 80) {
      throw Exception('This page did not provide enough readable article content.');
    }

    final title = _readerTitle(document, fallback: uri.host);
    final siteName = _readerSiteName(document, fallback: uri.host);
    final byline = _readerByline(document);

    return ReaderModeDocument(
      title: title,
      siteName: siteName,
      sourceUrl: uri.toString(),
      contentHtml: contentHtml,
      byline: byline,
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
  static const _keyReadArticleKeys = 'library.readArticleKeys';

  final SharedPreferences _prefs;

  bool _isDarkMode = false;
  List<String> _savedFeeds = <String>[];
  List<ArticleHistoryEntry> _articleHistory = <ArticleHistoryEntry>[];
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
  const _ArticleTile({
    required this.article,
    required this.onTap,
    this.isRead = false,
  });

  final FeedArticle article;
  final VoidCallback onTap;
  final bool isRead;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: _cardColor(context),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isRead
                ? _borderColor(context).withValues(alpha: 0.6)
                : _borderColor(context),
          ),
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
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: isRead
                            ? _secondaryLabelColor(context)
                            : _labelColor(context),
                      ),
                    ),
                    if (isRead) ...[
                      const SizedBox(height: 6),
                      DecoratedBox(
                        decoration: BoxDecoration(
                          color: CupertinoColors.systemGrey4.withValues(alpha: 0.5),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: const Padding(
                          padding:
                              EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          child: Text(
                            'Read',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: CupertinoColors.systemGrey,
                            ),
                          ),
                        ),
                      ),
                    ],
                    if (article.publishedLabel != null &&
                        article.publishedLabel!.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Text(
                        [
                          if (article.sourceTitle != null &&
                              article.sourceTitle!.trim().isNotEmpty)
                            article.sourceTitle!.trim(),
                          article.publishedLabel!,
                        ].join('  |  '),
                        style: TextStyle(
                          fontSize: 12,
                          color: _secondaryLabelColor(context),
                        ),
                      ),
                    ],
                    if ((article.publishedLabel == null ||
                            article.publishedLabel!.isEmpty) &&
                        article.sourceTitle != null &&
                        article.sourceTitle!.trim().isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Text(
                        article.sourceTitle!.trim(),
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
                          color: isRead
                              ? _secondaryLabelColor(context)
                              : _labelColor(context),
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

class _MarkReadSwipeBackground extends StatelessWidget {
  const _MarkReadSwipeBackground({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: CupertinoColors.activeGreen.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: CupertinoColors.activeGreen.withValues(alpha: 0.35),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            const Icon(
              CupertinoIcons.check_mark_circled,
              color: CupertinoColors.activeGreen,
              size: 18,
            ),
            const SizedBox(width: 8),
            Text(
              label,
              style: const TextStyle(
                color: CupertinoColors.activeGreen,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FilterPill extends StatelessWidget {
  const _FilterPill({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return CupertinoButton(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      minimumSize: Size.zero,
      borderRadius: BorderRadius.circular(999),
      color: selected ? CupertinoColors.activeBlue : _secondaryButtonColor(context),
      onPressed: onTap,
      child: Text(
        label,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: selected ? CupertinoColors.white : _labelColor(context),
        ),
      ),
    );
  }
}

class _SourceFilterOption {
  const _SourceFilterOption({
    required this.sourceUrl,
    required this.label,
  });

  final String sourceUrl;
  final String label;
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

String? _normalizedFeedUrl(String raw) {
  final trimmed = raw.trim();
  if (trimmed.isEmpty) return null;
  final uri = Uri.tryParse(trimmed);
  if (uri == null || !uri.hasScheme || uri.host.trim().isEmpty) return null;
  final scheme = uri.scheme.toLowerCase();
  if (scheme != 'http' && scheme != 'https') return null;
  return uri.toString();
}

void _showSimpleDialog(
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

String _articleReadKey(FeedArticle article) {
  final link = _nullIfBlank(article.link);
  if (link != null) return 'link:$link';

  final source = _nullIfBlank(article.sourceUrl) ?? _nullIfBlank(article.sourceTitle) ?? '';
  final published = _nullIfBlank(article.publishedLabel) ?? '';
  return 'fallback:$source|${article.title}|$published';
}

int _compareArticleRecency(FeedArticle a, FeedArticle b) {
  final aDate = _tryParseArticleDate(a.publishedLabel);
  final bDate = _tryParseArticleDate(b.publishedLabel);
  if (aDate != null && bDate != null) {
    return bDate.compareTo(aDate);
  }
  if (aDate != null) return -1;
  if (bDate != null) return 1;
  return a.title.toLowerCase().compareTo(b.title.toLowerCase());
}

DateTime? _tryParseArticleDate(String? value) {
  final text = _nullIfBlank(value);
  if (text == null) return null;
  try {
    return DateTime.parse(text).toUtc();
  } catch (_) {
    return null;
  }
}

String _articleBodyText(String value) {
  if (value.trim().isEmpty) return '';
  return value
      .replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), '\n')
      .replaceAll(RegExp(r'</p>', caseSensitive: false), '\n\n')
      .replaceAll(RegExp(r'</div>', caseSensitive: false), '\n')
      .replaceAll(RegExp(r'</li>', caseSensitive: false), '\n')
      .replaceAll(RegExp(r'<li[^>]*>', caseSensitive: false), '- ')
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
      .replaceAll(RegExp(r'[ \t]+\n'), '\n')
      .replaceAll(RegExp(r'\n[ \t]+'), '\n')
      .replaceAll(RegExp(r'\n{3,}'), '\n\n')
      .replaceAll(RegExp(r' {2,}'), ' ')
      .trim();
}

String _buildReaderModeHtmlDocument(ReaderModeDocument doc, BuildContext context) {
  final brightness = CupertinoTheme.of(context).brightness ?? Brightness.light;
  final darkMode = brightness == Brightness.dark;

  final bg = darkMode ? '#0b0b0d' : '#f2f2f7';
  final surface = darkMode ? '#151518' : '#ffffff';
  final text = darkMode ? '#f5f5f7' : '#111111';
  final muted = darkMode ? '#a1a1aa' : '#6b7280';
  final border = darkMode ? '#2b2b31' : '#e5e7eb';
  final link = '#0a84ff';

  final title = _htmlEscape(doc.title);
  final siteName = _htmlEscape(doc.siteName);
  final sourceUrl = _htmlEscape(doc.sourceUrl);
  final byline = _htmlEscape(doc.byline ?? '');

  return '''
<!doctype html>
<html>
  <head>
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <style>
      :root { color-scheme: ${darkMode ? 'dark' : 'light'}; }
      body {
        margin: 0;
        background: $bg;
        color: $text;
        font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif;
        line-height: 1.55;
        word-break: break-word;
      }
      .wrap {
        max-width: 760px;
        margin: 0 auto;
        padding: 14px;
      }
      .meta, .content {
        background: $surface;
        border: 1px solid $border;
        border-radius: 14px;
      }
      .meta {
        padding: 16px;
        margin-bottom: 10px;
      }
      .title {
        margin: 0;
        font-size: 28px;
        line-height: 1.15;
      }
      .sub {
        margin-top: 8px;
        color: $muted;
        font-size: 13px;
      }
      .content {
        padding: 16px;
        font-size: 18px;
      }
      .content p, .content li {
        font-size: 18px;
      }
      .content h1, .content h2, .content h3, .content h4 {
        line-height: 1.2;
        margin-top: 1.2em;
        margin-bottom: 0.5em;
      }
      .content img, .content video {
        max-width: 100%;
        height: auto;
        border-radius: 10px;
      }
      .content pre, .content code {
        white-space: pre-wrap;
        word-break: break-word;
      }
      .content blockquote {
        margin: 1em 0;
        padding: 0.2em 1em;
        border-left: 4px solid $border;
        color: $muted;
      }
      .content a {
        color: $link;
      }
      .content table {
        width: 100%;
        border-collapse: collapse;
        display: block;
        overflow-x: auto;
      }
    </style>
  </head>
  <body>
    <div class="wrap">
      <div class="meta">
        <h1 class="title">$title</h1>
        <div class="sub">$siteName${byline.isEmpty ? '' : '  |  $byline'}</div>
        <div class="sub"><a href="$sourceUrl">$sourceUrl</a></div>
      </div>
      <div class="content">
        ${doc.contentHtml}
      </div>
    </div>
  </body>
</html>
''';
}

void _removeReaderNoise(dom.Document document) {
  final selectors = [
    'script',
    'style',
    'noscript',
    'template',
    'svg',
    'canvas',
    'iframe',
    'form',
    'button',
    'input',
    'select',
    'textarea',
    'nav',
    'footer',
    'aside',
    '.advertisement',
    '.ads',
    '.ad',
    '.promo',
    '.newsletter',
    '.subscribe',
    '[aria-hidden="true"]',
  ];
  for (final selector in selectors) {
    for (final node in document.querySelectorAll(selector)) {
      node.remove();
    }
  }
}

dom.Element? _extractReaderContentNode(dom.Document document) {
  const preferredSelectors = [
    'article',
    'main article',
    '[itemprop="articleBody"]',
    '[role="main"] article',
    'main',
    '.article-body',
    '.entry-content',
    '.post-content',
    '.article-content',
    '#article-body',
    '#content',
  ];

  for (final selector in preferredSelectors) {
    final node = document.querySelector(selector);
    if (node == null) continue;
    if (_readerTextLength(node) >= 200) {
      return node.clone(true);
    }
  }

  final candidates = document.querySelectorAll('article, main, section, div');
  dom.Element? best;
  double bestScore = 0;
  for (final candidate in candidates) {
    final score = _readerContentScore(candidate);
    if (score > bestScore) {
      bestScore = score;
      best = candidate;
    }
  }

  if (best != null && _readerTextLength(best) >= 120) {
    return best.clone(true);
  }

  final body = document.body;
  if (body == null) return null;
  if (_readerTextLength(body) < 80) return null;
  return body.clone(true);
}

double _readerContentScore(dom.Element element) {
  final textLen = _readerTextLength(element);
  if (textLen < 60) return 0;
  final pCount = element.querySelectorAll('p').length;
  final imgCount = element.querySelectorAll('img').length;
  final linkTextLen = element
      .querySelectorAll('a')
      .map((link) => _normalizedText(link.text).length)
      .fold<int>(0, (sum, value) => sum + value);
  final linkDensity = textLen == 0 ? 0 : linkTextLen / textLen;
  final className = element.className.toString().toLowerCase();
  final classPenalty = (className.contains('comment') ||
          className.contains('footer') ||
          element.id.toLowerCase().contains('comment'))
      ? 200
      : 0;
  return textLen.toDouble() +
      (pCount * 80).toDouble() +
      (imgCount * 35).toDouble() -
      (linkDensity * 220) -
      classPenalty.toDouble();
}

int _readerTextLength(dom.Element element) => _normalizedText(element.text).length;

String _normalizedText(String value) =>
    value.replaceAll(RegExp(r'\s+'), ' ').trim();

void _sanitizeReaderContent(dom.Element root, Uri baseUri) {
  for (final node in root.querySelectorAll(
    'script,style,noscript,iframe,canvas,svg,form,button,input,select,textarea',
  )) {
    node.remove();
  }

  final allElements = <dom.Element>[root, ...root.querySelectorAll('*')];
  for (final element in allElements) {
    if (element.localName == 'img') {
      final src = _nullIfBlank(
        element.attributes['src'] ??
            element.attributes['data-src'] ??
            element.attributes['data-original'],
      );
      if (src == null) {
        element.remove();
        continue;
      }
      element.attributes['src'] = _resolveUrl(baseUri, src);
    }

    if (element.localName == 'a') {
      final href = _nullIfBlank(element.attributes['href']);
      if (href != null) {
        element.attributes['href'] = _resolveUrl(baseUri, href);
      }
    }

    final attrs = element.attributes.keys.map((key) => key.toString()).toList();
    for (final attr in attrs) {
      final lower = attr.toLowerCase();
      if (lower.startsWith('on')) {
        element.attributes.remove(attr);
        continue;
      }
      if (lower == 'style' ||
          lower == 'class' ||
          lower == 'id' ||
          lower == 'srcset' ||
          lower == 'sizes' ||
          lower == 'loading' ||
          lower == 'decoding') {
        element.attributes.remove(attr);
      }
    }
  }
}

String _resolveUrl(Uri baseUri, String raw) {
  final parsed = Uri.tryParse(raw);
  if (parsed == null) return raw;
  if (parsed.hasScheme) return parsed.toString();
  return baseUri.resolveUri(parsed).toString();
}

String _readerTitle(dom.Document document, {required String fallback}) {
  final ogTitle = document
      .querySelector('meta[property="og:title"]')
      ?.attributes['content'];
  final title = _nullIfBlank(ogTitle) ??
      _nullIfBlank(document.querySelector('title')?.text);
  return title ?? fallback;
}

String _readerSiteName(dom.Document document, {required String fallback}) {
  final ogSite = document
      .querySelector('meta[property="og:site_name"]')
      ?.attributes['content'];
  return _nullIfBlank(ogSite) ?? fallback;
}

String? _readerByline(dom.Document document) {
  const selectors = [
    'meta[name="author"]',
    'meta[property="article:author"]',
    '[rel="author"]',
    '.author',
    '.byline',
    '[itemprop="author"]',
  ];
  for (final selector in selectors) {
    final node = document.querySelector(selector);
    if (node == null) continue;
    final content = _nullIfBlank(node.attributes['content']) ?? _nullIfBlank(node.text);
    if (content != null) return _normalizedText(content);
  }
  return null;
}

String _htmlEscape(String value) => htmlEscape.convert(value);

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
