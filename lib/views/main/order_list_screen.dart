import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';

import '../../models/order.dart';
import '../../providers/order_provider.dart';
import '../../services/firestore_service.dart';
import '../../services/location_service.dart';
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

class _CancelOrderDialog extends StatefulWidget {
  const _CancelOrderDialog({required this.orderId});

  final String orderId;

  @override
  State<_CancelOrderDialog> createState() => _CancelOrderDialogState();
}

class _CancelOrderDialogState extends State<_CancelOrderDialog> {
  final TextEditingController _reasonController = TextEditingController();

  @override
  void dispose() {
    _reasonController.dispose();
    super.dispose();
  }

  void _submitReason() {
    final reason = _reasonController.text.trim();
    if (reason.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Vui lòng nhập lý do hủy đơn.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    Navigator.of(context).pop(reason);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Hủy đơn'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Bạn có chắc chắn muốn hủy đơn ${widget.orderId}?'),
            const SizedBox(height: 12),
            TextField(
              controller: _reasonController,
              minLines: 2,
              maxLines: 4,
              textInputAction: TextInputAction.newline,
              decoration: const InputDecoration(
                labelText: 'Lý do hủy đơn',
                hintText: 'Nhập lý do hủy đơn',
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(null),
          child: const Text('Không'),
        ),
        FilledButton.tonal(
          onPressed: _submitReason,
          child: const Text('Xác nhận hủy'),
        ),
      ],
    );
  }
}

class OrderListScreen extends StatefulWidget {
  const OrderListScreen({
    super.key,
    required this.orderService,
    required this.userSessionService,
    this.onOpenChat,
  });

  final OrderService orderService;
  final UserSessionService userSessionService;
  final Future<void> Function(String roomId)? onOpenChat;

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
  final FirestoreService _firestoreService = FirestoreService();

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: _tabs.length, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
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

