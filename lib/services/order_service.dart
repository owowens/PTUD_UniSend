import 'package:flutter/foundation.dart';

import '../models/order.dart';

class OrderActionResult {
  const OrderActionResult({required this.success, required this.message});

  final bool success;
  final String message;
}

class OrderService {
  OrderService({List<DeliveryOrder>? initialOrders})
    : _ordersNotifier = ValueNotifier<List<DeliveryOrder>>(
        initialOrders ?? <DeliveryOrder>[],
      );

  final ValueNotifier<List<DeliveryOrder>> _ordersNotifier;

  ValueListenable<List<DeliveryOrder>> get ordersListenable => _ordersNotifier;

  List<DeliveryOrder> get orders =>
      List<DeliveryOrder>.unmodifiable(_ordersNotifier.value);

  List<DeliveryOrder> ordersByStatus(OrderStatus status) {
    return orders.where((order) => order.status == status).toList();
  }

  Set<String> knownUserIds({String? currentUserId}) {
    final ids = <String>{
      if (currentUserId != null && currentUserId.trim().isNotEmpty)
        currentUserId.trim(),
    };

    for (final order in orders) {
      ids.add(order.senderId);
      ids.add(order.receiverId);
      ids.add(order.createdBy);
      if (order.carrierId != null && order.carrierId!.trim().isNotEmpty) {
        ids.add(order.carrierId!.trim());
      }
    }

    return ids;
  }

  DeliveryOrder createOrder({
    required String currentUserId,
    required String title,
    required String description,
    required String imageUrl,
    required String senderId,
    required String receiverId,
    DateTime? deadlineAt,
  }) {
    final now = DateTime.now();
    final String normalizedCurrentUserId = currentUserId.trim();
    final String normalizedSenderId = senderId.trim().isEmpty
        ? normalizedCurrentUserId
        : senderId.trim();

    final createdOrder = DeliveryOrder(
      id: 'ORD-${now.millisecondsSinceEpoch}',
      title: title.trim(),
      description: description.trim(),
      imageUrl: imageUrl,
      senderId: normalizedSenderId,
      receiverId: receiverId.trim(),
      carrierId: null,
      createdBy: normalizedCurrentUserId,
      status: OrderStatus.waitingCarrier,
      createdAt: now,
      deadlineAt: deadlineAt ?? now.add(const Duration(hours: 4)),
      canAccept: true,
      canMarkDelivered: false,
      canCancel: true,
    );

    _ordersNotifier.value = <DeliveryOrder>[createdOrder, ...orders];
    return createdOrder;
  }

  OrderActionResult acceptOrder(String orderId, String currentUserId) {
    final index = _findOrderIndex(orderId);
    if (index < 0) {
      return const OrderActionResult(
        success: false,
        message: 'Không tìm thấy đơn để nhận.',
      );
    }

    final order = orders[index];
    final permissions = OrderPolicy.resolvePermissions(
      order: order,
      currentUserId: currentUserId,
    );
    if (!permissions.acceptAction.isVisible) {
      return const OrderActionResult(
        success: false,
        message: 'Bạn không thuộc nhóm được phép nhận đơn này.',
      );
    }

    if (!permissions.acceptAction.isEnabled) {
      return OrderActionResult(
        success: false,
        message:
            permissions.acceptAction.deniedReason ??
            'Hệ thống tạm thời từ chối nhận đơn.',
      );
    }

    _updateOrderAt(
      index,
      order.copyWith(
        carrierId: currentUserId.trim(),
        status: OrderStatus.waitingDelivery,
        canAccept: false,
        canMarkDelivered: true,
        canCancel: true,
        acceptDeniedReason: null,
        markDeliveredDeniedReason: null,
        cancelDeniedReason: null,
      ),
    );
    return const OrderActionResult(
      success: true,
      message: 'Đã nhận đơn thành công.',
    );
  }

  OrderActionResult markDelivered(String orderId, String currentUserId) {
    final index = _findOrderIndex(orderId);
    if (index < 0) {
      return const OrderActionResult(
        success: false,
        message: 'Không tìm thấy đơn để hoàn tất.',
      );
    }

    final order = orders[index];
    final permissions = OrderPolicy.resolvePermissions(
      order: order,
      currentUserId: currentUserId,
    );
    if (!permissions.markDeliveredAction.isVisible) {
      return const OrderActionResult(
        success: false,
        message: 'Bạn không có quyền hoàn tất đơn này.',
      );
    }

    if (!permissions.markDeliveredAction.isEnabled) {
      return OrderActionResult(
        success: false,
        message:
            permissions.markDeliveredAction.deniedReason ??
            'Hệ thống tạm thời từ chối hoàn tất đơn.',
      );
    }

    _updateOrderAt(
      index,
      order.copyWith(
        status: OrderStatus.completed,
        canAccept: false,
        canMarkDelivered: false,
        canCancel: false,
        cancelDeniedReason: 'Đơn đã hoàn thành nên không thể hủy.',
      ),
    );
    return const OrderActionResult(
      success: true,
      message: 'Đơn đã được đánh dấu hoàn tất.',
    );
  }

  OrderActionResult cancelOrder(String orderId, String currentUserId) {
    final index = _findOrderIndex(orderId);
    if (index < 0) {
      return const OrderActionResult(
        success: false,
        message: 'Không tìm thấy đơn để hủy.',
      );
    }

    final order = orders[index];
    final permissions = OrderPolicy.resolvePermissions(
      order: order,
      currentUserId: currentUserId,
    );
    if (!permissions.cancelAction.isVisible) {
      return const OrderActionResult(
        success: false,
        message: 'Bạn không có quyền hủy đơn này.',
      );
    }

    if (!permissions.cancelAction.isEnabled) {
      return OrderActionResult(
        success: false,
        message:
            permissions.cancelAction.deniedReason ??
            'Hệ thống tạm thời từ chối yêu cầu hủy đơn.',
      );
    }

    _updateOrderAt(
      index,
      order.copyWith(
        status: OrderStatus.cancelled,
        canAccept: false,
        canMarkDelivered: false,
        canCancel: false,
      ),
    );
    return const OrderActionResult(
      success: true,
      message: 'Đã hủy đơn thành công.',
    );
  }

  int _findOrderIndex(String orderId) {
    return orders.indexWhere((order) => order.id == orderId);
  }

  void _updateOrderAt(int index, DeliveryOrder updatedOrder) {
    final mutableOrders = orders.toList();
    mutableOrders[index] = updatedOrder;
    _ordersNotifier.value = mutableOrders;
  }
}
