part of ../main.dart;

enum ReaderModeFontFamily {
  system,
  serif,
  humanist,
  mono,
}

String _fontFamilyLabel(ReaderModeFontFamily fontFamily) {
  switch (fontFamily) {
    case ReaderModeFontFamily.system:
      return 'System';
    case ReaderModeFontFamily.serif:
      return 'Serif';
    case ReaderModeFontFamily.humanist:
      return 'Humanist';
    case ReaderModeFontFamily.mono:
      return 'Mono';
  }
}

class ArticleScreen extends StatelessWidget {
  const ArticleScreen({super.key, required this.article});

  final FeedArticle article;

  @override
  Widget build(BuildContext context) {
    final controller = AppScope.of(context);
    final metadataLabel = [
      if (article.sourceTitle != null && article.sourceTitle!.trim().isNotEmpty)
        article.sourceTitle!.trim(),
      if (article.publishedLabel != null && article.publishedLabel!.trim().isNotEmpty)
        article.publishedLabel!.trim(),
    ].join('  |  ');
    final hasLink = article.link != null && article.link!.trim().isNotEmpty;
    final bodyText = _articleBodyText(article.summary);
    final isBookmarked = controller.isArticleBookmarked(article);

    return CupertinoPageScaffold(
      navigationBar: CupertinoNavigationBar(
        middle: Text(
          article.sourceTitle?.trim().isNotEmpty == true ? article.sourceTitle! : 'Article',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ),
      child: SafeArea(
        child: Column(
          children: [
            Expanded(
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
            _ArticleActionBar(
              article: article,
              hasLink: hasLink,
              isBookmarked: isBookmarked,
            ),
          ],
        ),
      ),
    );
  }
}

class _ArticleActionBar extends StatelessWidget {
  const _ArticleActionBar({
    required this.article,
    required this.hasLink,
    required this.isBookmarked,
  });

  final FeedArticle article;
  final bool hasLink;
  final bool isBookmarked;

  @override
  Widget build(BuildContext context) {
    final controller = AppScope.of(context);
    final link = article.link;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: _cardColor(context),
        border: Border(top: BorderSide(color: _borderColor(context))),
      ),
      child: SafeArea(
        top: false,
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
          child: Row(
            children: [
              if (hasLink) ...[
                CupertinoButton(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  color: CupertinoColors.activeBlue,
                  borderRadius: BorderRadius.circular(12),
                  onPressed: () {
                    final uri = Uri.tryParse(link!);
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
                const SizedBox(width: 8),
                CupertinoButton(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  color: _secondaryButtonColor(context),
                  borderRadius: BorderRadius.circular(12),
                  onPressed: () {
                    final uri = Uri.tryParse(link!);
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
                const SizedBox(width: 8),
              ],
              CupertinoButton(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                color: _secondaryButtonColor(context),
                borderRadius: BorderRadius.circular(12),
                onPressed: link == null
                    ? null
                    : () {
                        Clipboard.setData(ClipboardData(text: link));
                        _showSimpleDialog(
                          context,
                          title: 'Copied',
                          message: 'Article link copied to clipboard.',
                        );
                      },
                child: Row(
                  children: [
                    Icon(
                      CupertinoIcons.doc_on_doc,
                      size: 16,
                      color: _labelColor(context),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      'Copy',
                      style: TextStyle(color: _labelColor(context)),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              CupertinoButton(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                color: _secondaryButtonColor(context),
                borderRadius: BorderRadius.circular(12),
                onPressed: link == null
                    ? null
                    : () {
                        Share.share(
                          link,
                          subject: article.title,
                        );
                      },
                child: Row(
                  children: [
                    Icon(
                      CupertinoIcons.share,
                      size: 16,
                      color: _labelColor(context),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      'Share',
                      style: TextStyle(color: _labelColor(context)),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              CupertinoButton(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                color: isBookmarked
                    ? CupertinoColors.activeOrange
                    : _secondaryButtonColor(context),
                borderRadius: BorderRadius.circular(12),
                onPressed: () {
                  controller.toggleArticleBookmark(article);
                },
                child: Row(
                  children: [
                    Icon(
                      isBookmarked
                          ? CupertinoIcons.bookmark_fill
                          : CupertinoIcons.bookmark,
                      size: 16,
                      color:
                          isBookmarked ? CupertinoColors.white : _labelColor(context),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      isBookmarked ? 'Saved' : 'Save',
                      style: TextStyle(
                        color: isBookmarked
                            ? CupertinoColors.white
                            : _labelColor(context),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
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
  ReaderModeFontFamily _fontFamily = ReaderModeFontFamily.system;

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
        _buildReaderModeHtmlDocument(
          doc,
          context,
          fontFamily: _fontFamily,
        ),
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
                          horizontal: 12,
                          vertical: 6,
                        ),
                        color: _secondaryButtonColor(context),
                        borderRadius: BorderRadius.circular(10),
                        onPressed: () => _showFontPicker(context),
                        child: Text(
                          'Font: ${_fontFamilyLabel(_fontFamily)}',
                          style: TextStyle(color: _labelColor(context)),
                        ),
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
                          Share.share(widget.uri.toString(), subject: widget.title);
                        },
                        child: Row(
                          children: [
                            Icon(
                              CupertinoIcons.share,
                              size: 16,
                              color: _labelColor(context),
                            ),
                            const SizedBox(width: 6),
                            Text(
                              'Share',
                              style: TextStyle(color: _labelColor(context)),
                            ),
                          ],
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

  void _showFontPicker(BuildContext context) {
    showCupertinoModalPopup<void>(
      context: context,
      builder: (dialogContext) {
        return CupertinoActionSheet(
          title: const Text('Reader Font'),
          actions: [
            for (final option in ReaderModeFontFamily.values)
              CupertinoActionSheetAction(
                isDefaultAction: option == _fontFamily,
                onPressed: () async {
                  Navigator.of(dialogContext).pop();
                  if (option == _fontFamily) return;
                  setState(() {
                    _fontFamily = option;
                  });
                  final controller = _webViewController;
                  final doc = _readerDocument;
                  if (controller == null || doc == null) return;
                  await controller.loadHtmlString(
                    _buildReaderModeHtmlDocument(
                      doc,
                      context,
                      fontFamily: _fontFamily,
                    ),
                  );
                },
                child: Text(_fontFamilyLabel(option)),
              ),
          ],
          cancelButton: CupertinoActionSheetAction(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Cancel'),
          ),
        );
      },
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

    final document = html_parser.parse(_decodeHttpResponseBody(response));
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