  String _buildCountdownText(DeliveryOrder order, DateTime now) {
    if (order.status == OrderStatus.completed) {
      return 'Đã hoàn thành';
    }
    if (order.status == OrderStatus.cancelled) {
      return 'Đã hủy';
    }

    final diff = order.deadlineAt.difference(now);
    if (diff.isNegative) {
      final overdue = now.difference(order.deadlineAt);
      final hours = overdue.inHours;
      final minutes = overdue.inMinutes.remainder(60);
      return 'Quá hạn ${hours.toString().padLeft(2, '0')}:${minutes.toString().padLeft(2, '0')}';
    }

    final hours = diff.inHours;
    final minutes = diff.inMinutes.remainder(60);
    final seconds = diff.inSeconds.remainder(60);
    return 'Còn ${hours.toString().padLeft(2, '0')}:${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
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

  String _formatLocationForCard(Location location) {
    final address = location.address?.trim();
    if (address != null && address.isNotEmpty) {
      return address;
    }
    return '${location.latitude.toStringAsFixed(5)}, ${location.longitude.toStringAsFixed(5)}';
  }

  String _buildRouteDetails(DeliveryOrder order) {
    final fromLabel = _formatLocationForCard(order.senderLocation);
    final toLabel = _formatLocationForCard(order.receiverLocation);
    final distanceKm = order.senderLocation.distanceTo(order.receiverLocation);

    return 'Lấy hàng: $fromLabel\n'
        'Giao hàng: $toLabel\n'
        'Khoảng cách dự kiến: ${distanceKm.toStringAsFixed(2)} km';
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

  String? _buildCancelReasonText(DeliveryOrder order) {
    if (order.status != OrderStatus.cancelled) {
      return null;
    }

    final reason = order.cancelReason?.trim();
    if (reason == null || reason.isEmpty) {
      return 'Lý do hủy: chưa có thông tin.';
    }

    return 'Lý do hủy: $reason';
  }

  Future<void> _acceptOrder(DeliveryOrder order, String currentUserId) async {
    try {
      await context.read<OrderProvider>().acceptOrder(order.id, currentUserId);
      await widget.onOpenChat?.call(order.id);
      _showMessage('Đã nhận đơn thành công.');
    } catch (e) {
      _showMessage('Không thể nhận đơn: $e');
    }
  }

  Future<void> _markDelivered(DeliveryOrder order, String currentUserId) async {
    try {
      await context.read<OrderProvider>().completeOrder(
        order.id,
        currentUserId,
      );
      _showMessage('Đơn đã được đánh dấu hoàn tất.');
    } catch (e) {
      _showMessage('Không thể hoàn tất đơn: $e');
    }
  }

  Future<void> _setDeadline(DeliveryOrder order, String currentUserId) async {
    final now = DateTime.now();
    final fallbackInitial = order.deadlineAt.isAfter(now)
        ? order.deadlineAt
        : now.add(const Duration(hours: 4));
    final firstDate = DateTime(now.year, now.month, now.day);
    final lastDate = DateTime(now.year + 1, now.month, now.day);

    final pickedDate = await showDatePicker(
      context: context,
      initialDate: fallbackInitial,
      firstDate: firstDate,
      lastDate: lastDate,
    );
    if (!mounted || pickedDate == null) {
      return;
    }

    final pickedTime = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(fallbackInitial),
    );
    if (!mounted || pickedTime == null) {
      return;
    }

    final deadlineAt = DateTime(
      pickedDate.year,
      pickedDate.month,
      pickedDate.day,
      pickedTime.hour,
      pickedTime.minute,
    );

    if (!deadlineAt.isAfter(now)) {
      _showMessage('Hạn giao phải lớn hơn thời điểm hiện tại.');
      return;
    }

    try {
      await context.read<OrderProvider>().updateDeadline(
        order.id,
        currentUserId,
        deadlineAt,
      );
      _showMessage('Đã cập nhật hạn giao đến ${_formatDeadline(deadlineAt)}.');
    } catch (e) {
      _showMessage('Không thể đặt hạn giao: $e');
    }
  }

  Future<void> _showRateCarrierDialog(
    DeliveryOrder order,
    String currentUserId,
  ) async {
    final carrierId = order.carrierId?.trim();
    if (carrierId == null || carrierId.isEmpty) {
      _showMessage('Không tìm thấy người trung gian để đánh giá.');
      return;
    }

    int selectedRating = 5;
    final rating = await showDialog<int>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('Đánh giá người giao'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Chọn số sao cho người trung gian đã giao đơn này.',
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<int>(
                      initialValue: selectedRating,
                      decoration: const InputDecoration(labelText: 'Số sao'),
                      items: List.generate(
                        5,
                        (index) => DropdownMenuItem<int>(
                          value: index + 1,
                          child: Text('${index + 1} sao'),
                        ),
                      ),
                      onChanged: (value) {
                        if (value == null) return;
                        setDialogState(() => selectedRating = value);
                      },
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(),
                  child: const Text('Hủy'),
                ),
                FilledButton(
                  onPressed: () =>
                      Navigator.of(dialogContext).pop(selectedRating),
                  child: const Text('Gửi đánh giá'),
                ),
              ],
            );
          },
        );
      },
    );

    if (!mounted || rating == null) {
      return;
    }

    try {
      await _firestoreService.saveRating(
        orderId: order.id,
        ratedUserId: carrierId,
        raterUserId: currentUserId,
        rating: rating.toDouble(),
      );
      _showMessage('Đã gửi đánh giá ${rating.toString()} sao.');
    } catch (e) {
      _showMessage('Không thể gửi đánh giá: $e');
    }
  }

  Future<String?> _showCancelOrderDialog(DeliveryOrder order) async {
    final reason = await showDialog<String?>(
      context: context,
      builder: (dialogContext) {
        return _CancelOrderDialog(orderId: order.id);
      },
    );
    return reason;
  }

  Future<void> _cancelOrder(DeliveryOrder order, String currentUserId) async {
    try {
      final orderProvider = context.read<OrderProvider>();
      final reason = await _showCancelOrderDialog(order);
      if (reason == null) {
        return;
      }

      if (!mounted) {
        return;
      }

      await orderProvider.cancelOrder(order.id, currentUserId, reason: reason);
      _showMessage('Đã hủy đơn thành công.');
    } catch (e) {
      _showMessage('Không thể hủy đơn: $e');
    }
  }

  Future<void> _editOrderLocations(
    DeliveryOrder order,
    String currentUserId,
  ) async {
    final editedResult = await showModalBottomSheet<_OrderLocationEditResult>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => FractionallySizedBox(
        heightFactor: 0.95,
        child: _EditOrderLocationsSheet(
          initialSenderLocation: order.senderLocation,
          initialReceiverLocation: order.receiverLocation,
        ),
      ),
    );

    if (!mounted || editedResult == null) {
      return;
    }

    try {
      await _firestoreService.updateOrderLocations(
        orderId: order.id,
        actorUserId: currentUserId,
        senderLocation: editedResult.senderLocation,
        receiverLocation: editedResult.receiverLocation,
      );
      _showMessage('Đã cập nhật địa chỉ gửi/nhận.');
    } catch (e) {
      _showMessage('Không thể cập nhật địa chỉ: $e');
    }
  }

  List<OrderCardAction> _buildActions(
    DeliveryOrder order,
    OrderPermissions permissions,
    OrderActorFlags actors,
    String currentUserId,
    OrderProvider orderProvider,
  ) {
    final actions = <OrderCardAction>[];

    if (permissions.acceptAction.isVisible) {
      actions.add(
        OrderCardAction(
          label: 'Nhận đơn',
          icon: Icons.how_to_reg_outlined,
          isEnabled:
              permissions.acceptAction.isEnabled &&
              !orderProvider.isOrderBusy(order.id),
          onPressed:
              permissions.acceptAction.isEnabled &&
                  !orderProvider.isOrderBusy(order.id)
              ? () => _acceptOrder(order, currentUserId)
              : null,
        ),
      );
    }

    if (permissions.markDeliveredAction.isVisible) {
      actions.add(
        OrderCardAction(
          label: 'Hoàn tất giao',
          icon: Icons.done_all_outlined,
          isEnabled:
              permissions.markDeliveredAction.isEnabled &&
              !orderProvider.isOrderBusy(order.id),
          onPressed:
              permissions.markDeliveredAction.isEnabled &&
                  !orderProvider.isOrderBusy(order.id)
              ? () => _markDelivered(order, currentUserId)
              : null,
        ),
      );
    }

    final canSetDeadline =
        actors.isCarrier && order.status == OrderStatus.waitingDelivery;
    if (canSetDeadline) {
      actions.add(
        OrderCardAction(
          label: 'Đặt hạn giao',
          icon: Icons.event_available_outlined,
          isEnabled: !orderProvider.isOrderBusy(order.id),
          onPressed: !orderProvider.isOrderBusy(order.id)
              ? () => _setDeadline(order, currentUserId)
              : null,
        ),
      );
    }

    final canRateCarrier =
        order.status == OrderStatus.completed &&
        actors.isReceiver &&
        (order.carrierId?.trim().isNotEmpty ?? false);
    if (canRateCarrier) {
      actions.add(
        OrderCardAction(
          label: 'Đánh giá người giao',
          icon: Icons.star_outline,
          onPressed: () => _showRateCarrierDialog(order, currentUserId),
        ),
      );
    }

    if (permissions.cancelAction.isVisible) {
      actions.add(
        OrderCardAction(
          label: 'Hủy đơn',
          icon: Icons.cancel_outlined,
          isEnabled:
              permissions.cancelAction.isEnabled &&
              !orderProvider.isOrderBusy(order.id),
          isDestructive: true,
          onPressed:
              permissions.cancelAction.isEnabled &&
                  !orderProvider.isOrderBusy(order.id)
              ? () => _cancelOrder(order, currentUserId)
              : null,
        ),
      );
    }

    final canEditLocations =
        order.status == OrderStatus.waitingCarrier &&
        !order.hasCarrier &&
        (actors.isSender || actors.isCreator);

    if (canEditLocations) {
      actions.add(
        OrderCardAction(
          label: 'Sửa địa chỉ',
          icon: Icons.edit_location_alt_outlined,
          onPressed: () => _editOrderLocations(order, currentUserId),
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
    OrderProvider orderProvider,
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
        final cancelReasonText = _buildCancelReasonText(order);
        var summaryText = order.isLate
            ? '${cardMessage.text}\nĐơn trễ hạn. Phí hiện tại: ${order.lateFee}đ'
            : cardMessage.text;
        if (cancelReasonText != null) {
          summaryText = '$summaryText\n$cancelReasonText';
        }

        return OrderCard(
          title: order.title,
          description:
              '${_toFriendlyDescription(order.description)}\n\n${_buildRouteDetails(order)}',
          deadline:
              'Hạn giao: ${_formatDeadline(order.deadlineAt)} (${_buildCountdownText(order, orderProvider.now)})',
          statusText: _tabLabel(order.status),
          statusIcon: _tabIcon(order.status),
          statusColor: _statusColor(order.status, scheme),
          imageUrl: order.imageUrl,
          summaryIcon: cardMessage.icon,
          summaryColor: cardMessage.color,
          summaryText: summaryText,
          actions: _buildActions(
            order,
            permissions,
            actors,
            currentUserId,
            orderProvider,
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final currentUserId = context.watch<UserSessionService>().currentUserId;
    final orderProvider = context.watch<OrderProvider>();

    if (orderProvider.error != null && orderProvider.orders.isEmpty) {
      return Scaffold(
        appBar: AppBar(title: const Text('Đơn hàng')),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Text('Không tải được danh sách đơn: ${orderProvider.error}'),
          ),
        ),
      );
    }

    if (orderProvider.isLoading && orderProvider.orders.isEmpty) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final orders = orderProvider.orders;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Đơn hàng'),
        bottom: TabBar(
          controller: _tabController,
          tabs: _tabs.map((status) => Tab(text: _tabLabel(status))).toList(),
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
                orderProvider,
              ),
            )
            .toList(),
      ),
    );
  }
}

