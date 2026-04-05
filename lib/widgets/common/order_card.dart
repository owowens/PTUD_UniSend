import 'package:flutter/material.dart';

import '../../services/storage_service.dart';

class OrderCardAction {
  const OrderCardAction({
    required this.label,
    required this.icon,
    this.onPressed,
    this.isEnabled = true,
    this.isDestructive = false,
  });

  final String label;
  final IconData icon;
  final VoidCallback? onPressed;
  final bool isEnabled;
  final bool isDestructive;
}

class OrderCard extends StatefulWidget {
  const OrderCard({
    super.key,
    required this.title,
    required this.description,
    required this.deadline,
    required this.statusText,
    required this.statusIcon,
    required this.statusColor,
    required this.imageUrl,
    this.summaryText,
    this.summaryIcon = Icons.info_outline_rounded,
    this.summaryColor,
    this.extraContent,
    this.actions = const <OrderCardAction>[],
  });

  final String title;
  final String description;
  final String deadline;
  final String statusText;
  final IconData statusIcon;
  final Color statusColor;
  final String imageUrl;
  final String? summaryText;
  final IconData summaryIcon;
  final Color? summaryColor;
  final Widget? extraContent;
  final List<OrderCardAction> actions;

  @override
  State<OrderCard> createState() => _OrderCardState();
}

class _OrderCardState extends State<OrderCard> {
  final StorageService _storageService = StorageService();
  late Future<String?> _resolvedImageUrlFuture;

  @override
  void initState() {
    super.initState();
    _resolvedImageUrlFuture = _resolveImageUrl();
  }

  @override
  void didUpdateWidget(covariant OrderCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.imageUrl != widget.imageUrl) {
      _resolvedImageUrlFuture = _resolveImageUrl();
    }
  }

  Future<String?> _resolveImageUrl() {
    return _storageService.resolveStoredImageUrl(widget.imageUrl);
  }

  Widget _buildImagePlaceholder(ColorScheme colorScheme) {
    return ColoredBox(
      color: colorScheme.surfaceContainerHighest,
      child: Center(
        child: Icon(
          Icons.image_not_supported_outlined,
          color: colorScheme.onSurfaceVariant,
          size: 26,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Card(
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: widget.statusColor.withAlpha(30),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              widget.statusIcon,
                              size: 14,
                              color: widget.statusColor,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              widget.statusText,
                              style: Theme.of(context).textTheme.labelSmall
                                  ?.copyWith(
                                    color: widget.statusColor,
                                    fontWeight: FontWeight.w700,
                                    letterSpacing: 0.2,
                                  ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        widget.title,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        widget.description,
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          const Icon(Icons.schedule, size: 18),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              widget.deadline,
                              softWrap: true,
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Container(
                  width: 72,
                  height: 72,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: colorScheme.outlineVariant,
                      width: 1.4,
                    ),
                  ),
                  child: ClipOval(
                    child: FutureBuilder<String?>(
                      future: _resolvedImageUrlFuture,
                      builder: (context, snapshot) {
                        final resolvedUrl = snapshot.data?.trim();
                        if (snapshot.connectionState != ConnectionState.done ||
                            resolvedUrl == null ||
                            resolvedUrl.isEmpty) {
                          return _buildImagePlaceholder(colorScheme);
                        }

                        return Image.network(
                          resolvedUrl,
                          fit: BoxFit.cover,
                          errorBuilder: (context, error, stackTrace) {
                            return _buildImagePlaceholder(colorScheme);
                          },
                        );
                      },
                    ),
                  ),
                ),
              ],
            ),
            if (widget.summaryText != null &&
                widget.summaryText!.trim().isNotEmpty) ...[
              const SizedBox(height: 12),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: (widget.summaryColor ?? colorScheme.secondary)
                      .withAlpha(26),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      widget.summaryIcon,
                      size: 18,
                      color: widget.summaryColor ?? colorScheme.secondary,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        widget.summaryText!,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: colorScheme.onSurface,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            if (widget.extraContent != null) ...[
              const SizedBox(height: 12),
              widget.extraContent!,
            ],
            if (widget.actions.isNotEmpty) ...[
              const SizedBox(height: 14),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                alignment: WrapAlignment.end,
                children: widget.actions.map((action) {
                  if (action.isDestructive) {
                    return FilledButton.tonalIcon(
                      onPressed: action.isEnabled ? action.onPressed : null,
                      style: FilledButton.styleFrom(
                        foregroundColor: colorScheme.error,
                      ),
                      icon: Icon(action.icon, size: 18),
                      label: Text(action.label),
                    );
                  }

                  return FilledButton.tonalIcon(
                    onPressed: action.isEnabled ? action.onPressed : null,
                    icon: Icon(action.icon, size: 18),
                    label: Text(action.label),
                  );
                }).toList(),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
