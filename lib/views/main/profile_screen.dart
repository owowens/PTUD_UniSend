import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../services/auth_service.dart';
import '../../services/firestore_service.dart';
import '../../services/storage_service.dart';
import '../../services/user_session_service.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({
    super.key,
    required this.isDarkMode,
    required this.onThemeModeChanged,
  });

  final bool isDarkMode;
  final ValueChanged<bool> onThemeModeChanged;

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  static const String _developerFacebookUrl =
      'https://www.facebook.com/share/1C6EfmQXL2/?mibextid=wwXIfr';
  static const String _developerZaloQrAsset = 'maZL.jpg';
  static const List<String> _bankOptions = [
    'Vietcombank',
    'VietinBank',
    'BIDV',
    'Agribank',
    'Techcombank',
    'ACB',
    'Sacombank',
    'MB Bank',
    'VPBank',
    'TPBank',
  ];
  final AuthService _authService = AuthService();
  final FirestoreService _firestoreService = FirestoreService();
  final StorageService _storageService = StorageService();
  final ImagePicker _imagePicker = ImagePicker();

  bool _isLoadingProfile = true;
  bool _isSavingProfile = false;
  bool _isUploadingAvatar = false;
  bool _isSubmittingVerification = false;

  String _displayName = 'Người dùng UniSend';
  String _email = 'user@unisend.app';
  String? _accountId;
  String? _phone;
  String? _address;
  String? _birthday;
  String? _avatarUrl;
  String? _bankName;
  String? _bankAccountNumber;
  String? _verificationImageUrl;
  bool _isVerified = false;

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  String _inferNameFromEmail(String email, String fallbackId) {
    if (email.contains('@')) {
      return email.split('@').first;
    }
    return 'user_${fallbackId.substring(0, 6)}';
  }

  Future<void> _loadProfile() async {
    final user = _authService.currentUser;
    if (user == null) {
      setState(() {
        _isLoadingProfile = false;
      });
      return;
    }

    try {
      final profile = await _firestoreService.getUserProfile(user.uid);
      if (!mounted) {
        return;
      }

      final resolvedEmail =
          user.email ?? (profile?['email'] as String?) ?? 'user@unisend.app';
      final displayName = user.displayName?.trim();
      final resolvedName =
          (profile?['name'] as String?)?.trim() ??
          (displayName != null && displayName.isNotEmpty
              ? displayName
              : _inferNameFromEmail(resolvedEmail, user.uid));

      setState(() {
        _displayName = resolvedName;
        _email = resolvedEmail;
        _accountId = (profile?['accountId'] as String?)?.trim();
        _phone = (profile?['phone'] as String?)?.trim();
        _address = (profile?['address'] as String?)?.trim();
        _birthday = (profile?['birthday'] as String?)?.trim();
        _avatarUrl = (profile?['avatarUrl'] as String?)?.trim();
        _bankName = (profile?['bankName'] as String?)?.trim();
        _bankAccountNumber = (profile?['bankAccountNumber'] as String?)?.trim();
        _verificationImageUrl = (profile?['verificationImageUrl'] as String?)
            ?.trim();
        _isVerified = profile?['isVerified'] == true;
        _isLoadingProfile = false;
      });
      if (context.mounted) {
        context.read<UserSessionService>().setCurrentAccountId(
          _accountId ?? '',
        );
      }
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() {
        _isLoadingProfile = false;
      });
      _showUiNotice(context, 'Không thể tải hồ sơ. Vui lòng thử lại.');
    }
  }

  void _showVerificationImage(BuildContext context) {
    final url = _verificationImageUrl;
    if (url == null || url.trim().isEmpty) {
      _showUiNotice(context, 'Vui lòng thêm ảnh xác thực.');
      return;
    }

    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Ảnh xác thực tài khoản'),
        content: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: Image.network(
            url,
            fit: BoxFit.cover,
            errorBuilder: (context, error, stackTrace) => const SizedBox(
              height: 120,
              child: Center(child: Text('Không thể tải ảnh xác thực.')),
            ),
          ),
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

  Future<void> _showDeveloperContactInfo(BuildContext context) async {
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Thông tin liên hệ của nhà phát triển'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Quét QR bên dưới để liên hệ Zalo:',
                style: Theme.of(dialogContext).textTheme.bodyMedium,
              ),
              const SizedBox(height: 12),
              ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: SizedBox(
                  height: 220,
                  child: Image.asset(
                    _developerZaloQrAsset,
                    fit: BoxFit.contain,
                    errorBuilder: (context, error, stackTrace) =>
                        const SizedBox(
                          height: 180,
                          child: Center(
                            child: Text('Không thể tải ảnh QR Zalo.'),
                          ),
                        ),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'Facebook:',
                style: Theme.of(dialogContext).textTheme.titleSmall,
              ),
              const SizedBox(height: 4),
              SelectableText(_developerFacebookUrl),
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: () async {
                    final uri = Uri.parse(_developerFacebookUrl);
                    if (!await launchUrl(
                      uri,
                      mode: LaunchMode.externalApplication,
                    )) {
                      if (dialogContext.mounted) {
                        _showUiNotice(
                          dialogContext,
                          'Không thể mở liên kết Facebook.',
                        );
                      }
                    }
                  },
                  icon: const Icon(Icons.open_in_new_outlined),
                  label: const Text('Mở Facebook'),
                ),
              ),
            ],
          ),
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

  void _showUiNotice(BuildContext context, String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
    );
  }

  String _maskAccountNumber(String? accountNumber) {
    if (accountNumber == null || accountNumber.trim().isEmpty) {
      return '---';
    }
    final normalized = accountNumber.replaceAll(RegExp(r'\s+'), '');
    if (normalized.length <= 4) {
      return normalized;
    }
    final last4 = normalized.substring(normalized.length - 4);
    return '**** **** $last4';
  }

  Future<ImageSource?> _pickAvatarSource(BuildContext context) {
    return showModalBottomSheet<ImageSource>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined),
              title: const Text('Chụp ảnh'),
              onTap: () => Navigator.of(sheetContext).pop(ImageSource.camera),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('Chọn từ thư viện'),
              onTap: () => Navigator.of(sheetContext).pop(ImageSource.gallery),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _handleUpdateAvatar(BuildContext context) async {
    if (_isUploadingAvatar) {
      return;
    }

    final user = _authService.currentUser;
    if (user == null) {
      _showUiNotice(context, 'Vui lòng đăng nhập để cập nhật avatar.');
      return;
    }

    final source = await _pickAvatarSource(context);
    if (source == null) {
      return;
    }

    try {
      setState(() {
        _isUploadingAvatar = true;
      });

      final pickedFile = await _imagePicker.pickImage(
        source: source,
        imageQuality: 85,
      );

      if (!mounted || pickedFile == null) {
        return;
      }

      final uploadedImageUrl = await _storageService.uploadImage(
        file: pickedFile,
        isAvatar: true,
      );

      if (!context.mounted) {
        return;
      }

      if (uploadedImageUrl == null || uploadedImageUrl.trim().isEmpty) {
        _showUiNotice(context, 'Upload avatar thất bại. Vui lòng thử lại.');
        return;
      }

      await _saveProfile(
        name: _displayName,
        phone: _phone,
        address: _address,
        birthday: _birthday,
        avatarUrl: uploadedImageUrl,
      );
    } catch (_) {
      if (!context.mounted) {
        return;
      }
      _showUiNotice(context, 'Không thể cập nhật avatar. Vui lòng thử lại.');
    } finally {
      if (mounted) {
        setState(() {
          _isUploadingAvatar = false;
        });
      }
    }
  }

  Future<void> _saveProfile({
    required String name,
    String? accountId,
    String? phone,
    String? address,
    String? birthday,
    String? avatarUrl,
  }) async {
    final user = _authService.currentUser;
    if (user == null) {
      _showUiNotice(context, 'Vui lòng đăng nhập để cập nhật hồ sơ.');
      return;
    }

    setState(() {
      _isSavingProfile = true;
    });

    final trimmedName = name.trim().isEmpty ? _displayName : name.trim();
    final resolvedEmail = user.email ?? _email;
    final normalizedPhone = phone?.trim().isEmpty == true
        ? null
        : phone?.trim();
    final normalizedAddress = address?.trim().isEmpty == true
        ? null
        : address?.trim();
    final normalizedBirthday = birthday?.trim().isEmpty == true
        ? null
        : birthday?.trim();
    final normalizedAccountId = accountId?.trim().isEmpty == true
        ? null
        : accountId?.trim();
    final resolvedAvatarUrl = avatarUrl?.trim().isEmpty == true
        ? null
        : avatarUrl?.trim();

    try {
      await _firestoreService.saveUserProfile(
        userId: user.uid,
        name: trimmedName,
        accountId: normalizedAccountId ?? _accountId,
        email: resolvedEmail,
        isVerified: _isVerified,
        avatarUrl: resolvedAvatarUrl ?? _avatarUrl,
        phone: normalizedPhone ?? _phone,
        address: normalizedAddress ?? _address,
        birthday: normalizedBirthday ?? _birthday,
      );

      if (!mounted) {
        return;
      }

      setState(() {
        _displayName = trimmedName;
        _email = resolvedEmail;
        _accountId = normalizedAccountId ?? _accountId;
        _phone = normalizedPhone ?? _phone;
        _address = normalizedAddress ?? _address;
        _birthday = normalizedBirthday ?? _birthday;
        _avatarUrl = resolvedAvatarUrl ?? _avatarUrl;
      });

      _showUiNotice(context, 'Đã cập nhật hồ sơ.');
    } catch (_) {
      if (!mounted) {
        return;
      }
      _showUiNotice(context, 'Không thể cập nhật hồ sơ. Vui lòng thử lại.');
    } finally {
      if (mounted) {
        setState(() {
          _isSavingProfile = false;
        });
      }
    }
  }

  Future<void> _openEditProfileSheet(BuildContext context) async {
    if (_isLoadingProfile) {
      return;
    }

    final user = _authService.currentUser;
    if (user == null) {
      _showUiNotice(context, 'Vui lòng đăng nhập để chỉnh sửa hồ sơ.');
      return;
    }

    final draft = await showModalBottomSheet<_ProfileDraft>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) => _ProfileEditSheet(
        name: _displayName,
        email: _email,
        accountId: _accountId ?? '',
        phone: _phone ?? '',
        address: _address ?? '',
        birthday: _birthday ?? '',
        formatDate: _formatDate,
        tryParseDate: _tryParseDate,
      ),
    );

    if (draft == null) {
      return;
    }

    await _saveProfile(
      name: draft.name,
      accountId: draft.accountId,
      phone: draft.phone,
      address: draft.address,
      birthday: draft.birthday,
    );
  }

  Future<void> _handleSignOut(BuildContext context) async {
    final shouldSignOut = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Xác nhận đăng xuất'),
        content: const Text('Bạn có chắc muốn đăng xuất không?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Hủy'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Đăng xuất'),
          ),
        ],
      ),
    );

    if (shouldSignOut != true) {
      return;
    }

    try {
      await AuthService().signOut();
    } catch (_) {
      if (!context.mounted) {
        return;
      }
      _showUiNotice(context, 'Không thể đăng xuất. Vui lòng thử lại.');
    }
  }

  Future<void> _openPaymentLinkSheet(BuildContext context) async {
    final result = await showModalBottomSheet<_PaymentLinkDraft>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) => _PaymentLinkSheet(banks: _bankOptions),
    );

    if (!context.mounted || result == null) {
      return;
    }

    final user = _authService.currentUser;
    if (user == null) {
      _showUiNotice(context, 'Vui lòng đăng nhập để lưu tài khoản ngân hàng.');
      return;
    }

    try {
      await _firestoreService.saveUserBankAccount(
        userId: user.uid,
        accountNumber: result.accountNumber,
        bankName: result.bank,
      );
      if (!context.mounted) {
        return;
      }
      setState(() {
        _bankName = result.bank;
        _bankAccountNumber = result.accountNumber;
      });
      await showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Đã lưu tài khoản ngân hàng'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Ngân hàng: ${result.bank}'),
              const SizedBox(height: 8),
              Text('Số tài khoản: ${result.accountNumber}'),
            ],
          ),
          actions: [
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('OK'),
            ),
          ],
        ),
      );
      if (!context.mounted) {
        return;
      }
      _showUiNotice(context, 'Lưu tài khoản ngân hàng thành công.');
    } catch (_) {
      if (!context.mounted) {
        return;
      }
      _showUiNotice(
        context,
        'Không thể lưu tài khoản ngân hàng. Vui lòng thử lại.',
      );
    }
  }

  Future<void> _openVerificationSheet(BuildContext context) async {
    if (_isSubmittingVerification) {
      return;
    }

    final user = _authService.currentUser;
    if (user == null) {
      _showUiNotice(context, 'Vui lòng đăng nhập để xác thực tài khoản.');
      return;
    }

    final result = await showModalBottomSheet<_VerificationDraft>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) => _VerificationSheet(imagePicker: _imagePicker),
    );

    if (!context.mounted || result == null) {
      return;
    }

    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Xác nhận tải thông tin'),
        content: const Text(
          'Bạn phải hoàn toàn chịu trách nhiệm đối với thông tin mình tải lên.',
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Tôi đã hiểu'),
          ),
        ],
      ),
    );

    if (!context.mounted) {
      return;
    }

    try {
      setState(() {
        _isSubmittingVerification = true;
      });

      final uploadedUrl = await _storageService.uploadVerificationImage(
        file: result.imageFile,
      );

      if (!context.mounted) {
        return;
      }

      if (uploadedUrl == null || uploadedUrl.trim().isEmpty) {
        _showUiNotice(context, 'Tải ảnh xác thực thất bại. Vui lòng thử lại.');
        return;
      }

      await _firestoreService.saveUserVerification(
        userId: user.uid,
        imageUrl: uploadedUrl,
      );

      if (!context.mounted) {
        return;
      }

      setState(() {
        _isVerified = false;
      });

      _showUiNotice(context, 'Đã gửi thông tin xác thực. Vui lòng chờ duyệt.');
    } catch (_) {
      if (!context.mounted) {
        return;
      }
      _showUiNotice(context, 'Không thể gửi xác thực. Vui lòng thử lại.');
    } finally {
      if (mounted) {
        setState(() {
          _isSubmittingVerification = false;
        });
      }
    }
  }

  DateTime? _tryParseDate(String value) {
    try {
      if (value.trim().isEmpty) {
        return null;
      }
      final parts = value.split('-');
      if (parts.length != 3) {
        return null;
      }
      final year = int.parse(parts[0]);
      final month = int.parse(parts[1]);
      final day = int.parse(parts[2]);
      return DateTime(year, month, day);
    } catch (_) {
      return null;
    }
  }

  String _formatDate(DateTime date) {
    final month = date.month.toString().padLeft(2, '0');
    final day = date.day.toString().padLeft(2, '0');
    return '${date.year}-$month-$day';
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
            onPressed: _isLoadingProfile
                ? null
                : () => _openEditProfileSheet(context),
            icon: const Icon(Icons.edit_outlined),
          ),
        ],
      ),
      body: SafeArea(
        child: _isLoadingProfile
            ? const Center(child: CircularProgressIndicator())
            : SingleChildScrollView(
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
                              backgroundImage:
                                  _avatarUrl != null && _avatarUrl!.isNotEmpty
                                  ? NetworkImage(_avatarUrl!)
                                  : null,
                              child:
                                  _avatarUrl != null && _avatarUrl!.isNotEmpty
                                  ? null
                                  : Icon(
                                      Icons.person,
                                      size: 42,
                                      color: colorScheme.onPrimaryContainer,
                                    ),
                            ),
                            const SizedBox(height: 12),
                            Text(
                              _displayName,
                              style: Theme.of(context).textTheme.titleLarge,
                            ),
                            const SizedBox(height: 4),
                            Text(
                              _email,
                              style: Theme.of(context).textTheme.bodyMedium
                                  ?.copyWith(
                                    color: colorScheme.onSurfaceVariant,
                                  ),
                            ),
                            const SizedBox(height: 10),
                            OutlinedButton.icon(
                              onPressed: _isUploadingAvatar
                                  ? null
                                  : () => _handleUpdateAvatar(context),
                              icon: _isUploadingAvatar
                                  ? const SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    )
                                  : const Icon(Icons.photo_camera_outlined),
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
                            value: widget.isDarkMode,
                            onChanged: widget.onThemeModeChanged,
                            title: const Text('Chế độ sáng/tối'),
                            subtitle: Text(
                              widget.isDarkMode
                                  ? 'Đang ở chế độ tối toàn ứng dụng.'
                                  : 'Đang ở chế độ sáng toàn ứng dụng.',
                            ),
                            secondary: Icon(
                              widget.isDarkMode
                                  ? Icons.dark_mode_outlined
                                  : Icons.light_mode_outlined,
                            ),
                          ),
                          const Divider(height: 1),
                          ListTile(
                            leading: const Icon(Icons.phone_outlined),
                            title: const Text('Số điện thoại'),
                            subtitle: Text(
                              _phone == null || _phone!.isEmpty
                                  ? '---'
                                  : _phone!,
                            ),
                          ),
                          const Divider(height: 1),
                          ListTile(
                            leading: const Icon(Icons.badge_outlined),
                            title: const Text('Mã tài khoản'),
                            subtitle: Text(
                              _accountId == null || _accountId!.isEmpty
                                  ? '---'
                                  : _accountId!,
                            ),
                          ),
                          const Divider(height: 1),
                          ListTile(
                            leading: const Icon(Icons.cake_outlined),
                            title: const Text('Ngày sinh'),
                            subtitle: Text(
                              _birthday == null || _birthday!.isEmpty
                                  ? '---'
                                  : _birthday!,
                            ),
                          ),
                          const Divider(height: 1),
                          ListTile(
                            leading: const Icon(Icons.location_on_outlined),
                            title: const Text('Địa chỉ'),
                            subtitle: Text(
                              _address == null || _address!.isEmpty
                                  ? '---'
                                  : _address!,
                            ),
                          ),
                          const Divider(height: 1),
                          ListTile(
                            leading: const Icon(
                              Icons.account_balance_wallet_outlined,
                            ),
                            title: const Text('Ngân hàng'),
                            subtitle: Text(
                              _bankName == null || _bankName!.isEmpty
                                  ? '---'
                                  : _bankName!,
                            ),
                          ),
                          const Divider(height: 1),
                          ListTile(
                            leading: const Icon(Icons.credit_card_outlined),
                            title: const Text('Số tài khoản'),
                            subtitle: Text(
                              _maskAccountNumber(_bankAccountNumber),
                            ),
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
                              onPressed: _isSubmittingVerification
                                  ? null
                                  : () => _openVerificationSheet(context),
                              icon: _isSubmittingVerification
                                  ? const SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    )
                                  : const Icon(Icons.verified_user_outlined),
                              label: const Text('Xác thực tài khoản'),
                            ),
                            const SizedBox(height: 8),
                            OutlinedButton.icon(
                              onPressed: () => _showVerificationImage(context),
                              icon: const Icon(Icons.image_outlined),
                              label: const Text('Xem ảnh xác thực'),
                            ),
                            const SizedBox(height: 8),
                            FilledButton.tonalIcon(
                              onPressed: () => _openPaymentLinkSheet(context),
                              icon: const Icon(Icons.account_balance_outlined),
                              label: const Text('Liên kết thanh toán'),
                            ),
                            const SizedBox(height: 8),
                            FilledButton.tonalIcon(
                              onPressed: () =>
                                  _showDeveloperContactInfo(context),
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
                              onPressed: () => _handleSignOut(context),
                              icon: const Icon(Icons.logout),
                              label: const Text('Đăng xuất'),
                            ),
                          ],
                        ),
                      ),
                    ),
                    if (_isSavingProfile) ...[
                      const SizedBox(height: 12),
                      const LinearProgressIndicator(),
                    ],
                  ],
                ),
              ),
      ),
    );
  }
}