class _OrderLocationEditResult {
  const _OrderLocationEditResult({
    required this.senderLocation,
    required this.receiverLocation,
  });

  final Location senderLocation;
  final Location receiverLocation;
}

class _EditOrderLocationsSheet extends StatefulWidget {
  const _EditOrderLocationsSheet({
    required this.initialSenderLocation,
    required this.initialReceiverLocation,
  });

  final Location initialSenderLocation;
  final Location initialReceiverLocation;

  @override
  State<_EditOrderLocationsSheet> createState() =>
      _EditOrderLocationsSheetState();
}

class _EditOrderLocationsSheetState extends State<_EditOrderLocationsSheet> {
  late Location _senderLocation;
  late Location _receiverLocation;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _senderLocation = widget.initialSenderLocation;
    _receiverLocation = widget.initialReceiverLocation;
  }

  String _formatLocation(Location location) {
    final address = location.address?.trim();
    if (address != null && address.isNotEmpty) {
      return address;
    }
    return '${location.latitude.toStringAsFixed(5)}, ${location.longitude.toStringAsFixed(5)}';
  }

  Future<void> _pickLocation({required bool isSender}) async {
    final initialLocation = isSender ? _senderLocation : _receiverLocation;

    final selected = await showModalBottomSheet<Location>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => FractionallySizedBox(
        heightFactor: 0.95,
        child: _OrderLocationPickerSheet(
          title: isSender ? 'Sửa địa chỉ lấy hàng' : 'Sửa địa chỉ giao hàng',
          initialLocation: initialLocation,
        ),
      ),
    );

    if (!mounted || selected == null) {
      return;
    }

    setState(() {
      if (isSender) {
        _senderLocation = selected;
      } else {
        _receiverLocation = selected;
      }
    });
  }

  void _save() {
    if (_isSaving) {
      return;
    }

    setState(() {
      _isSaving = true;
    });

    Navigator.of(context).pop(
      _OrderLocationEditResult(
        senderLocation: _senderLocation,
        receiverLocation: _receiverLocation,
      ),
    );
  }

  Widget _buildTile({
    required String title,
    required Location value,
    required VoidCallback onPick,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: Theme.of(context).textTheme.labelLarge),
          const SizedBox(height: 6),
          Text(
            _formatLocation(value),
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 4),
          Text(
            'Tọa độ: ${value.latitude.toStringAsFixed(5)}, ${value.longitude.toStringAsFixed(5)}',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 10),
          OutlinedButton.icon(
            onPressed: onPick,
            icon: const Icon(Icons.map_outlined),
            label: const Text('Chọn trên bản đồ'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Sửa địa chỉ đơn hàng')),
      body: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildTile(
              title: 'Địa chỉ lấy hàng',
              value: _senderLocation,
              onPick: () => _pickLocation(isSender: true),
            ),
            const SizedBox(height: 12),
            _buildTile(
              title: 'Địa chỉ giao hàng',
              value: _receiverLocation,
              onPick: () => _pickLocation(isSender: false),
            ),
            const Spacer(),
            FilledButton.icon(
              onPressed: _isSaving ? null : _save,
              icon: const Icon(Icons.save_outlined),
              label: const Text('Lưu địa chỉ mới'),
            ),
          ],
        ),
      ),
    );
  }
}

