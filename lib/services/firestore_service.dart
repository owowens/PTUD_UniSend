import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import '../models/order.dart';

/// Service quản lý tất cả thao tác Firestore Database
class FirestoreService {
  static bool get isFirebaseReady => Firebase.apps.isNotEmpty;

  FirebaseFirestore get _firestore => FirebaseFirestore.instance;

  // Collections
  static const String ordersCollection = 'orders';
  static const String usersCollection = 'users';
  static const String messagesCollection = 'messages';
  static const String ratingsCollection = 'ratings';

  // ===== ORDER OPERATIONS =====

  /// STREAM - Theo dõi tất cả đơn hàng theo thời gian thực
  Stream<List<DeliveryOrder>> watchAllOrders() {
    if (!isFirebaseReady) {
      debugPrint(
        'watchAllOrders skipped: Firebase chưa được khởi tạo (No default app).',
      );
      return Stream<List<DeliveryOrder>>.value(const <DeliveryOrder>[]);
    }

    return _firestore
        .collection(ordersCollection)
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map(
          (snapshot) => snapshot.docs
              .map((doc) => _mapDocToOrder(doc))
              .toList(growable: false),
        );
  }

  /// CREATE - Tạo đơn hàng mới
  /// [order] là DeliveryOrder cần lưu
  Future<String> createOrder(DeliveryOrder order) async {
    try {
      final docRef = _firestore.collection(ordersCollection).doc(order.id);

      await docRef.set({
        'id': order.id,
        'title': order.title,
        'description': order.description,
        'imageUrl': order.imageUrl,
        'senderId': order.senderId,
        'receiverId': order.receiverId,
        'carrierId': order.carrierId,
        'createdBy': order.createdBy,
        'status': order.status.name,
        'createdAt': Timestamp.fromDate(order.createdAt),
        'deadlineAt': Timestamp.fromDate(order.deadlineAt),
        'senderLocation': order.senderLocation.toMap(),
        'receiverLocation': order.receiverLocation.toMap(),
        'pickupLocation': order.pickupLocation?.toMap(),
        'deliveryLocation': order.deliveryLocation?.toMap(),
      });

      return order.id;
    } catch (e) {
      debugPrint('Error creating order: $e');
      rethrow;
    }
  }

  /// READ - Lấy đơn hàng theo ID
  Future<DeliveryOrder?> getOrderById(String orderId) async {
    try {
      final doc = await _firestore
          .collection(ordersCollection)
          .doc(orderId)
          .get();

      if (!doc.exists) {
        return null;
      }

      return _mapDocToOrder(doc);
    } catch (e) {
      debugPrint('Error getting order: $e');
      return null;
    }
  }

  /// READ - Lấy tất cả đơn hàng của người dùng
  /// [userId] ID của người dùng
  /// [role] vai trò: 'sender' (người gửi), 'receiver' (người nhận), 'carrier' (người trung gian)
  Future<List<DeliveryOrder>> getUserOrders(
    String userId, {
    String role = 'sender',
  }) async {
    try {
      late Query query;

      switch (role) {
        case 'sender':
          query = _firestore
              .collection(ordersCollection)
              .where('senderId', isEqualTo: userId);
          break;
        case 'receiver':
          query = _firestore
              .collection(ordersCollection)
              .where('receiverId', isEqualTo: userId);
          break;
        case 'carrier':
          query = _firestore
              .collection(ordersCollection)
              .where('carrierId', isEqualTo: userId);
          break;
        default:
          throw Exception('Invalid role');
      }

      final querySnapshot = await query.get();
      return querySnapshot.docs
          .map(
            (doc) =>
                _mapDocToOrder(doc as DocumentSnapshot<Map<String, dynamic>>),
          )
          .toList();
    } catch (e) {
      debugPrint('Error getting user orders: $e');
      return [];
    }
  }

  /// READ - Lấy các đơn hàng theo status
  Future<List<DeliveryOrder>> getOrdersByStatus(String status) async {
    try {
      final querySnapshot = await _firestore
          .collection(ordersCollection)
          .where('status', isEqualTo: status)
          .orderBy('createdAt', descending: true)
          .get();

      return querySnapshot.docs
          .map(
            (doc) =>
                _mapDocToOrder(doc as DocumentSnapshot<Map<String, dynamic>>),
          )
          .toList();
    } catch (e) {
      debugPrint('Error getting orders by status: $e');
      return [];
    }
  }

