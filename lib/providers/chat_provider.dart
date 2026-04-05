import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';

import '../services/chat_service.dart';
import '../services/user_session_service.dart';

class ChatProvider extends ChangeNotifier {
  ChatProvider({
    required ChatService chatService,
    required UserSessionService userSessionService,
  }) : _chatService = chatService,
       _userSessionService = userSessionService {
    _userSessionService.addListener(_bindCurrentUserFromSession);
    _bindCurrentUserFromSession();
  }

  final ChatService _chatService;
  final UserSessionService _userSessionService;

  StreamSubscription<List<ChatRoomModel>>? _roomsSubscription;
  StreamSubscription<List<ChatMessageModel>>? _messagesSubscription;

  String _currentUserId = '';
  String? _selectedRoomId;
  List<ChatRoomModel> _rooms = const <ChatRoomModel>[];
  List<ChatMessageModel> _messages = const <ChatMessageModel>[];
  bool _roomsLoading = true;
  bool _messagesLoading = false;
  String? _error;
  bool _sending = false;
  bool _uploadingImage = false;

  String get currentUserId => _currentUserId;
  String? get selectedRoomId => _selectedRoomId;
  List<ChatRoomModel> get rooms => _rooms;
  List<ChatMessageModel> get messages => _messages;
  bool get roomsLoading => _roomsLoading;
  bool get messagesLoading => _messagesLoading;
  String? get error => _error;
  bool get sending => _sending;
  bool get uploadingImage => _uploadingImage;
  bool get isBusy => _sending || _uploadingImage;

  ChatRoomModel? get selectedRoom {
    if (_selectedRoomId == null) {
      return null;
    }
    for (final room in _rooms) {
      if (room.id == _selectedRoomId) {
        return room;
      }
    }
    return null;
  }

  void setCurrentUser(String userId) {
    final normalized = userId.trim();
    if (normalized == _currentUserId) {
      return;
    }

    _currentUserId = normalized;
    _listenRooms();
  }

  void selectRoom(String roomId) {
    final normalizedRoomId = roomId.trim();
    if (normalizedRoomId.isEmpty || normalizedRoomId == _selectedRoomId) {
      return;
    }

    _selectedRoomId = normalizedRoomId;
    _listenMessages();
    notifyListeners();
  }

  Future<void> sendTextMessage(String content) async {
    final roomId = _selectedRoomId;
    if (roomId == null || roomId.trim().isEmpty) {
      throw Exception('Chưa chọn cuộc trò chuyện.');
    }

    if (_sending) {
      return;
    }

    _sending = true;
    notifyListeners();

    try {
      await _chatService.sendTextMessage(
        roomId: roomId,
        senderId: _currentUserId,
        content: content,
      );
    } finally {
      _sending = false;
      notifyListeners();
    }
  }

  Future<Uint8List?> pickImage({
    ImageSource source = ImageSource.gallery,
  }) async {
    return _chatService.pickImage(source: source);
  }

  Future<void> sendImageMessage(Uint8List bytes) async {
    final roomId = _selectedRoomId;
    if (roomId == null || roomId.trim().isEmpty) {
      throw Exception('Chưa chọn cuộc trò chuyện.');
    }

    if (_uploadingImage) {
      return;
    }

    _uploadingImage = true;
    notifyListeners();

    try {
      await _chatService.sendImageMessage(
        roomId: roomId,
        senderId: _currentUserId,
        bytes: bytes,
      );
    } finally {
      _uploadingImage = false;
      notifyListeners();
    }
  }

  Future<void> leaveRoom(String roomId) async {
    final normalizedRoomId = roomId.trim();
    if (normalizedRoomId.isEmpty || _currentUserId.isEmpty) {
      throw Exception('Không thể rời phòng chat.');
    }

    await _chatService.leaveRoom(
      roomId: normalizedRoomId,
      userId: _currentUserId,
    );

    if (_selectedRoomId == normalizedRoomId) {
      _selectedRoomId = null;
      _messages = const <ChatMessageModel>[];
      _messagesLoading = false;
      notifyListeners();
    }
  }

  void _bindCurrentUserFromSession() {
    setCurrentUser(_userSessionService.currentUserId);
  }

  void _listenRooms() {
    _roomsSubscription?.cancel();
    _rooms = const <ChatRoomModel>[];
    _messages = const <ChatMessageModel>[];
    _selectedRoomId = null;
    _roomsLoading = true;
    _messagesLoading = false;
    _error = null;
    notifyListeners();

    if (_currentUserId.isEmpty) {
      _roomsLoading = false;
      notifyListeners();
      return;
    }

    _roomsSubscription = _chatService
        .watchRoomsByUser(_currentUserId)
        .listen(
          (rooms) {
            _rooms = rooms;
            _roomsLoading = false;
            _error = null;

            if (_selectedRoomId == null && rooms.isNotEmpty) {
              _selectedRoomId = rooms.first.id;
              _listenMessages();
            }

            if (_selectedRoomId != null &&
                !rooms.any((room) => room.id == _selectedRoomId)) {
              _selectedRoomId = rooms.isEmpty ? null : rooms.first.id;
              _listenMessages();
            }

            notifyListeners();
          },
          onError: (Object error) {
            _roomsLoading = false;
            _error = error.toString();
            notifyListeners();
          },
        );
  }

  void _listenMessages() {
    _messagesSubscription?.cancel();
    _messages = const <ChatMessageModel>[];
    _messagesLoading = true;
    _error = null;
    notifyListeners();

    final roomId = _selectedRoomId;
    if (roomId == null || roomId.trim().isEmpty) {
      _messagesLoading = false;
      notifyListeners();
      return;
    }

    _messagesSubscription = _chatService
        .watchMessages(roomId)
        .listen(
          (messages) {
            _messages = messages;
            _messagesLoading = false;
            _error = null;
            notifyListeners();
          },
          onError: (Object error) {
            _messagesLoading = false;
            _error = error.toString();
            notifyListeners();
          },
        );
  }

  @override
  void dispose() {
    _userSessionService.removeListener(_bindCurrentUserFromSession);
    _roomsSubscription?.cancel();
    _messagesSubscription?.cancel();
    super.dispose();
  }
}
