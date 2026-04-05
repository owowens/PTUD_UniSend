import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../../providers/chat_provider.dart';
import '../../services/chat_service.dart';
import '../../services/firestore_service.dart';
import '../../services/user_session_service.dart';
import '../../widgets/common/chat_bubble.dart';

class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _UserInfoData {
  const _UserInfoData({required this.profile, required this.ratingCount});

  final Map<String, dynamic>? profile;
  final int ratingCount;
}

class _ChatScreenState extends State<ChatScreen> {
  final TextEditingController _controller = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final FirestoreService _firestoreService = FirestoreService();
  final Map<String, Map<String, dynamic>> _userProfileCache = {};
  final Map<String, int> _userRatingCountCache = {};
  int _lastMessageCount = 0;

  @override
  void dispose() {
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _autoScrollIfNeeded(int messageCount) {
    if (messageCount <= _lastMessageCount) {
      return;
    }
    _lastMessageCount = messageCount;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) {
        return;
      }
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 240),
        curve: Curves.easeOut,
      );
    });
  }

  Future<void> _sendMessage() async {
    final content = _controller.text.trim();
    if (content.isEmpty) {
      return;
    }

    try {
      await context.read<ChatProvider>().sendTextMessage(content);
      _controller.clear();
    } catch (e) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Không gửi được tin nhắn: $e'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<void> _pickAndSendImage(ImageSource source) async {
    final provider = context.read<ChatProvider>();

    try {
      final bytes = await provider.pickImage(source: source);
      if (bytes == null || bytes.isEmpty) {
        return;
      }

      await provider.sendImageMessage(bytes);
    } catch (e) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Không gửi được ảnh: $e'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<void> _showImagePickerOptions() async {
    if (context.read<ChatProvider>().isBusy) {
      return;
    }

    await showModalBottomSheet<void>(
      context: context,
      builder: (sheetContext) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.photo_library_outlined),
                title: const Text('Chọn từ thư viện'),
                onTap: () async {
                  Navigator.of(sheetContext).pop();
                  await _pickAndSendImage(ImageSource.gallery);
                },
              ),
              ListTile(
                leading: const Icon(Icons.camera_alt_outlined),
                title: const Text('Chụp ảnh'),
                onTap: () async {
                  Navigator.of(sheetContext).pop();
                  await _pickAndSendImage(ImageSource.camera);
                },
              ),
            ],
          ),
        );
      },
    );
  }

  Future<Map<String, dynamic>?> _loadUserProfile(
    String userId, {
    bool forceRefresh = false,
  }) async {
    final normalizedUserId = userId.trim();
    if (normalizedUserId.isEmpty) {
      return null;
    }

    final cached = _userProfileCache[normalizedUserId];
    if (cached != null && !forceRefresh) {
      return cached;
    }

    final profile = await _firestoreService.getUserProfile(normalizedUserId);
    if (profile != null) {
      _userProfileCache[normalizedUserId] = profile;
    }
    return profile;
  }

  Future<int> _loadUserRatingCount(
    String userId, {
    bool forceRefresh = false,
  }) async {
    final normalizedUserId = userId.trim();
    if (normalizedUserId.isEmpty) {
      return 0;
    }

    final cached = _userRatingCountCache[normalizedUserId];
    if (cached != null && !forceRefresh) {
      return cached;
    }

    final count = await _firestoreService.getUserRatingCount(normalizedUserId);
    _userRatingCountCache[normalizedUserId] = count;
    return count;
  }

  Future<_UserInfoData> _loadUserInfo(
    String userId, {
    bool forceRefresh = false,
  }) async {
    final profile = await _loadUserProfile(userId, forceRefresh: forceRefresh);
    final ratingCount = await _loadUserRatingCount(
      userId,
      forceRefresh: forceRefresh,
    );
    return _UserInfoData(profile: profile, ratingCount: ratingCount);
  }

  String _profileDisplayName(Map<String, dynamic>? profile, String userId) {
    final name = (profile?['name'] as String?)?.trim();
    final accountId = (profile?['accountId'] as String?)?.trim();
    if (name != null && name.isNotEmpty) {
      return name;
    }
    if (accountId != null && accountId.isNotEmpty) {
      return accountId;
    }
    return userId;
  }

  String? _profileAvatarUrl(Map<String, dynamic>? profile) {
    final avatarUrl = (profile?['avatarUrl'] as String?)?.trim();
    if (avatarUrl != null && avatarUrl.isNotEmpty) {
      return avatarUrl;
    }
    return null;
  }

  Future<List<String>> _loadRoomParticipantAccountCodes(
    List<String> participantIds,
  ) async {
    final codes = <String>[];

    for (final participantId in participantIds) {
      final profile = await _loadUserProfile(participantId);
      final accountCode = (profile?['accountId'] as String?)?.trim();
      if (accountCode != null && accountCode.isNotEmpty) {
        codes.add(accountCode);
      } else {
        codes.add(participantId.trim());
      }
    }

    return codes;
  }

  void _showUserInfo(BuildContext context, String userId) {
    if (userId.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Không tìm thấy thông tin người dùng.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Thông tin người dùng'),
        content: FutureBuilder<_UserInfoData>(
          future: _loadUserInfo(userId, forceRefresh: true),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const SizedBox(
                height: 120,
                child: Center(child: CircularProgressIndicator()),
              );
            }

            final info = snapshot.data;
            final profile = info?.profile;
            if (profile == null) {
              return const Text('Không tìm thấy thông tin người dùng.');
            }

            final displayName = _profileDisplayName(profile, userId);
            final accountId = (profile['accountId'] as String?)?.trim();
            final avatarUrl = _profileAvatarUrl(profile);
            final phone = (profile['phone'] as String?)?.trim();
            final deliveries = (profile['totalDeliveries'] as num?) ?? 0;
            final averageRating =
                (profile['rating'] as num?)?.toDouble() ?? 0.0;
            final ratingCount = info?.ratingCount ?? 0;
            final ratingText = ratingCount > 0
                ? '${averageRating.toStringAsFixed(1)}/5 trên $ratingCount lượt'
                : 'Chưa có đánh giá';

            return SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: CircleAvatar(
                      radius: 34,
                      backgroundColor: Theme.of(
                        context,
                      ).colorScheme.primaryContainer,
                      backgroundImage: avatarUrl != null
                          ? NetworkImage(avatarUrl)
                          : null,
                      child: avatarUrl == null
                          ? Icon(
                              Icons.person,
                              size: 34,
                              color: Theme.of(
                                context,
                              ).colorScheme.onPrimaryContainer,
                            )
                          : null,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Center(
                    child: Text(
                      displayName,
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Mã tài khoản: ${accountId == null || accountId.isEmpty ? '---' : accountId}',
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Số điện thoại: ${phone == null || phone.isEmpty ? '---' : phone}',
                  ),
                  const SizedBox(height: 8),
                  Text('Đơn giao thành công: ${deliveries.toString()}'),
                  const SizedBox(height: 8),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      color: Theme.of(
                        context,
                      ).colorScheme.primaryContainer.withAlpha(120),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.star_rounded,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Đánh giá: $ratingText',
                            style: Theme.of(context).textTheme.bodyMedium,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            );
          },
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Đóng'),
          ),
        ],
      ),
    );
  }

  Future<void> _leaveRoomWithConfirmation(
    BuildContext context,
    ChatRoomModel room,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (confirmContext) => AlertDialog(
        title: const Text('Rời khỏi phòng chat'),
        content: Text(
          'Bạn có chắc muốn rời khỏi phòng chat ${room.id} không? Sau khi rời, phòng này sẽ không còn hiển thị trong trò chuyện của bạn.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(confirmContext).pop(false),
            child: const Text('Hủy'),
          ),
          FilledButton.tonal(
            onPressed: () => Navigator.of(confirmContext).pop(true),
            child: const Text('Rời phòng'),
          ),
        ],
      ),
    );

    if (confirmed != true || !context.mounted) {
      return;
    }

    try {
      await context.read<ChatProvider>().leaveRoom(room.id);
      if (!context.mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Đã rời khỏi phòng chat.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (e) {
      if (!context.mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Không thể rời phòng chat: $e'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  void _showRoomInfo(BuildContext context, ChatRoomModel room) {
    final participants = room.participants;
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Chi tiết phòng chat'),
        content: FutureBuilder<List<String>>(
          future: _loadRoomParticipantAccountCodes(participants),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const SizedBox(
                height: 120,
                child: Center(child: CircularProgressIndicator()),
              );
            }

            final accountCodes = snapshot.data ?? const <String>[];
            return SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Tên room: ${room.id}'),
                  const SizedBox(height: 8),
                  Text('Mã đơn: ${room.orderId}'),
                  const SizedBox(height: 8),
                  Text('Số người tham gia: ${participants.length}'),
                  const SizedBox(height: 8),
                  Text(
                    'Thành viên:',
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  const SizedBox(height: 6),
                  if (accountCodes.isEmpty)
                    const Text('---')
                  else
                    ...accountCodes.map(
                      (code) => Padding(
                        padding: const EdgeInsets.symmetric(vertical: 2),
                        child: Text('• $code'),
                      ),
                    ),
                ],
              ),
            );
          },
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Đóng'),
          ),
          TextButton(
            onPressed: () {
              Navigator.of(dialogContext).pop();
              _leaveRoomWithConfirmation(context, room);
            },
            style: TextButton.styleFrom(
              foregroundColor: Theme.of(context).colorScheme.error,
            ),
            child: const Text('Rời khỏi phòng chat'),
          ),
        ],
      ),
    );
  }

  String _roomSubtitle(ChatRoomModel room, String currentUserId) {
    final others = room.participants
        .where((id) => id != currentUserId)
        .toList();
    if (others.isEmpty) {
      return 'Đơn #${room.orderId}';
    }
    return 'Đơn #${room.orderId} • ${others.join(', ')}';
  }

  @override
  Widget build(BuildContext context) {
    final currentUserId = context.watch<UserSessionService>().currentUserId;
    final chatProvider = context.watch<ChatProvider>();

    if (chatProvider.currentUserId != currentUserId) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) {
          return;
        }
        context.read<ChatProvider>().setCurrentUser(currentUserId);
      });
    }

    _autoScrollIfNeeded(chatProvider.messages.length);

    return Scaffold(
      appBar: AppBar(title: const Text('Trò chuyện')),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final roomPanelWidth = (constraints.maxWidth * 0.24)
              .clamp(200.0, 260.0)
              .toDouble();

          return Column(
            children: [
              if (chatProvider.error != null)
                Container(
                  width: double.infinity,
                  color: Theme.of(context).colorScheme.errorContainer,
                  padding: const EdgeInsets.all(10),
                  child: Text(
                    chatProvider.error!,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
              Expanded(
                child: Row(
                  children: [
                    SizedBox(
                      width: roomPanelWidth,
                      child: _RoomsPanel(
                        rooms: chatProvider.rooms,
                        selectedRoomId: chatProvider.selectedRoomId,
                        isLoading: chatProvider.roomsLoading,
                        currentUserId: currentUserId,
                        subtitleBuilder: _roomSubtitle,
                        onRoomInfoTap: (room) => _showRoomInfo(context, room),
                        onSelectRoom: (roomId) {
                          context.read<ChatProvider>().selectRoom(roomId);
                        },
                      ),
                    ),
                    const VerticalDivider(width: 1),
                    Expanded(
                      flex: 4,
                      child: _MessagesPanel(
                        messages: chatProvider.messages,
                        selectedRoom: chatProvider.selectedRoom,
                        currentUserId: currentUserId,
                        isLoading: chatProvider.messagesLoading,
                        loadUserProfile: _loadUserProfile,
                        scrollController: _scrollController,
                        onAvatarTap: (userId) {
                          _showUserInfo(context, userId);
                        },
                      ),
                    ),
                  ],
                ),
              ),
              SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.surfaceContainer,
                      borderRadius: BorderRadius.circular(24),
                    ),
                    child: Row(
                      children: [
                        const SizedBox(width: 10),
                        Expanded(
                          child: TextField(
                            controller: _controller,
                            textInputAction: TextInputAction.send,
                            onSubmitted: (_) => _sendMessage(),
                            enabled: !chatProvider.isBusy,
                            decoration: const InputDecoration(
                              hintText: 'Nhập tin nhắn...',
                              border: InputBorder.none,
                              isDense: true,
                            ),
                          ),
                        ),
                        IconButton(
                          tooltip: 'Gửi ảnh',
                          onPressed: chatProvider.isBusy
                              ? null
                              : _showImagePickerOptions,
                          icon: chatProvider.uploadingImage
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Icon(Icons.image_outlined),
                        ),
                        IconButton.filled(
                          tooltip: 'Gửi',
                          onPressed: chatProvider.isBusy ? null : _sendMessage,
                          icon: chatProvider.sending
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Icon(Icons.send_rounded),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _RoomsPanel extends StatelessWidget {
  const _RoomsPanel({
    required this.rooms,
    required this.selectedRoomId,
    required this.isLoading,
    required this.currentUserId,
    required this.subtitleBuilder,
    required this.onRoomInfoTap,
    required this.onSelectRoom,
  });

  final List<ChatRoomModel> rooms;
  final String? selectedRoomId;
  final bool isLoading;
  final String currentUserId;
  final String Function(ChatRoomModel room, String currentUserId)
  subtitleBuilder;
  final ValueChanged<ChatRoomModel> onRoomInfoTap;
  final ValueChanged<String> onSelectRoom;

  @override
  Widget build(BuildContext context) {
    if (isLoading && rooms.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    if (rooms.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(16),
          child: Text(
            'Chưa có phòng chat.\nPhòng sẽ được tạo khi có carrier nhận đơn.',
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    return ListView.separated(
      itemCount: rooms.length,
      separatorBuilder: (_, _) => const Divider(height: 1),
      itemBuilder: (context, index) {
        final room = rooms[index];
        final isSelected = room.id == selectedRoomId;
        return ListTile(
          selected: isSelected,
          dense: true,
          contentPadding: const EdgeInsets.symmetric(horizontal: 12),
          minLeadingWidth: 40,
          leading: InkWell(
            onTap: () => onRoomInfoTap(room),
            customBorder: const CircleBorder(),
            child: const CircleAvatar(child: Icon(Icons.group_outlined)),
          ),
          subtitle: Text(
            subtitleBuilder(room, currentUserId),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          onTap: () => onSelectRoom(room.id),
        );
      },
    );
  }
}

class _MessagesPanel extends StatelessWidget {
  const _MessagesPanel({
    required this.messages,
    required this.selectedRoom,
    required this.currentUserId,
    required this.isLoading,
    required this.loadUserProfile,
    required this.scrollController,
    required this.onAvatarTap,
  });

  final List<ChatMessageModel> messages;
  final ChatRoomModel? selectedRoom;
  final String currentUserId;
  final bool isLoading;
  final Future<Map<String, dynamic>?> Function(String userId) loadUserProfile;
  final ScrollController scrollController;
  final ValueChanged<String> onAvatarTap;

  String _displayName(Map<String, dynamic>? profile, String userId) {
    final name = (profile?['name'] as String?)?.trim();
    final accountId = (profile?['accountId'] as String?)?.trim();
    if (name != null && name.isNotEmpty) {
      return name;
    }
    if (accountId != null && accountId.isNotEmpty) {
      return accountId;
    }
    return userId;
  }

  String? _avatarUrl(Map<String, dynamic>? profile) {
    final value = (profile?['avatarUrl'] as String?)?.trim();
    if (value != null && value.isNotEmpty) {
      return value;
    }
    return null;
  }

  Widget _buildAvatar(String userId, String displayName, String? avatarUrl) {
    final initials = displayName.isNotEmpty
        ? displayName[0].toUpperCase()
        : (userId.isNotEmpty ? userId[0].toUpperCase() : '?');

    return CircleAvatar(
      radius: 16,
      backgroundImage: avatarUrl != null ? NetworkImage(avatarUrl) : null,
      child: avatarUrl == null
          ? Text(
              initials,
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
            )
          : null,
    );
  }

  Widget _buildAvatarButton(
    String userId,
    String displayName,
    String? avatarUrl,
  ) {
    return InkWell(
      onTap: () => onAvatarTap(userId),
      customBorder: const CircleBorder(),
      child: _buildAvatar(userId, displayName, avatarUrl),
    );
  }

  Widget _buildMessageBlock(
    BuildContext context,
    ChatMessageModel message,
    Map<String, dynamic>? profile,
  ) {
    final isMe = message.senderId == currentUserId;
    final displayName = _displayName(profile, message.senderId);
    final avatarUrl = _avatarUrl(profile);
    final content = _buildMessageContent(context, message, isMe);

    final header = Row(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: isMe ? MainAxisAlignment.end : MainAxisAlignment.start,
      children: isMe
          ? [
              Text(displayName, style: Theme.of(context).textTheme.labelSmall),
              const SizedBox(width: 8),
              _buildAvatarButton(message.senderId, displayName, avatarUrl),
            ]
          : [
              _buildAvatarButton(message.senderId, displayName, avatarUrl),
              const SizedBox(width: 8),
              Text(displayName, style: Theme.of(context).textTheme.labelSmall),
            ],
    );

    final body = Column(
      crossAxisAlignment: isMe
          ? CrossAxisAlignment.end
          : CrossAxisAlignment.start,
      children: [header, const SizedBox(height: 4), content],
    );

    return Align(
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: body,
      ),
    );
  }

  Widget _buildMessageContent(
    BuildContext context,
    ChatMessageModel message,
    bool isMe,
  ) {
    if (message.type == 'image') {
      return ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 280, maxHeight: 320),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: Image.network(
            message.content,
            fit: BoxFit.cover,
            errorBuilder: (context, error, stackTrace) {
              return Container(
                width: 220,
                height: 140,
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                alignment: Alignment.center,
                child: const Text('Ảnh lỗi'),
              );
            },
          ),
        ),
      );
    }

    return ChatBubble(text: message.content, isMe: isMe);
  }

  @override
  Widget build(BuildContext context) {
    if (selectedRoom == null) {
      return const Center(child: Text('Chọn một cuộc trò chuyện để bắt đầu.'));
    }

    if (isLoading && messages.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    if (messages.isEmpty) {
      return const Center(child: Text('Chưa có tin nhắn.'));
    }

    return ListView.builder(
      controller: scrollController,
      padding: const EdgeInsets.all(12),
      itemCount: messages.length,
      itemBuilder: (context, index) {
        final message = messages[index];
        return FutureBuilder<Map<String, dynamic>?>(
          future: loadUserProfile(message.senderId),
          builder: (context, snapshot) {
            final profile = snapshot.data;
            final messageBlock = _buildMessageBlock(context, message, profile);
            return messageBlock;
          },
        );
      },
    );
  }
}
