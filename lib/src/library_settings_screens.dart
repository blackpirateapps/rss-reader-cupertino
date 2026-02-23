part of 'package:rss_reader_cupertino/main.dart';

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
                        title: 'Bookmarked Articles',
                        subtitle:
                            '${controller.bookmarkedArticles.length} saved locally',
                        onTap: controller.bookmarkedArticles.isEmpty
                            ? null
                            : controller.clearBookmarkedArticles,
                        trailing: controller.bookmarkedArticles.isEmpty
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
                        value: 'Preview + Reader + WebView',
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

class BookmarksScreen extends StatelessWidget {
  const BookmarksScreen({super.key, required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final bookmarks = controller.bookmarkedArticles;
        return CupertinoPageScaffold(
          navigationBar: CupertinoNavigationBar(
            middle: const Text('Saved'),
            trailing: bookmarks.isEmpty
                ? null
                : CupertinoButton(
                    padding: EdgeInsets.zero,
                    minimumSize: const Size.square(28),
                    onPressed: () => _confirm(
                      context,
                      title: 'Clear Saved Articles',
                      message: 'Remove all bookmarked articles?',
                      confirmLabel: 'Clear',
                      onConfirm: controller.clearBookmarkedArticles,
                    ),
                    child: const Text('Clear'),
                  ),
          ),
          child: SafeArea(
            child: bookmarks.isEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(
                        'Saved articles will appear here after tapping Save in an article.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: _secondaryLabelColor(context),
                          fontSize: 15,
                        ),
                      ),
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
                    itemCount: bookmarks.length,
                    itemBuilder: (context, index) {
                      final entry = bookmarks[index];
                      return Padding(
                        padding: EdgeInsets.only(
                          bottom: index == bookmarks.length - 1 ? 0 : 8,
                        ),
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: _cardColor(context),
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: _borderColor(context)),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.all(12),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(
                                  child: GestureDetector(
                                    onTap: () {
                                      final article = entry.toFeedArticle();
                                      controller.markArticleRead(
                                        _articleReadKey(article),
                                      );
                                      controller.recordArticle(
                                        ArticleHistoryEntry(
                                          title: article.title,
                                          link: article.link,
                                          summary: article.summary,
                                          publishedLabel: article.publishedLabel,
                                          feedTitle: article.sourceTitle,
                                          openedAt: DateTime.now(),
                                        ),
                                      );
                                      Navigator.of(context).push(
                                        CupertinoPageRoute<void>(
                                          builder: (_) => ArticleScreen(article: article),
                                        ),
                                      );
                                    },
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          entry.title,
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(
                                            fontSize: 16,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                        const SizedBox(height: 6),
                                        Text(
                                          [
                                            if ((entry.feedTitle ?? '').trim().isNotEmpty)
                                              entry.feedTitle!.trim(),
                                            'Saved ${_formatDateTime(entry.savedAt)}',
                                          ].join('  |  '),
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(
                                            fontSize: 12,
                                            color: _secondaryLabelColor(context),
                                          ),
                                        ),
                                        if (entry.summary.trim().isNotEmpty) ...[
                                          const SizedBox(height: 8),
                                          Text(
                                            _plainTextPreview(entry.summary, 180),
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
                                ),
                                const SizedBox(width: 8),
                                CupertinoButton(
                                  padding: EdgeInsets.zero,
                                  minimumSize: const Size.square(28),
                                  onPressed: () => controller.removeBookmarkedArticle(
                                    entry.bookmarkKey,
                                  ),
                                  child: const Icon(
                                    CupertinoIcons.delete_solid,
                                    color: CupertinoColors.systemRed,
                                    size: 18,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  ),
          ),
        );
      },
    );
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
