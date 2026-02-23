part of 'package:rss_reader_cupertino/main.dart';

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