  /// READ - Lấy các đơn đang chờ người trung gian (trong bán kính cho trước)
  /// [userLocation] vị trí hiện tại của người trung gian
  /// [radiusKm] bán kính tìm kiếm (mặc định 5km)
  Future<List<DeliveryOrder>> getAvailableOrdersNearby(
    Location userLocation, {
    double radiusKm = 5.0,
  }) async {
    try {
      // Lấy tất cả đơn chờ người trung gian
      final querySnapshot = await _firestore
          .collection(ordersCollection)
          .where('status', isEqualTo: 'waitingCarrier')
          .get();

      final orders = querySnapshot.docs
          .map(
            (doc) =>
                _mapDocToOrder(doc as DocumentSnapshot<Map<String, dynamic>>),
          )
          .toList();

      // Lọc những đơn nằm trong bán kính
      return orders.where((order) {
        final distance = userLocation.distanceTo(order.receiverLocation);
        return distance <= radiusKm;
      }).toList();
    } catch (e) {
      debugPrint('Error getting nearby orders: $e');
      return [];
    }
  }

  /// UPDATE - Cập nhật status đơn hàng
  /// Luồng cập nhật: waitingCarrier → waitingDelivery → completed
  Future<void> updateOrderStatus(String orderId, String newStatus) async {
    try {
      await _firestore.collection(ordersCollection).doc(orderId).update({
        'status': newStatus,
      });
    } catch (e) {
      debugPrint('Error updating order status: $e');
      rethrow;
    }
  }

  /// UPDATE - Nhận đơn (gán người trung gian)
  /// Khi người trung gian C nhận đơn
  Future<void> acceptOrder(String orderId, String carrierId) async {
    try {
      await _firestore.collection(ordersCollection).doc(orderId).update({
        'carrierId': carrierId,
        'status': 'waitingDelivery',
      });
    } catch (e) {
      debugPrint('Error accepting order: $e');
      rethrow;
    }
  }

  /// UPDATE - Sửa địa chỉ gửi/nhận khi đơn chưa có ai nhận giao
  /// Chỉ cho phép người tạo đơn hoặc người gửi sửa
  Future<void> updateOrderLocations({
    required String orderId,
    required String actorUserId,
    required Location senderLocation,
    required Location receiverLocation,
  }) async {
    final docRef = _firestore.collection(ordersCollection).doc(orderId);

    try {
      await _firestore.runTransaction((transaction) async {
        final snapshot = await transaction.get(docRef);
        if (!snapshot.exists) {
          throw StateError('Không tìm thấy đơn hàng để cập nhật địa chỉ.');
        }

        final data = snapshot.data() as Map<String, dynamic>;
        final status = (data['status'] as String?) ?? 'waitingCarrier';
        final carrierId = (data['carrierId'] as String?)?.trim() ?? '';
        final createdBy = (data['createdBy'] as String?)?.trim() ?? '';
        final senderId = (data['senderId'] as String?)?.trim() ?? '';
        final actorId = actorUserId.trim();

        final canEditByRole =
            actorId.isNotEmpty && (actorId == createdBy || actorId == senderId);
        if (!canEditByRole) {
          throw StateError('Bạn không có quyền sửa địa chỉ đơn này.');
        }

        final canEditByOrderState =
            status == 'waitingCarrier' && carrierId.isEmpty;
        if (!canEditByOrderState) {
          throw StateError(
            'Đơn đã có người nhận hoặc không còn ở trạng thái chờ nhận.',
          );
        }

        transaction.update(docRef, {
          'senderLocation': senderLocation.toMap(),
          'receiverLocation': receiverLocation.toMap(),
          'updatedAt': Timestamp.now(),
        });
      });
    } catch (e) {
      debugPrint('Error updating order locations: $e');
      rethrow;
    }
  }

  /// UPDATE - Cập nhật vị trí lấy hàng (khi C lấy từ A)
  Future<void> updatePickupLocation(
    String orderId,
    Location pickupLocation,
  ) async {
    try {
      await _firestore.collection(ordersCollection).doc(orderId).update({
        'pickupLocation': pickupLocation.toMap(),
        'status': 'waitingDelivery',
      });
    } catch (e) {
      debugPrint('Error updating pickup location: $e');
      rethrow;
    }
  }

