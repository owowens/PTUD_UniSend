enum OrderStatus { waitingCarrier, waitingDelivery, completed, cancelled }

class DeliveryOrder {
  const DeliveryOrder({
    required this.id,
    required this.title,
    required this.description,
    required this.imageUrl,
    required this.senderId,
    required this.receiverId,
    required this.createdBy,
    required this.status,
    required this.createdAt,
    required this.deadlineAt,
    this.carrierId,
    this.canAccept,
    this.canMarkDelivered,
    this.canCancel,
    this.acceptDeniedReason,
    this.markDeliveredDeniedReason,
    this.cancelDeniedReason,
  });

  final String id;
  final String title;
  final String description;
  final String imageUrl;
  final String senderId;
  final String receiverId;
  final String? carrierId;
  final String createdBy;
  final OrderStatus status;
  final DateTime createdAt;
  final DateTime deadlineAt;
  final bool? canAccept;
  final bool? canMarkDelivered;
  final bool? canCancel;
  final String? acceptDeniedReason;
  final String? markDeliveredDeniedReason;
  final String? cancelDeniedReason;

  bool get hasCarrier => carrierId != null && carrierId!.trim().isNotEmpty;

  DeliveryOrder copyWith({
    String? title,
    String? description,
    String? imageUrl,
    String? senderId,
    String? receiverId,
    String? carrierId,
    bool clearCarrier = false,
    String? createdBy,
    OrderStatus? status,
    DateTime? createdAt,
    DateTime? deadlineAt,
    bool? canAccept,
    bool? canMarkDelivered,
    bool? canCancel,
    String? acceptDeniedReason,
    String? markDeliveredDeniedReason,
    String? cancelDeniedReason,
  }) {
    return DeliveryOrder(
      id: id,
      title: title ?? this.title,
      description: description ?? this.description,
      imageUrl: imageUrl ?? this.imageUrl,
      senderId: senderId ?? this.senderId,
      receiverId: receiverId ?? this.receiverId,
      carrierId: clearCarrier ? null : (carrierId ?? this.carrierId),
      createdBy: createdBy ?? this.createdBy,
      status: status ?? this.status,
      createdAt: createdAt ?? this.createdAt,
      deadlineAt: deadlineAt ?? this.deadlineAt,
      canAccept: canAccept ?? this.canAccept,
      canMarkDelivered: canMarkDelivered ?? this.canMarkDelivered,
      canCancel: canCancel ?? this.canCancel,
      acceptDeniedReason: acceptDeniedReason ?? this.acceptDeniedReason,
      markDeliveredDeniedReason:
          markDeliveredDeniedReason ?? this.markDeliveredDeniedReason,
      cancelDeniedReason: cancelDeniedReason ?? this.cancelDeniedReason,
    );
  }
}

class OrderActorFlags {
  const OrderActorFlags({
    required this.isSender,
    required this.isReceiver,
    required this.isCarrier,
    required this.isCreator,
  });

  final bool isSender;
  final bool isReceiver;
  final bool isCarrier;
  final bool isCreator;

  bool get isParticipant => isSender || isReceiver || isCarrier;
}

class OrderPermissions {
  const OrderPermissions({
    required this.acceptAction,
    required this.markDeliveredAction,
    required this.cancelAction,
  });

  final OrderActionConstraint acceptAction;
  final OrderActionConstraint markDeliveredAction;
  final OrderActionConstraint cancelAction;

  bool get hasAnyVisibleAction =>
      acceptAction.isVisible ||
      markDeliveredAction.isVisible ||
      cancelAction.isVisible;

  bool get hasAnyEnabledAction =>
      acceptAction.isEnabled ||
      markDeliveredAction.isEnabled ||
      cancelAction.isEnabled;
}

class OrderActionConstraint {
  const OrderActionConstraint({
    required this.isVisible,
    required this.isEnabled,
    this.deniedReason,
  });

  final bool isVisible;
  final bool isEnabled;
  final String? deniedReason;
}

class OrderPolicy {
  static OrderActorFlags resolveActors({
    required DeliveryOrder order,
    required String currentUserId,
  }) {
    final normalizedCurrentUserId = currentUserId.trim();

    bool isSameUser(String? userId) {
      if (normalizedCurrentUserId.isEmpty || userId == null) {
        return false;
      }
      return userId.trim() == normalizedCurrentUserId;
    }

    return OrderActorFlags(
      isSender: isSameUser(order.senderId),
      isReceiver: isSameUser(order.receiverId),
      isCarrier: isSameUser(order.carrierId),
      isCreator: isSameUser(order.createdBy),
    );
  }

  static OrderPermissions resolvePermissions({
    required DeliveryOrder order,
    required String currentUserId,
  }) {
    final actors = resolveActors(order: order, currentUserId: currentUserId);
    final bool canAcceptByRole =
        !actors.isSender && !actors.isReceiver && !actors.isCarrier;
    final bool canAcceptByStatus = order.status == OrderStatus.waitingCarrier;
    final bool canAcceptByBackend = order.canAccept ?? true;

    final acceptAction = OrderActionConstraint(
      isVisible: canAcceptByRole && canAcceptByStatus,
      isEnabled: canAcceptByRole && canAcceptByStatus && canAcceptByBackend,
      deniedReason: canAcceptByRole && canAcceptByStatus && !canAcceptByBackend
          ? (order.acceptDeniedReason ?? 'Hệ thống chưa cho phép nhận đơn này.')
          : null,
    );

    final bool canMarkDeliveredByRole = actors.isCarrier;
    final bool canMarkDeliveredByStatus =
        order.status == OrderStatus.waitingDelivery;
    final bool canMarkDeliveredByBackend = order.canMarkDelivered ?? true;

    final markDeliveredAction = OrderActionConstraint(
      isVisible: canMarkDeliveredByRole && canMarkDeliveredByStatus,
      isEnabled:
          canMarkDeliveredByRole &&
          canMarkDeliveredByStatus &&
          canMarkDeliveredByBackend,
      deniedReason:
          canMarkDeliveredByRole &&
              canMarkDeliveredByStatus &&
              !canMarkDeliveredByBackend
          ? (order.markDeliveredDeniedReason ??
                'Hệ thống chưa cho phép hoàn tất đơn này.')
          : null,
    );

    final bool canCancelByRole =
        actors.isSender ||
        actors.isReceiver ||
        actors.isCarrier ||
        actors.isCreator;
    final bool canCancelByStatus =
        order.status == OrderStatus.waitingCarrier ||
        order.status == OrderStatus.waitingDelivery;
    final bool canCancelByBackend = order.canCancel ?? true;

    final cancelAction = OrderActionConstraint(
      isVisible: canCancelByRole && canCancelByStatus,
      isEnabled: canCancelByRole && canCancelByStatus && canCancelByBackend,
      deniedReason: canCancelByRole && canCancelByStatus && !canCancelByBackend
          ? (order.cancelDeniedReason ?? 'Hệ thống từ chối yêu cầu hủy đơn.')
          : null,
    );

    return OrderPermissions(
      acceptAction: acceptAction,
      markDeliveredAction: markDeliveredAction,
      cancelAction: cancelAction,
    );
  }
}
