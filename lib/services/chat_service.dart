import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class ChatRoomModel {
  const ChatRoomModel({
    required this.id,
    required this.orderId,
    required this.participants,
    required this.createdAt,
    required this.updatedAt,
    this.lastMessage,
    this.lastMessageAt,
  });

  final String id;
  final String orderId;
  final List<String> participants;
  final DateTime createdAt;
  final DateTime updatedAt;
  final String? lastMessage;
  final DateTime? lastMessageAt;

  factory ChatRoomModel.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? <String, dynamic>{};

    DateTime parseDate(dynamic raw, DateTime fallback) {
      if (raw is Timestamp) {
        return raw.toDate();
      }
      if (raw is DateTime) {
        return raw;
      }
      if (raw is String) {
        return DateTime.tryParse(raw) ?? fallback;
      }
      return fallback;
    }

    final now = DateTime.now();
    return ChatRoomModel(
      id: (data['id'] as String?) ?? doc.id,
      orderId: (data['order_id'] as String?) ?? '',
      participants: ((data['participants'] as List?) ?? const <dynamic>[])
          .map((e) => e.toString())
          .where((e) => e.trim().isNotEmpty)
          .toList(growable: false),
      createdAt: parseDate(data['created_at'], now),
      updatedAt: parseDate(data['updated_at'], now),
      lastMessage: data['last_message'] as String?,
      lastMessageAt: data['last_message_at'] == null
          ? null
          : parseDate(data['last_message_at'], now),
    );
  }
}

class ChatMessageModel {
  const ChatMessageModel({
    required this.id,
    required this.roomId,
    required this.senderId,
    required this.content,
    required this.type,
    required this.createdAt,
  });

  final String id;
  final String roomId;
  final String senderId;
  final String content;
  final String type;
  final DateTime createdAt;

  factory ChatMessageModel.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? <String, dynamic>{};

    DateTime parseDate(dynamic raw) {
      if (raw is Timestamp) {
        return raw.toDate();
      }
      if (raw is DateTime) {
        return raw;
      }
      if (raw is String) {
        return DateTime.tryParse(raw) ?? DateTime.now();
      }
      return DateTime.now();
    }

    return ChatMessageModel(
      id: (data['id'] as String?) ?? doc.id,
      roomId: (data['room_id'] as String?) ?? '',
      senderId: (data['sender_id'] as String?) ?? '',
      content: (data['content'] as String?) ?? '',
      type: (data['type'] as String?) ?? 'text',
      createdAt: parseDate(data['created_at']),
    );
  }
}

class ChatService {
  ChatService({FirebaseFirestore? firestore})
    : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;
  final ImagePicker _imagePicker = ImagePicker();

  static const String chatRoomsCollection = 'chat_rooms';
  static const String messagesCollection = 'messages';

  CollectionReference<Map<String, dynamic>> get _chatRoomsRef =>
      _firestore.collection(chatRoomsCollection);

  SupabaseClient? _tryGetSupabaseClient() {
    try {
      return Supabase.instance.client;
    } catch (_) {
      return null;
    }
  }

  Future<Uint8List?> pickImage({
    ImageSource source = ImageSource.gallery,
    int imageQuality = 85,
  }) async {
    try {
      final picked = await _imagePicker.pickImage(
        source: source,
        imageQuality: imageQuality,
      );
      if (picked == null) {
        debugPrint('[ChatService] pickImage cancelled by user');
        return null;
      }

      final bytes = await picked.readAsBytes();
      debugPrint('[ChatService] pickImage success, bytes=${bytes.length}');
      return bytes;
    } catch (error, stackTrace) {
      debugPrint('[ChatService] pickImage error: $error\n$stackTrace');
      rethrow;
    }
  }

  Future<String> uploadImageToSupabase({
    required String roomId,
    required Uint8List bytes,
  }) async {
    final normalizedRoomId = roomId.trim();
    if (normalizedRoomId.isEmpty) {
      throw Exception('roomId không hợp lệ để upload ảnh.');
    }
    if (bytes.isEmpty) {
      throw Exception('Ảnh rỗng, không thể upload.');
    }

    try {
      final supabase = _tryGetSupabaseClient();
      if (supabase == null) {
        throw Exception('Supabase chưa được khởi tạo.');
      }

      final fileName = '${DateTime.now().millisecondsSinceEpoch}.jpg';
      final path = 'chat_images/$normalizedRoomId/$fileName';

      await supabase.storage
          .from('orders')
          .uploadBinary(
            path,
            bytes,
            fileOptions: const FileOptions(
              upsert: false,
              cacheControl: '3600',
              contentType: 'image/jpeg',
            ),
          );

      final publicUrl = supabase.storage.from('orders').getPublicUrl(path);
      debugPrint('[ChatService] uploadImageToSupabase success: $publicUrl');
      return publicUrl;
    } catch (error, stackTrace) {
      debugPrint(
        '[ChatService] uploadImageToSupabase error: $error\n$stackTrace',
      );
      rethrow;
    }
  }

  Stream<List<ChatRoomModel>> watchRoomsByUser(String userId) {
    final normalizedUserId = userId.trim();
    if (normalizedUserId.isEmpty) {
      return Stream<List<ChatRoomModel>>.value(const <ChatRoomModel>[]);
    }

    return _chatRoomsRef
        .where('participants', arrayContains: normalizedUserId)
        .snapshots()
        .map((snapshot) {
          final rooms = snapshot.docs
              .map(ChatRoomModel.fromDoc)
              .toList(growable: false);
          rooms.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
          return rooms;
        });
  }