  /// UPDATE - Cập nhật vị trí giao hàng (khi C giao cho B)
  Future<void> updateDeliveryLocation(
    String orderId,
    Location deliveryLocation,
  ) async {
    try {
      await _firestore.collection(ordersCollection).doc(orderId).update({
        'deliveryLocation': deliveryLocation.toMap(),
        'status': 'completed',
      });
    } catch (e) {
      debugPrint('Error updating delivery location: $e');
      rethrow;
    }
  }

  /// DELETE - Hủy đơn hàng
  Future<void> cancelOrder(String orderId) async {
    try {
      await _firestore.collection(ordersCollection).doc(orderId).update({
        'status': 'cancelled',
      });
    } catch (e) {
      debugPrint('Error cancelling order: $e');
      rethrow;
    }
  }

  /// STREAM - Theo dõi thay đổi của một đơn hàng (Real-time)
  /// Dùng cho Chat 3 người để update tình trạng đơn
  Stream<DeliveryOrder?> watchOrder(String orderId) {
    if (!isFirebaseReady) {
      debugPrint(
        'watchOrder skipped: Firebase chưa được khởi tạo (No default app).',
      );
      return Stream<DeliveryOrder?>.value(null);
    }

    return _firestore.collection(ordersCollection).doc(orderId).snapshots().map(
      (doc) {
        if (!doc.exists) {
          return null;
        }
        return _mapDocToOrder(doc);
      },
    );
  }

  // ===== USER OPERATIONS =====

  /// CREATE/UPDATE - Lưu hoặc cập nhật profile người dùng
  Future<void> saveUserProfile({
    required String userId,
    required String name,
    required String email,
    required bool isVerified,
    String? avatarUrl,
    String? phone,
    double? rating,
    int? totalDeliveries,
  }) async {
    try {
      await _firestore.collection(usersCollection).doc(userId).set({
        'id': userId,
        'name': name,
        'email': email,
        'phone': phone,
        'avatarUrl': avatarUrl,
        'isVerified': isVerified,
        'rating': rating ?? 0.0,
        'totalDeliveries': totalDeliveries ?? 0,
        'createdAt': Timestamp.now(),
        'updatedAt': Timestamp.now(),
      }, SetOptions(merge: true));
    } catch (e) {
      debugPrint('Error saving user profile: $e');
      rethrow;
    }
  }

  /// READ - Lấy profile người dùng
  Future<Map<String, dynamic>?> getUserProfile(String userId) async {
    try {
      final doc = await _firestore
          .collection(usersCollection)
          .doc(userId)
          .get();

      if (!doc.exists) {
        return null;
      }

      return doc.data();
    } catch (e) {
      debugPrint('Error getting user profile: $e');
      return null;
    }
  }

  // ===== MESSAGE OPERATIONS =====

  /// CREATE - Gửi tin nhắn trong cuộc trò chuyện 3 người
  /// [orderId] ID của đơn hàng
  /// [senderId] ID của người gửi
  /// [message] nội dung tin nhắn
  Future<void> sendMessage({
    required String orderId,
    required String senderId,
    required String message,
  }) async {
    try {
      final messageRef = _firestore
          .collection(ordersCollection)
          .doc(orderId)
          .collection(messagesCollection)
          .doc();

      await messageRef.set({
        'id': messageRef.id,
        'senderId': senderId,
        'message': message,
        'createdAt': Timestamp.now(),
        'delivered': false,
      });
    } catch (e) {
      debugPrint('Error sending message: $e');
      rethrow;
    }
  }

  /// READ - Lấy các tin nhắn của một đơn hàng
  /// [orderId] ID của đơn hàng
  /// [limit] số lượng tin nhắn muốn lấy (mặc định 50)
  Future<List<Map<String, dynamic>>> getMessages(
    String orderId, {
    int limit = 50,
  }) async {
    try {
      final querySnapshot = await _firestore
          .collection(ordersCollection)
          .doc(orderId)
          .collection(messagesCollection)
          .orderBy('createdAt', descending: true)
          .limit(limit)
          .get();

      return querySnapshot.docs
          .map((doc) => doc.data())
          .toList()
          .reversed
          .toList();
    } catch (e) {
      debugPrint('Error getting messages: $e');
      return [];
    }
  }