class _OrderLocationPickerSheet extends StatefulWidget {
  const _OrderLocationPickerSheet({
    required this.title,
    required this.initialLocation,
  });

  final String title;
  final Location initialLocation;

  @override
  State<_OrderLocationPickerSheet> createState() =>
      _OrderLocationPickerSheetState();
}

class _OrderLocationPickerSheetState extends State<_OrderLocationPickerSheet> {
  static const String _tileUrlTemplate =
      'https://tile.openstreetmap.org/{z}/{x}/{y}.png';
  static const double _minZoom = 5.0;
  static const double _maxZoom = 18.0;

  final MapController _mapController = MapController();
  final LocationService _locationService = LocationService();

  late LatLng _selectedPoint;
  late double _currentZoom;
  Timer? _resolveDebounce;
  String? _selectedAddress;
  bool _isResolvingAddress = false;

  @override
  void initState() {
    super.initState();
    _selectedPoint = LatLng(
      widget.initialLocation.latitude,
      widget.initialLocation.longitude,
    );
    _selectedAddress = widget.initialLocation.address;
    _currentZoom = 15;

    if ((_selectedAddress ?? '').trim().isEmpty) {
      _resolveAddress();
    }
  }

  @override
  void dispose() {
    _resolveDebounce?.cancel();
    super.dispose();
  }

