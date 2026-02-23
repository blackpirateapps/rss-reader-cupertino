part of ../main.dart;

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