class _ProfileDraft {
  const _ProfileDraft({
    required this.name,
    this.accountId,
    this.phone,
    this.address,
    this.birthday,
  });

  final String name;
  final String? accountId;
  final String? phone;
  final String? address;
  final String? birthday;
}

class _ProfileEditSheet extends StatefulWidget {
  const _ProfileEditSheet({
    required this.name,
    required this.email,
    required this.accountId,
    required this.phone,
    required this.address,
    required this.birthday,
    required this.formatDate,
    required this.tryParseDate,
  });

  final String name;
  final String email;
  final String accountId;
  final String phone;
  final String address;
  final String birthday;
  final String Function(DateTime) formatDate;
  final DateTime? Function(String) tryParseDate;

  @override
  State<_ProfileEditSheet> createState() => _ProfileEditSheetState();
}

class _ProfileEditSheetState extends State<_ProfileEditSheet> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late final TextEditingController _emailController;
  late final TextEditingController _accountIdController;
  late final TextEditingController _phoneController;
  late final TextEditingController _addressController;
  late final TextEditingController _birthdayController;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.name);
    _emailController = TextEditingController(text: widget.email);
    _accountIdController = TextEditingController(text: widget.accountId);
    _phoneController = TextEditingController(text: widget.phone);
    _addressController = TextEditingController(text: widget.address);
    _birthdayController = TextEditingController(text: widget.birthday);
  }

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _accountIdController.dispose();
    _phoneController.dispose();
    _addressController.dispose();
    _birthdayController.dispose();
    super.dispose();
  }

  Future<void> _pickBirthday() async {
    final now = DateTime.now();
    final initialDate =
        widget.tryParseDate(_birthdayController.text) ??
        DateTime(now.year - 18, now.month, now.day);
    final pickedDate = await showDatePicker(
      context: context,
      initialDate: initialDate,
      firstDate: DateTime(1900),
      lastDate: now,
    );
    if (!mounted) {
      return;
    }
    if (pickedDate != null) {
      _birthdayController.text = widget.formatDate(pickedDate);
    }
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) {
      return;
    }
    Navigator.of(context).pop(
      _ProfileDraft(
        name: _nameController.text.trim(),
        accountId: _accountIdController.text.trim(),
        phone: _phoneController.text.trim(),
        address: _addressController.text.trim(),
        birthday: _birthdayController.text.trim(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 8,
        bottom: MediaQuery.of(context).viewInsets.bottom + 16,
      ),
      child: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Chỉnh sửa hồ sơ',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _nameController,
                decoration: const InputDecoration(labelText: 'Họ và tên'),
                validator: (value) => value == null || value.trim().isEmpty
                    ? 'Vui lòng nhập họ và tên'
                    : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _emailController,
                enabled: false,
                decoration: const InputDecoration(labelText: 'Email'),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _accountIdController,
                decoration: const InputDecoration(labelText: 'Mã tài khoản'),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _phoneController,
                keyboardType: TextInputType.phone,
                decoration: const InputDecoration(labelText: 'Số điện thoại'),
                validator: (value) {
                  final normalized =
                      value?.replaceAll(RegExp(r'\s+'), '') ?? '';
                  if (normalized.isEmpty) {
                    return null;
                  }
                  if (!RegExp(r'^\d{10}$').hasMatch(normalized)) {
                    return 'Số điện thoại phải gồm 10 chữ số';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _birthdayController,
                readOnly: true,
                decoration: const InputDecoration(
                  labelText: 'Ngày sinh',
                  suffixIcon: Icon(Icons.calendar_today_outlined),
                ),
                onTap: _pickBirthday,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _addressController,
                decoration: const InputDecoration(labelText: 'Địa chỉ'),
                maxLines: 2,
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: _submit,
                  child: const Text('Lưu'),
                ),
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }
}

class _PaymentLinkDraft {
  const _PaymentLinkDraft({required this.accountNumber, required this.bank});

  final String accountNumber;
  final String bank;
}

class _PaymentLinkSheet extends StatefulWidget {
  const _PaymentLinkSheet({required this.banks});

  final List<String> banks;

  @override
  State<_PaymentLinkSheet> createState() => _PaymentLinkSheetState();
}

class _PaymentLinkSheetState extends State<_PaymentLinkSheet> {
  final _formKey = GlobalKey<FormState>();
  final _accountNumberController = TextEditingController();
  String? _selectedBank;

  @override
  void dispose() {
    _accountNumberController.dispose();
    super.dispose();
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) {
      return;
    }
    if (_selectedBank == null) {
      return;
    }
    Navigator.of(context).pop(
      _PaymentLinkDraft(
        accountNumber: _accountNumberController.text.trim(),
        bank: _selectedBank!,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 8,
        bottom: MediaQuery.of(context).viewInsets.bottom + 16,
      ),
      child: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Liên kết tài khoản ngân hàng',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _accountNumberController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Số tài khoản'),
                validator: (value) {
                  final normalized =
                      value?.replaceAll(RegExp(r'\s+'), '') ?? '';
                  if (normalized.isEmpty) {
                    return 'Vui lòng nhập số tài khoản';
                  }
                  if (!RegExp(r'^\d{6,20}$').hasMatch(normalized)) {
                    return 'Số tài khoản không hợp lệ';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: _selectedBank,
                items: widget.banks
                    .map(
                      (bank) => DropdownMenuItem<String>(
                        value: bank,
                        child: Text(bank),
                      ),
                    )
                    .toList(growable: false),
                onChanged: (value) => setState(() {
                  _selectedBank = value;
                }),
                decoration: const InputDecoration(labelText: 'Ngân hàng'),
                validator: (value) => value == null || value.isEmpty
                    ? 'Vui lòng chọn ngân hàng'
                    : null,
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: _submit,
                  child: const Text('Lưu'),
                ),
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }
}

class _VerificationDraft {
  const _VerificationDraft({required this.imageFile});

  final XFile imageFile;
}

class _VerificationSheet extends StatefulWidget {
  const _VerificationSheet({required this.imagePicker});

  final ImagePicker imagePicker;

  @override
  State<_VerificationSheet> createState() => _VerificationSheetState();
}

class _VerificationSheetState extends State<_VerificationSheet> {
  XFile? _selectedImage;
  bool _isPicking = false;

  Future<void> _pickImage(ImageSource source) async {
    if (_isPicking) {
      return;
    }

    setState(() {
      _isPicking = true;
    });

    try {
      final pickedFile = await widget.imagePicker.pickImage(
        source: source,
        imageQuality: 85,
      );
      if (!mounted) {
        return;
      }
      if (pickedFile != null) {
        setState(() {
          _selectedImage = pickedFile;
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _isPicking = false;
        });
      }
    }
  }

  void _submit() {
    if (_selectedImage == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Vui lòng tải ảnh thẻ sinh viên để xác thực.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }
    Navigator.of(context).pop(_VerificationDraft(imageFile: _selectedImage!));
  }

  @override
  Widget build(BuildContext context) {
    final preview = _selectedImage == null
        ? const Center(child: Text('Chưa chọn ảnh thẻ sinh viên.'))
        : ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Image.file(
              File(_selectedImage!.path),
              height: 180,
              width: double.infinity,
              fit: BoxFit.cover,
            ),
          );

    return Padding(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 8,
        bottom: MediaQuery.of(context).viewInsets.bottom + 16,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Xác thực tài khoản',
              style: Theme.of(context).textTheme.titleLarge,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            Text(
              'Vui lòng cung cấp ảnh thẻ sinh viên để xác thực tài khoản.',
              style: Theme.of(context).textTheme.bodyMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 200),
              child: preview,
            ),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: _isPicking
                  ? null
                  : () => _pickImage(ImageSource.gallery),
              icon: const Icon(Icons.photo_library_outlined),
              label: const Text('Tải ảnh từ thư viện'),
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: _isPicking
                  ? null
                  : () => _pickImage(ImageSource.camera),
              icon: const Icon(Icons.photo_camera_outlined),
              label: const Text('Chụp ảnh trực tiếp'),
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: _submit,
              child: const Text('Xác nhận tải thông tin'),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}