  String _fallbackAddress(LatLng point) {
    return '${point.latitude.toStringAsFixed(5)}, ${point.longitude.toStringAsFixed(5)}';
  }

  Future<void> _resolveAddress() async {
    final target = _selectedPoint;
    setState(() {
      _isResolvingAddress = true;
    });

    final location = await _locationService.getLocationFromCoordinates(
      target.latitude,
      target.longitude,
    );

    if (!mounted) {
      return;
    }

    final unchanged =
        (target.latitude - _selectedPoint.latitude).abs() < 0.000001 &&
        (target.longitude - _selectedPoint.longitude).abs() < 0.000001;

    if (!unchanged) {
      return;
    }

    setState(() {
      _isResolvingAddress = false;
      _selectedAddress = location?.address;
    });
  }

  void _scheduleResolveAddress() {
    _resolveDebounce?.cancel();
    _resolveDebounce = Timer(
      const Duration(milliseconds: 600),
      _resolveAddress,
    );
  }

  void _onPositionChanged(MapPosition position, bool hasGesture) {
    final center = position.center;
    if (center == null) {
      return;
    }

    final zoom = (position.zoom ?? _currentZoom).clamp(_minZoom, _maxZoom);
    final changed =
        (center.latitude - _selectedPoint.latitude).abs() > 0.0000001 ||
        (center.longitude - _selectedPoint.longitude).abs() > 0.0000001;

    setState(() {
      _selectedPoint = center;
      _currentZoom = zoom;
      if (changed) {
        _selectedAddress = null;
      }
    });

    if (changed) {
      _scheduleResolveAddress();
    }
  }

