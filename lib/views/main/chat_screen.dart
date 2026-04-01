import 'package:flutter/material.dart';

class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final TextEditingController _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _showUiOnlyNotice(String label) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('$label đang ở chế độ UI/UX thuần.'),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Trò chuyện'),
        actions: [
          IconButton(
            tooltip: 'Gọi điện',
            onPressed: () => _showUiOnlyNotice('Gọi điện'),
            icon: const Icon(Icons.call_outlined),
          ),
          IconButton(
            tooltip: 'Gọi video',
            onPressed: () => _showUiOnlyNotice('Gọi video'),
            icon: const Icon(Icons.videocam_outlined),
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.forum_outlined,
                      size: 52,
                      color: colorScheme.primary,
                    ),
                    const SizedBox(height: 14),
                    Text(
                      'Chưa có cuộc trò chuyện',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Khung chat hiện tại chỉ là giao diện, chưa kết nối dữ liệu.',
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
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: colorScheme.surfaceContainer,
                  borderRadius: BorderRadius.circular(24),
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 6,
                  ),
                  child: Row(
                    children: [
                      IconButton(
                        tooltip: 'Gửi ảnh',
                        onPressed: () => _showUiOnlyNotice('Gửi ảnh'),
                        icon: const Icon(Icons.image_outlined),
                      ),
                      IconButton(
                        tooltip: 'Gửi âm thanh',
                        onPressed: () => _showUiOnlyNotice('Gửi âm thanh'),
                        icon: const Icon(Icons.mic_outlined),
                      ),
                      IconButton(
                        tooltip: 'Gửi vị trí',
                        onPressed: () => _showUiOnlyNotice('Gửi vị trí'),
                        icon: const Icon(Icons.location_on_outlined),
                      ),
                      Expanded(
                        child: TextField(
                          controller: _controller,
                          textInputAction: TextInputAction.send,
                          onSubmitted: (_) => _showUiOnlyNotice('Gửi tin nhắn'),
                          decoration: const InputDecoration(
                            hintText: 'Nhập tin nhắn...',
                            border: InputBorder.none,
                            isDense: true,
                          ),
                        ),
                      ),
                      IconButton.filled(
                        tooltip: 'Gửi',
                        onPressed: () => _showUiOnlyNotice('Gửi tin nhắn'),
                        icon: const Icon(Icons.send_rounded),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
