import 'package:flutter/material.dart';

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

class OrderCard extends StatelessWidget {
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
  final List<OrderCardAction> actions;

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
                          color: statusColor.withAlpha(30),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(statusIcon, size: 14, color: statusColor),
                            const SizedBox(width: 6),
                            Text(
                              statusText,
                              style: Theme.of(context).textTheme.labelSmall
                                  ?.copyWith(
                                    color: statusColor,
                                    fontWeight: FontWeight.w700,
                                    letterSpacing: 0.2,
                                  ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        title,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        description,
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          const Icon(Icons.schedule, size: 18),
                          const SizedBox(width: 6),
                          Text(
                            deadline,
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: SizedBox(
                    width: 72,
                    height: 72,
                    child: Image.network(
                      imageUrl,
                      fit: BoxFit.cover,
                      errorBuilder: (context, error, stackTrace) {
                        return ColoredBox(
                          color: colorScheme.surfaceContainerHighest,
                          child: Center(
                            child: Text(
                              'Ảnh lỗi',
                              style: Theme.of(context).textTheme.labelSmall,
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ),
              ],
            ),
            if (summaryText != null && summaryText!.trim().isNotEmpty) ...[
              const SizedBox(height: 12),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: (summaryColor ?? colorScheme.secondary).withAlpha(26),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      summaryIcon,
                      size: 18,
                      color: summaryColor ?? colorScheme.secondary,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        summaryText!,
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
            if (actions.isNotEmpty) ...[
              const SizedBox(height: 14),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                alignment: WrapAlignment.end,
                children: actions.map((action) {
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
