import 'package:flutter/material.dart';

class ProfileScreen extends StatelessWidget {
  const ProfileScreen({
    super.key,
    required this.isDarkMode,
    required this.onThemeModeChanged,
  });

  final bool isDarkMode;
  final ValueChanged<bool> onThemeModeChanged;

  void _showUiNotice(BuildContext context, String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Hồ sơ'),
        actions: [
          IconButton(
            tooltip: 'Chỉnh sửa hồ sơ',
            onPressed: () => _showUiNotice(
              context,
              'Màn hình chỉnh sửa hồ sơ đang ở chế độ UI/UX thuần.',
            ),
            icon: const Icon(Icons.edit_outlined),
          ),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    children: [
                      CircleAvatar(
                        radius: 42,
                        backgroundColor: colorScheme.primaryContainer,
                        child: Icon(
                          Icons.person,
                          size: 42,
                          color: colorScheme.onPrimaryContainer,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'Người dùng UniSend',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'user@unisend.app',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 10),
                      OutlinedButton.icon(
                        onPressed: () => _showUiNotice(
                          context,
                          'Tính năng cập nhật avatar đang ở chế độ UI/UX thuần.',
                        ),
                        icon: const Icon(Icons.photo_camera_outlined),
                        label: const Text('Cập nhật avatar'),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Card(
                child: Column(
                  children: [
                    SwitchListTile.adaptive(
                      value: isDarkMode,
                      onChanged: onThemeModeChanged,
                      title: const Text('Chế độ sáng/tối'),
                      subtitle: Text(
                        isDarkMode
                            ? 'Đang ở chế độ tối toàn ứng dụng.'
                            : 'Đang ở chế độ sáng toàn ứng dụng.',
                      ),
                      secondary: Icon(
                        isDarkMode
                            ? Icons.dark_mode_outlined
                            : Icons.light_mode_outlined,
                      ),
                    ),
                    const Divider(height: 1),
                    ListTile(
                      leading: const Icon(Icons.phone_outlined),
                      title: const Text('Số điện thoại'),
                      subtitle: const Text('---'),
                    ),
                    const Divider(height: 1),
                    ListTile(
                      leading: const Icon(Icons.cake_outlined),
                      title: const Text('Ngày sinh'),
                      subtitle: const Text('---'),
                    ),
                    const Divider(height: 1),
                    ListTile(
                      leading: const Icon(Icons.location_on_outlined),
                      title: const Text('Địa chỉ'),
                      subtitle: const Text('---'),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        'Tiện ích tài khoản',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 10),
                      FilledButton.tonalIcon(
                        onPressed: () => _showUiNotice(
                          context,
                          'Màn hình xác thực tài khoản đang ở chế độ UI/UX thuần.',
                        ),
                        icon: const Icon(Icons.verified_user_outlined),
                        label: const Text('Xác thực tài khoản'),
                      ),
                      const SizedBox(height: 8),
                      FilledButton.tonalIcon(
                        onPressed: () => _showUiNotice(
                          context,
                          'Màn hình thanh toán đang ở chế độ UI/UX thuần.',
                        ),
                        icon: const Icon(Icons.account_balance_outlined),
                        label: const Text('Liên kết thanh toán'),
                      ),
                      const SizedBox(height: 8),
                      FilledButton.tonalIcon(
                        onPressed: () => _showUiNotice(
                          context,
                          'Màn hình hỗ trợ đang ở chế độ UI/UX thuần.',
                        ),
                        icon: const Icon(Icons.support_agent_outlined),
                        label: const Text('Liên hệ hỗ trợ'),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      OutlinedButton.icon(
                        onPressed: () => _showUiNotice(
                          context,
                          'Đăng xuất đang ở chế độ UI/UX thuần.',
                        ),
                        icon: const Icon(Icons.logout),
                        label: const Text('Đăng xuất'),
                      ),
                      const SizedBox(height: 8),
                      FilledButton.tonalIcon(
                        style: FilledButton.styleFrom(
                          backgroundColor: colorScheme.errorContainer,
                          foregroundColor: colorScheme.onErrorContainer,
                        ),
                        onPressed: () => _showUiNotice(
                          context,
                          'Xóa tài khoản đang ở chế độ UI/UX thuần.',
                        ),
                        icon: const Icon(Icons.delete_forever_outlined),
                        label: const Text('Xóa tài khoản'),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
