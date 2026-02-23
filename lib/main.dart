import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:webfeed_plus/webfeed_plus.dart';

void main() {
  runApp(const RssReaderApp());
}

class RssReaderApp extends StatelessWidget {
  const RssReaderApp({super.key});

  @override
  Widget build(BuildContext context) {
    return CupertinoApp(
      title: 'RSS Reader',
      debugShowCheckedModeBanner: false,
      theme: const CupertinoThemeData(
        brightness: Brightness.light,
        primaryColor: CupertinoColors.activeBlue,
        scaffoldBackgroundColor: Color(0xFFF2F2F7),
      ),
      home: const FeedScreen(),
    );
  }
}

class FeedScreen extends StatefulWidget {
  const FeedScreen({super.key});

  @override
  State<FeedScreen> createState() => _FeedScreenState();
}

class _FeedScreenState extends State<FeedScreen> {
  static const _defaultFeed = 'https://hnrss.org/frontpage';

  final TextEditingController _urlController =
      TextEditingController(text: _defaultFeed);

  bool _isLoading = false;
  String? _error;
  String? _feedTitle;
  String? _feedSubtitle;
  DateTime? _lastLoadedAt;
  List<FeedArticle> _articles = const [];

  @override
  void initState() {
    super.initState();
    _loadFeed();
  }

  @override
  void dispose() {
    _urlController.dispose();
    super.dispose();
  }

  Future<void> _loadFeed() async {
    final rawUrl = _urlController.text.trim();
    if (rawUrl.isEmpty) {
      setState(() {
        _error = 'Enter an RSS feed URL.';
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
      final result = await RssRepository.fetch(uri);
      if (!mounted) return;
      setState(() {
        _feedTitle = result.title;
        _feedSubtitle = result.description;
        _articles = result.articles;
        _lastLoadedAt = DateTime.now();
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString().replaceFirst('Exception: ', '');
      });
    } finally {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = CupertinoTheme.of(context);

    return CupertinoPageScaffold(
      navigationBar: CupertinoNavigationBar(
        middle: const Text('RSS Reader'),
        trailing: CupertinoButton(
          padding: EdgeInsets.zero,
          minSize: 28,
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
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
              child: Row(
                children: [
                  Expanded(
                    child: CupertinoTextField(
                      controller: _urlController,
                      keyboardType: TextInputType.url,
                      placeholder: 'https://example.com/feed.xml',
                      prefix: const Padding(
                        padding: EdgeInsets.only(left: 10),
                        child: Icon(
                          CupertinoIcons.link,
                          size: 18,
                          color: CupertinoColors.systemGrey,
                        ),
                      ),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 12,
                      ),
                      onSubmitted: (_) => _loadFeed(),
                    ),
                  ),
                  const SizedBox(width: 8),
                  CupertinoButton(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    color: theme.primaryColor,
                    borderRadius: BorderRadius.circular(10),
                    onPressed: _isLoading ? null : _loadFeed,
                    child: const Text('Load'),
                  ),
                ],
              ),
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: CupertinoColors.systemRed.withOpacity(0.10),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: CupertinoColors.systemRed.withOpacity(0.25),
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
              child: _buildFeedBody(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFeedBody() {
    if (_isLoading && _articles.isEmpty) {
      return const Center(child: CupertinoActivityIndicator(radius: 14));
    }

    if (_articles.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            'No articles yet. Paste an RSS feed URL and tap Load.',
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: CupertinoColors.systemGrey,
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
              title: _feedTitle ?? 'Feed',
              subtitle: _feedSubtitle,
              itemCount: _articles.length,
              lastLoadedAt: _lastLoadedAt,
            ),
          ),
        ),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 16),
          sliver: SliverList(
            delegate: SliverChildBuilderDelegate(
              (context, index) {
                final article = _articles[index];
                return Padding(
                  padding:
                      EdgeInsets.only(bottom: index == _articles.length - 1 ? 0 : 8),
                  child: _ArticleTile(
                    article: article,
                    onTap: () {
                      Navigator.of(context).push(
                        CupertinoPageRoute<void>(
                          builder: (_) => ArticleScreen(article: article),
                        ),
                      );
                    },
                  ),
                );
              },
              childCount: _articles.length,
            ),
          ),
        ),
      ],
    );
  }
}

class _FeedHeaderCard extends StatelessWidget {
  const _FeedHeaderCard({
    required this.title,
    required this.subtitle,
    required this.itemCount,
    required this.lastLoadedAt,
  });

