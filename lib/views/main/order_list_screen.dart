import 'package:flutter/material.dart';

import '../../models/order.dart';
import '../../services/order_service.dart';
import '../../services/user_session_service.dart';
import '../../widgets/common/order_card.dart';

class _OrderCardMessage {
  const _OrderCardMessage({
    required this.text,
    required this.icon,
    required this.color,
  });

  final String text;
  final IconData icon;
  final Color color;
}

class OrderListScreen extends StatefulWidget {
  const OrderListScreen({
    super.key,
    required this.orderService,
    required this.userSessionService,
  });

  final OrderService orderService;
  final UserSessionService userSessionService;

  @override
  State<OrderListScreen> createState() => _OrderListScreenState();
}

class _OrderListScreenState extends State<OrderListScreen>
    with SingleTickerProviderStateMixin {
  static const List<OrderStatus> _tabs = <OrderStatus>[
    OrderStatus.waitingCarrier,
    OrderStatus.waitingDelivery,
    OrderStatus.completed,
    OrderStatus.cancelled,
  ];

  late final TabController _tabController;
  final TextEditingController _switchUserController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: _tabs.length, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    _switchUserController.dispose();
    super.dispose();
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
    );
  }

  Future<void> _showSwitchUserDialog(String currentUserId) async {
    _switchUserController.text = currentUserId;

    final knownIds =
        widget.orderService.knownUserIds(currentUserId: currentUserId).toList()
          ..sort();

    await showDialog<void>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Đổi tài khoản xem thử'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: _switchUserController,
                  decoration: const InputDecoration(labelText: 'Mã tài khoản'),
                ),
                const SizedBox(height: 12),
                Text(
                  'Gợi ý từ danh sách đơn:',
                  style: Theme.of(context).textTheme.labelLarge,
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: knownIds
                      .map(
                        (id) => ActionChip(
                          label: Text(id),
                          onPressed: () {
                            _switchUserController.text = id;
                          },
                        ),
                      )
                      .toList(),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Đóng'),
            ),
            FilledButton(
              onPressed: () {
                final newUserId = _switchUserController.text.trim();
                if (newUserId.isEmpty) {
                  _showMessage('Mã tài khoản không được để trống.');
                  return;
                }
                widget.userSessionService.setCurrentUserId(newUserId);
                Navigator.of(context).pop();
              },
              child: const Text('Áp dụng'),
            ),
          ],
        );
      },
    );
  }

  String _tabLabel(OrderStatus status) {
    switch (status) {
      case OrderStatus.waitingCarrier:
        return 'Chờ nhận đơn';
      case OrderStatus.waitingDelivery:
        return 'Chờ giao hàng';
      case OrderStatus.completed:
        return 'Hoàn thành';
      case OrderStatus.cancelled:
        return 'Đã hủy';
    }
  }

  IconData _tabIcon(OrderStatus status) {
    switch (status) {
      case OrderStatus.waitingCarrier:
        return Icons.hourglass_empty_outlined;
      case OrderStatus.waitingDelivery:
        return Icons.local_shipping_outlined;
      case OrderStatus.completed:
        return Icons.check_circle_outline;
      case OrderStatus.cancelled:
        return Icons.cancel_outlined;
    }
  }

  Color _statusColor(OrderStatus status, ColorScheme scheme) {
    switch (status) {
      case OrderStatus.waitingCarrier:
        return scheme.primary;
      case OrderStatus.waitingDelivery:
        return scheme.tertiary;
      case OrderStatus.completed:
        return Colors.green.shade700;
      case OrderStatus.cancelled:
        return scheme.error;
    }
  }

  String _formatDeadline(DateTime deadlineAt) {
    final day = deadlineAt.day.toString().padLeft(2, '0');
    final month = deadlineAt.month.toString().padLeft(2, '0');
    final year = deadlineAt.year;
    final hour = deadlineAt.hour.toString().padLeft(2, '0');
    final minute = deadlineAt.minute.toString().padLeft(2, '0');
    return '$day/$month/$year $hour:$minute';
  }

  String _toFriendlyDescription(String rawDescription) {
    final cleaned = rawDescription
        .replaceAll(
          RegExp(
            r'\b(created_by|sender_id|receiver_id|carrier_id|current_user)\b',
            caseSensitive: false,
          ),
          '',
        )
        .replaceAll(RegExp(r'\s{2,}'), ' ')
        .trim();

    if (cleaned.isEmpty) {
      return 'Thông tin đơn hàng.';
    }

    return cleaned;
  }

  String? _firstDeniedReason(OrderPermissions permissions) {
    final constraints = <OrderActionConstraint>[
      permissions.acceptAction,
      permissions.markDeliveredAction,
      permissions.cancelAction,
    ];

    for (final constraint in constraints) {
      final reason = constraint.deniedReason?.trim();
      if (constraint.isVisible &&
          !constraint.isEnabled &&
          reason != null &&
          reason.isNotEmpty) {
        return reason;
      }
    }

    return null;
  }

  _OrderCardMessage _buildPrimaryMessage({
    required DeliveryOrder order,
    required OrderActorFlags actors,
    required OrderPermissions permissions,
    required ColorScheme scheme,
  }) {
    final deniedReason = _firstDeniedReason(permissions);
    if (deniedReason != null) {
      return _OrderCardMessage(
        text: deniedReason,
        icon: Icons.info_outline_rounded,
        color: scheme.error,
      );
    }

    switch (order.status) {
      case OrderStatus.waitingCarrier:
        if (actors.isSender) {
          return _OrderCardMessage(
            text: 'Đơn của bạn đang chờ người nhận giao.',
            icon: Icons.hourglass_top_rounded,
            color: scheme.primary,
          );
        }
        if (actors.isCreator && !actors.isSender) {
          return _OrderCardMessage(
            text: 'Đơn tạo hộ đang chờ người nhận giao.',
            icon: Icons.person_add_alt_1_rounded,
            color: scheme.primary,
          );
        }
        if (permissions.acceptAction.isVisible &&
            permissions.acceptAction.isEnabled) {
          return _OrderCardMessage(
            text: 'Bạn có thể nhận đơn này.',
            icon: Icons.how_to_reg_rounded,
            color: scheme.primary,
          );
        }
        return _OrderCardMessage(
          text: 'Đơn đang chờ người nhận giao.',
          icon: Icons.hourglass_top_rounded,
          color: scheme.primary,
        );
      case OrderStatus.waitingDelivery:
        if (actors.isCarrier) {
          return _OrderCardMessage(
            text: 'Bạn đang giao đơn này.',
            icon: Icons.local_shipping_rounded,
            color: scheme.tertiary,
          );
        }
        if (actors.isReceiver) {
          return _OrderCardMessage(
            text: 'Đơn đang trên đường đến bạn.',
            icon: Icons.inbox_rounded,
            color: scheme.tertiary,
          );
        }
        if (actors.isSender || actors.isCreator) {
          return _OrderCardMessage(
            text: 'Đơn của bạn đang được giao.',
            icon: Icons.route_rounded,
            color: scheme.tertiary,
          );
        }
        return _OrderCardMessage(
          text: 'Đơn đang được giao.',
          icon: Icons.local_shipping_rounded,
          color: scheme.tertiary,
        );
      case OrderStatus.completed:
        return _OrderCardMessage(
          text: 'Đơn đã hoàn tất.',
          icon: Icons.check_circle_rounded,
          color: Colors.green.shade700,
        );
      case OrderStatus.cancelled:
        return _OrderCardMessage(
          text: 'Đơn đã hủy.',
          icon: Icons.cancel_rounded,
          color: scheme.error,
        );
    }
  }

  List<OrderCardAction> _buildActions(
    DeliveryOrder order,
    OrderPermissions permissions,
    String currentUserId,
  ) {
    final actions = <OrderCardAction>[];

    if (permissions.acceptAction.isVisible) {
      actions.add(
        OrderCardAction(
          label: 'Nhận đơn',
          icon: Icons.how_to_reg_outlined,
          isEnabled: permissions.acceptAction.isEnabled,
          onPressed: permissions.acceptAction.isEnabled
              ? () {
                  final result = widget.orderService.acceptOrder(
                    order.id,
                    currentUserId,
                  );
                  _showMessage(result.message);
                }
              : null,
        ),
      );
    }

    if (permissions.markDeliveredAction.isVisible) {
      actions.add(
        OrderCardAction(
          label: 'Hoàn tất giao',
          icon: Icons.done_all_outlined,
          isEnabled: permissions.markDeliveredAction.isEnabled,
          onPressed: permissions.markDeliveredAction.isEnabled
              ? () {
                  final result = widget.orderService.markDelivered(
                    order.id,
                    currentUserId,
                  );
                  _showMessage(result.message);
                }
              : null,
        ),
      );
    }

    if (permissions.cancelAction.isVisible) {
      actions.add(
        OrderCardAction(
          label: 'Hủy đơn',
          icon: Icons.cancel_outlined,
          isEnabled: permissions.cancelAction.isEnabled,
          isDestructive: true,
          onPressed: permissions.cancelAction.isEnabled
              ? () {
                  final result = widget.orderService.cancelOrder(
                    order.id,
                    currentUserId,
                  );
                  _showMessage(result.message);
                }
              : null,
        ),
      );
    }

    return actions;
  }

  Widget _buildEmptyTab({
    required IconData icon,
    required String title,
    required String description,
  }) {
    final colorScheme = Theme.of(context).colorScheme;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(icon, size: 44, color: colorScheme.primary),
                  const SizedBox(height: 14),
                  Text(
                    title,
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    description,
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildOrderTab(
    BuildContext context,
    List<DeliveryOrder> allOrders,
    OrderStatus status,
    String currentUserId,
  ) {
    final orders = allOrders.where((order) => order.status == status).toList();
    if (orders.isEmpty) {
      return _buildEmptyTab(
        icon: _tabIcon(status),
        title: _tabLabel(status),
        description: 'Chưa có đơn trong trạng thái này.',
      );
    }

    final scheme = Theme.of(context).colorScheme;

    return ListView.separated(
      padding: const EdgeInsets.all(12),
      itemCount: orders.length,
      separatorBuilder: (context, index) => const SizedBox(height: 10),
      itemBuilder: (context, index) {
        final order = orders[index];
        final actors = OrderPolicy.resolveActors(
          order: order,
          currentUserId: currentUserId,
        );
        final permissions = OrderPolicy.resolvePermissions(
          order: order,
          currentUserId: currentUserId,
        );
        final cardMessage = _buildPrimaryMessage(
          order: order,
          actors: actors,
          permissions: permissions,
          scheme: scheme,
        );

        return OrderCard(
          title: order.title,
          description: _toFriendlyDescription(order.description),
          deadline: 'Hạn giao: ${_formatDeadline(order.deadlineAt)}',
          statusText: _tabLabel(order.status),
          statusIcon: _tabIcon(order.status),
          statusColor: _statusColor(order.status, scheme),
          imageUrl: order.imageUrl,
          summaryText: cardMessage.text,
          summaryIcon: cardMessage.icon,
          summaryColor: cardMessage.color,
          actions: _buildActions(order, permissions, currentUserId),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.userSessionService,
      builder: (context, child) {
        final currentUserId = widget.userSessionService.currentUserId;
        return ValueListenableBuilder<List<DeliveryOrder>>(
          valueListenable: widget.orderService.ordersListenable,
          builder: (context, orders, child) {
            return Scaffold(
              appBar: AppBar(
                title: const Text('Đơn hàng'),
                actions: [
                  IconButton(
                    onPressed: () => _showSwitchUserDialog(currentUserId),
                    icon: const Icon(Icons.manage_accounts_outlined),
                    tooltip: 'Đổi người dùng thử nghiệm',
                  ),
                ],
                bottom: TabBar(
                  controller: _tabController,
                  tabs: _tabs
                      .map((status) => Tab(text: _tabLabel(status)))
                      .toList(),
                ),
              ),
              body: TabBarView(
                controller: _tabController,
                children: _tabs
                    .map(
                      (status) => _buildOrderTab(
                        context,
                        orders,
                        status,
                        currentUserId,
                      ),
                    )
                    .toList(),
              ),
            );
          },
        );
      },
    );
  }
}