  void _zoomBy(double delta) {
    final center = _mapController.camera.center;
    final zoom = (_currentZoom + delta).clamp(_minZoom, _maxZoom);
    _mapController.move(center, zoom);
  }

  void _confirm() {
    Navigator.of(context).pop(
      Location(
        latitude: _selectedPoint.latitude,
        longitude: _selectedPoint.longitude,
        address: _selectedAddress ?? _fallbackAddress(_selectedPoint),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final addressLabel =
        (_selectedAddress != null && _selectedAddress!.trim().isNotEmpty)
        ? _selectedAddress!
        : _fallbackAddress(_selectedPoint);

    return Scaffold(
      appBar: AppBar(title: Text(widget.title)),
      body: Column(
        children: [
          Expanded(
            child: Stack(
              fit: StackFit.expand,
              children: [
                FlutterMap(
                  mapController: _mapController,
                  options: MapOptions(
                    initialCenter: _selectedPoint,
                    initialZoom: _currentZoom,
                    minZoom: _minZoom,
                    maxZoom: _maxZoom,
                    onPositionChanged: _onPositionChanged,
                  ),
                  children: [
                    TileLayer(
                      urlTemplate: _tileUrlTemplate,
                      userAgentPackageName: 'com.example.unisend',
                      tileProvider: NetworkTileProvider(
                        headers: {'User-Agent': 'UniSend/1.0'},
                      ),
                    ),
                    const SimpleAttributionWidget(
                      source: Text('© OpenStreetMap contributors'),
                      alignment: Alignment.bottomLeft,
                    ),
                  ],
                ),
                IgnorePointer(
                  child: Center(
                    child: Transform.translate(
                      offset: const Offset(0, -18),
                      child: const Icon(
                        Icons.location_pin,
                        size: 52,
                        color: Colors.red,
                      ),
                    ),
                  ),
                ),
                Positioned(
                  top: 12,
                  right: 12,
                  child: Material(
                    color: Theme.of(context).colorScheme.surface.withAlpha(225),
                    borderRadius: BorderRadius.circular(12),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          onPressed: () => _zoomBy(1),
                          icon: const Icon(Icons.add),
                          tooltip: 'Phóng to',
                        ),
                        IconButton(
                          onPressed: () => _zoomBy(-1),
                          icon: const Icon(Icons.remove),
                          tooltip: 'Thu nhỏ',
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surface,
              border: Border(
                top: BorderSide(
                  color: Theme.of(context).colorScheme.outlineVariant,
                ),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _isResolvingAddress ? 'Đang lấy địa chỉ...' : addressLabel,
                ),
                const SizedBox(height: 8),
                Text(
                  'Kéo bản đồ để chọn điểm. Ghim đỏ ở giữa chính là vị trí sẽ lưu.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 10),
                FilledButton.icon(
                  onPressed: _confirm,
                  icon: const Icon(Icons.check_circle_outline),
                  label: const Text('Dùng vị trí này'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