  Stream<List<ChatMessageModel>> watchMessages(String roomId) {
    final normalizedRoomId = roomId.trim();
    if (normalizedRoomId.isEmpty) {
      return Stream<List<ChatMessageModel>>.value(const <ChatMessageModel>[]);
    }

    return _chatRoomsRef
        .doc(normalizedRoomId)
        .collection(messagesCollection)
        .orderBy('created_at')
        .snapshots()
        .map(
          (snapshot) => snapshot.docs
              .map(ChatMessageModel.fromDoc)
              .toList(growable: false),
        );
  }

  Future<String> ensureRoomForOrder({
    required String orderId,
    required List<String> participants,
  }) async {
    final roomId = orderId.trim();
    if (roomId.isEmpty) {
      throw Exception('orderId không hợp lệ để tạo chat room.');
    }

    final normalizedParticipants = participants
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toSet()
        .toList(growable: false);

    final now = Timestamp.now();
    final ref = _chatRoomsRef.doc(roomId);

    await _firestore.runTransaction((transaction) async {
      final snapshot = await transaction.get(ref);
      if (!snapshot.exists) {
        transaction.set(ref, {
          'id': roomId,
          'order_id': roomId,
          'participants': normalizedParticipants,
          'created_at': now,
          'updated_at': now,
        });
      } else {
        transaction.update(ref, {
          'participants': normalizedParticipants,
          'updated_at': now,
        });
      }
    });

    return roomId;
  }

  Future<void> sendTextMessage({
    required String roomId,
    required String senderId,
    required String content,
  }) async {
    final normalizedRoomId = roomId.trim();
    final normalizedSenderId = senderId.trim();
    final trimmedContent = content.trim();

    if (normalizedRoomId.isEmpty) {
      throw Exception('roomId không hợp lệ.');
    }
    if (normalizedSenderId.isEmpty) {
      throw Exception('senderId không hợp lệ.');
    }
    if (trimmedContent.isEmpty) {
      throw Exception('Tin nhắn không được để trống.');
    }

    final now = Timestamp.now();
    final messageRef = _chatRoomsRef
        .doc(normalizedRoomId)
        .collection(messagesCollection)
        .doc();
    final roomRef = _chatRoomsRef.doc(normalizedRoomId);

    await _firestore.runTransaction((transaction) async {
      transaction.set(messageRef, {
        'id': messageRef.id,
        'room_id': normalizedRoomId,
        'sender_id': normalizedSenderId,
        'content': trimmedContent,
        'type': 'text',
        'created_at': now,
      });

      transaction.update(roomRef, {
        'last_message': trimmedContent,
        'last_message_at': now,
        'updated_at': now,
      });
    });
  }

  Future<void> sendImageMessage({
    required String roomId,
    required String senderId,
    required Uint8List bytes,
  }) async {
    final normalizedRoomId = roomId.trim();
    final normalizedSenderId = senderId.trim();

    if (normalizedRoomId.isEmpty) {
      throw Exception('roomId không hợp lệ.');
    }
    if (normalizedSenderId.isEmpty) {
      throw Exception('senderId không hợp lệ.');
    }

    try {
      final imageUrl = await uploadImageToSupabase(
        roomId: normalizedRoomId,
        bytes: bytes,
      );

      final now = Timestamp.now();
      final messageRef = _chatRoomsRef
          .doc(normalizedRoomId)
          .collection(messagesCollection)
          .doc();
      final roomRef = _chatRoomsRef.doc(normalizedRoomId);

      await _firestore.runTransaction((transaction) async {
        transaction.set(messageRef, {
          'id': messageRef.id,
          'room_id': normalizedRoomId,
          'sender_id': normalizedSenderId,
          'content': imageUrl,
          'type': 'image',
          'created_at': now,
        });

        transaction.update(roomRef, {
          'last_message': '[Image]',
          'last_message_at': now,
          'updated_at': now,
        });
      });
      debugPrint(
        '[ChatService] sendImageMessage success, room=$normalizedRoomId',
      );
    } catch (error, stackTrace) {
      debugPrint('[ChatService] sendImageMessage error: $error\n$stackTrace');
      rethrow;
    }
  }

  Future<void> leaveRoom({
    required String roomId,
    required String userId,
  }) async {
    final normalizedRoomId = roomId.trim();
    final normalizedUserId = userId.trim();

    if (normalizedRoomId.isEmpty) {
      throw Exception('roomId không hợp lệ.');
    }
    if (normalizedUserId.isEmpty) {
      throw Exception('userId không hợp lệ.');
    }

    final roomRef = _chatRoomsRef.doc(normalizedRoomId);

    await _firestore.runTransaction((transaction) async {
      final snapshot = await transaction.get(roomRef);
      if (!snapshot.exists) {
        throw Exception('Không tìm thấy phòng chat.');
      }

      final data = snapshot.data() ?? <String, dynamic>{};
      final participants =
          ((data['participants'] as List?) ?? const <dynamic>[])
              .map((e) => e.toString().trim())
              .where((e) => e.isNotEmpty)
              .toSet()
              .toList(growable: false);

      if (!participants.contains(normalizedUserId)) {
        throw Exception('Bạn không còn trong phòng chat này.');
      }

      final remainingParticipants = participants
          .where((id) => id != normalizedUserId)
          .toList(growable: false);

      if (remainingParticipants.isEmpty) {
        transaction.delete(roomRef);
        return;
      }

      transaction.update(roomRef, {
        'participants': remainingParticipants,
        'updated_at': Timestamp.now(),
      });
    });
  }
}
