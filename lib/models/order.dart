import 'dart:math' as math;

enum OrderStatus { waitingCarrier, waitingDelivery, completed, cancelled }

/// Model đại diện cho một vị trí địa lý
class Location {
  const Location({
    required this.latitude,
    required this.longitude,
    this.address,
  });

  final double latitude;
  final double longitude;
  final String?
  address; // Địa chỉ con người đọc được (e.g., "123 Nguyễn Huệ, Q1, HCM")

  /// Chuyển đổi từ Map (Firestore) thành Location
  factory Location.fromMap(Map<String, dynamic> map) {
    return Location(
      latitude: (map['latitude'] as num).toDouble(),
      longitude: (map['longitude'] as num).toDouble(),
      address: map['address'] as String?,
    );
  }

  /// Chuyển đổi Location thành Map (để lưu Firestore)
  Map<String, dynamic> toMap() {
    return {'latitude': latitude, 'longitude': longitude, 'address': address};
  }

  /// Tính khoảng cách giữa 2 vị trí (theo Haversine formula)
  double distanceTo(Location other) {
    const earthRadius = 6371; // Km
    final lat1Rad = _toRad(latitude);
    final lat2Rad = _toRad(other.latitude);
    final deltaLatRad = _toRad(other.latitude - latitude);
    final deltaLngRad = _toRad(other.longitude - longitude);

    final a =
        (1 - math.cos(deltaLatRad)) / 2 +
        math.cos(lat1Rad) * math.cos(lat2Rad) * (1 - math.cos(deltaLngRad)) / 2;
    final c = 2 * math.asin(math.sqrt(a.clamp(0, 1)));
    return earthRadius * c;
  }

  static double _toRad(double degree) => degree * 3.14159265359 / 180;

  @override
  String toString() => 'Location($latitude, $longitude, $address)';
}

class DeliveryOrder {
  const DeliveryOrder({
    required this.id,
    required this.title,
    required this.description,
    required this.imageUrl,
    required this.senderId,
    required this.receiverId,
    required this.senderLocation,
    required this.receiverLocation,
    required this.createdBy,
    required this.status,
    required this.createdAt,
    required this.deadlineAt,
    this.carrierId,
    this.pickupLocation,
    this.deliveryLocation,
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
  final Location senderLocation; // Vị trí người gửi A
  final Location receiverLocation; // Vị trí người nhận B
  final String? carrierId;
  final Location? pickupLocation; // Vị trí lấy hàng thực tế (C lấy từ A)
  final Location? deliveryLocation; // Vị trí giao hàng thực tế (C giao cho B)
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
    Location? senderLocation,
    Location? receiverLocation,
    String? carrierId,
    bool clearCarrier = false,
    Location? pickupLocation,
    Location? deliveryLocation,
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
      senderLocation: senderLocation ?? this.senderLocation,
      receiverLocation: receiverLocation ?? this.receiverLocation,
      carrierId: clearCarrier ? null : (carrierId ?? this.carrierId),
      pickupLocation: pickupLocation ?? this.pickupLocation,
      deliveryLocation: deliveryLocation ?? this.deliveryLocation,
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