  /// STREAM - Theo dõi tin nhắn real-time
  Stream<List<Map<String, dynamic>>> watchMessages(String orderId) {
    if (!isFirebaseReady) {
      debugPrint(
        'watchMessages skipped: Firebase chưa được khởi tạo (No default app).',
      );
      return Stream<List<Map<String, dynamic>>>.value(
        const <Map<String, dynamic>>[],
      );
    }

    return _firestore
        .collection(ordersCollection)
        .doc(orderId)
        .collection(messagesCollection)
        .orderBy('createdAt')
        .snapshots()
        .map((snapshot) => snapshot.docs.map((doc) => doc.data()).toList());
  }

  // ===== RATING OPERATIONS =====

  /// CREATE - Lưu đánh giá cho người dùng
  /// [orderId] ID của đơn hàng
  /// [ratedUserId] ID của người được đánh giá
  /// [raterUserId] ID của người đánh giá
  /// [rating] số sao (1-5)
  /// [comment] bình luận
  Future<void> saveRating({
    required String orderId,
    required String ratedUserId,
    required String raterUserId,
    required double rating,
    String? comment,
  }) async {
    try {
      final ratingRef = _firestore
          .collection(ordersCollection)
          .doc(orderId)
          .collection(ratingsCollection)
          .doc();

      await ratingRef.set({
        'orderId': orderId,
        'ratedUserId': ratedUserId,
        'raterUserId': raterUserId,
        'rating': rating,
        'comment': comment,
        'createdAt': Timestamp.now(),
      });

      // Cập nhật điểm rating TB cho người được đánh giá
      await _updateUserAverageRating(ratedUserId);
    } catch (e) {
      debugPrint('Error saving rating: $e');
      rethrow;
    }
  }

  /// UPDATE - Cập nhật điểm rating trung bình của người dùng
  Future<void> _updateUserAverageRating(String userId) async {
    try {
      // Lấy tất cả ratings của user này
      final ratingsSnapshot = await _firestore
          .collectionGroup(ratingsCollection)
          .where('ratedUserId', isEqualTo: userId)
          .get();

      if (ratingsSnapshot.docs.isEmpty) {
        return;
      }

      // Tính trung bình
      final ratings = ratingsSnapshot.docs
          .map((doc) => (doc.data()['rating'] as num).toDouble())
          .toList();

      final averageRating = ratings.reduce((a, b) => a + b) / ratings.length;

      // Cập nhật vào user profile
      await _firestore.collection(usersCollection).doc(userId).update({
        'rating': averageRating,
      });
    } catch (e) {
      debugPrint('Error updating user average rating: $e');
    }
  }

  // ===== HELPER METHODS =====

  /// Chuyển đổi Firestore Document thành DeliveryOrder
  DeliveryOrder _mapDocToOrder(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? {};

    return DeliveryOrder(
      id: data['id'] ?? '',
      title: data['title'] ?? '',
      description: data['description'] ?? '',
      imageUrl: data['imageUrl'] ?? '',
      senderId: data['senderId'] ?? '',
      receiverId: data['receiverId'] ?? '',
      carrierId: data['carrierId'],
      createdBy: data['createdBy'] ?? '',
      status: _parseOrderStatus(data['status'] ?? 'waitingCarrier'),
      createdAt: (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      deadlineAt:
          (data['deadlineAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      senderLocation: data['senderLocation'] != null
          ? Location.fromMap(data['senderLocation'] as Map<String, dynamic>)
          : Location(latitude: 0, longitude: 0),
      receiverLocation: data['receiverLocation'] != null
          ? Location.fromMap(data['receiverLocation'] as Map<String, dynamic>)
          : Location(latitude: 0, longitude: 0),
      pickupLocation: data['pickupLocation'] != null
          ? Location.fromMap(data['pickupLocation'] as Map<String, dynamic>)
          : null,
      deliveryLocation: data['deliveryLocation'] != null
          ? Location.fromMap(data['deliveryLocation'] as Map<String, dynamic>)
          : null,
    );
  }

  /// Parse status string thành OrderStatus enum
  OrderStatus _parseOrderStatus(String status) {
    switch (status) {
      case 'waitingCarrier':
        return OrderStatus.waitingCarrier;
      case 'waitingDelivery':
        return OrderStatus.waitingDelivery;
      case 'completed':
        return OrderStatus.completed;
      case 'cancelled':
        return OrderStatus.cancelled;
      default:
        return OrderStatus.waitingCarrier;
    }
  }
}
