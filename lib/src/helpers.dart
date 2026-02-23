part of ../main.dart;

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

String _articleBookmarkKey(FeedArticle article) {
  final link = _nullIfBlank(article.link);
  if (link != null) return 'link:$link';

  final source = _nullIfBlank(article.sourceUrl) ?? _nullIfBlank(article.sourceTitle) ?? '';
  return 'fallback:$source|${article.title}';
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

String _decodeHttpResponseBody(http.Response response) {
  final bytes = response.bodyBytes;
  if (bytes.isEmpty) return '';

  final contentType = (response.headers['content-type'] ?? '').toLowerCase();
  final charsetMatch = RegExp(r'charset=([^;]+)').firstMatch(contentType);
  final charset = charsetMatch?.group(1)?.trim().replaceAll('"', '');
  final encoding = charset == null ? null : Encoding.getByName(charset);
  if (encoding != null) {
    try {
      return encoding.decode(bytes);
    } catch (_) {
      // Fall back below.
    }
  }

  try {
    return utf8.decode(bytes);
  } catch (_) {
    return latin1.decode(bytes);
  }
}

String _buildReaderModeHtmlDocument(
  ReaderModeDocument doc,
  BuildContext context, {
  ReaderModeFontFamily fontFamily = ReaderModeFontFamily.system,
}) {
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
  final readerFontCss = _readerModeFontCss(fontFamily);

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
        font-family: $readerFontCss;
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

String _readerModeFontCss(ReaderModeFontFamily fontFamily) {
  switch (fontFamily) {
    case ReaderModeFontFamily.system:
      return '-apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif';
    case ReaderModeFontFamily.serif:
      return 'Georgia, "Times New Roman", serif';
    case ReaderModeFontFamily.humanist:
      return '"Gill Sans", "Trebuchet MS", sans-serif';
    case ReaderModeFontFamily.mono:
      return '"SFMono-Regular", Menlo, Consolas, monospace';
  }
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