  final String title;
  final String? subtitle;
  final int itemCount;
  final DateTime? lastLoadedAt;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: CupertinoColors.secondarySystemGroupedBackground,
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
                style: const TextStyle(
                  fontSize: 13,
                  color: CupertinoColors.systemGrey,
                ),
              ),
            ],
            const SizedBox(height: 10),
            Text(
              '$itemCount articles${lastLoadedAt == null ? '' : '  |  Updated ${_formatTime(lastLoadedAt!)}'}',
              style: const TextStyle(
                fontSize: 12,
                color: CupertinoColors.systemGrey2,
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
          color: CupertinoColors.secondarySystemGroupedBackground,
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
                        style: const TextStyle(
                          fontSize: 12,
                          color: CupertinoColors.systemGrey,
                        ),
                      ),
                    ],
                    if (article.summary.trim().isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Text(
                        _plainTextPreview(article.summary, 180),
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 13,
                          color: CupertinoColors.label,
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
                style: const TextStyle(
                  fontSize: 13,
                  color: CupertinoColors.systemGrey,
                ),
              ),
            ],
            if (article.link != null && article.link!.isNotEmpty) ...[
              const SizedBox(height: 12),
              DecoratedBox(
                decoration: BoxDecoration(
                  color: CupertinoColors.secondarySystemGroupedBackground,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Link',
                        style: TextStyle(
                          fontSize: 12,
                          color: CupertinoColors.systemGrey,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        article.link!,
                        style: const TextStyle(fontSize: 13),
                      ),
                      const SizedBox(height: 8),
                      CupertinoButton(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                        color: CupertinoColors.activeBlue,
                        borderRadius: BorderRadius.circular(10),
                        onPressed: () {
                          Clipboard.setData(
                            ClipboardData(text: article.link!),
                          );
                          showCupertinoDialog<void>(
                            context: context,
                            builder: (context) => CupertinoAlertDialog(
                              title: const Text('Copied'),
                              content: const Text('Article link copied to clipboard.'),
                              actions: [
                                CupertinoDialogAction(
                                  onPressed: () => Navigator.of(context).pop(),
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
                ),
              ),
            ],
            const SizedBox(height: 16),
            Text(
              article.summary.trim().isEmpty
                  ? 'No description provided by the feed.'
                  : _plainText(article.summary),
              style: const TextStyle(fontSize: 15, height: 1.35),
            ),
          ],
        ),
      ),
    );
  }
}

class RssRepository {
  static Future<FeedLoadResult> fetch(Uri uri) async {
    final response = await http.get(
      uri,
      headers: const {
        'User-Agent': 'rss-reader-cupertino/0.1 (+flutter)',
        'Accept': 'application/rss+xml, application/xml, text/xml;q=0.9, */*;q=0.8',
      },
    );

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('HTTP ${response.statusCode} while loading feed.');
    }

    late final RssFeed feed;
    try {
      feed = RssFeed.parse(response.body);
    } catch (_) {
      throw Exception('Failed to parse RSS feed.');
    }

    final items = feed.items ?? const <RssItem>[];
    final articles = items.map((item) {
      final title = (item.title ?? '').trim();
      final description = (item.description ?? '').trim();
      return FeedArticle(
        title: title.isEmpty ? 'Untitled article' : title,
        summary: description,
        link: item.link?.trim(),
        publishedLabel: item.pubDate?.trim(),
      );
    }).toList();

    return FeedLoadResult(
      title: (feed.title ?? '').trim().isEmpty ? 'RSS Feed' : feed.title!.trim(),
      description: feed.description?.trim(),
      articles: articles,
    );
  }
}

class FeedLoadResult {
  const FeedLoadResult({
    required this.title,
    required this.description,
    required this.articles,
  });

  final String title;
  final String? description;
  final List<FeedArticle> articles;
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
      .replaceAll('&#39;', "'")
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
}

String _formatTime(DateTime dateTime) {
  final hour = dateTime.hour.toString().padLeft(2, '0');
  final minute = dateTime.minute.toString().padLeft(2, '0');
  return '$hour:$minute';
}
