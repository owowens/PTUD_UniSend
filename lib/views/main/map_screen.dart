import 'package:flutter/material.dart';

import '../../services/order_service.dart';
import '../../services/user_session_service.dart';

class MapScreen extends StatefulWidget {
  const MapScreen({
    super.key,
    required this.orderService,
    required this.userSessionService,
  });

  final OrderService orderService;
  final UserSessionService userSessionService;

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  static const double _panelMinSize = 0.12;
  static const double _panelMidSize = 0.34;
  static const double _panelMaxSize = 1.0;

  bool _showNearbyPanel = true;
  final DraggableScrollableController _nearbyPanelController =
      DraggableScrollableController();

  final List<_NearbyOrderPreview> _nearbyItems = const [
    _NearbyOrderPreview(
      title: 'Đơn hàng gần khu vực A',
      note: 'Hàng gọn nhẹ, có thể nhận ngay',
      priority: 'Ưu tiên cao',
    ),
    _NearbyOrderPreview(
      title: 'Đơn hàng gần khu vực B',
      note: 'Đang chờ người nhận đơn',
      priority: 'Bình thường',
    ),
    _NearbyOrderPreview(
      title: 'Đơn hàng gần khu vực C',
      note: 'Giao trong ngày, cần theo dõi lộ trình',
      priority: 'Theo dõi',
    ),
  ];

  bool get _isPanelExpanded {
    if (!_nearbyPanelController.isAttached) {
      return false;
    }
    return _nearbyPanelController.size >= 0.95;
  }

  void _animatePanelTo(double size) {
    if (!_nearbyPanelController.isAttached) {
      return;
    }
    _nearbyPanelController.animateTo(
      size,
      duration: const Duration(milliseconds: 240),
      curve: Curves.easeOutCubic,
    );
  }

  void _togglePanelFullscreen() {
    final target = _isPanelExpanded ? _panelMidSize : _panelMaxSize;
    _animatePanelTo(target);
  }

  void _openCreateOrderSheet(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => _CreateOrderSheet(
        orderService: widget.orderService,
        userSessionService: widget.userSessionService,
      ),
    );
  }

  @override
  void dispose() {
    _nearbyPanelController.dispose();
    super.dispose();
  }

  Widget _buildMapBackground(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [scheme.primaryContainer.withAlpha(90), scheme.surface],
        ),
      ),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.map_outlined, size: 52, color: scheme.primary),
            const SizedBox(height: 12),
            const Text(
              'Khu vực bản đồ',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 6),
            Text(
              'Màn hình bản đồ đang ở chế độ UI/UX thuần.',
              textAlign: TextAlign.center,
              style: TextStyle(color: scheme.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNearbyPanel() {
    return DraggableScrollableSheet(
      controller: _nearbyPanelController,
      initialChildSize: _panelMidSize,
      minChildSize: _panelMinSize,
      maxChildSize: _panelMaxSize,
      snap: true,
      snapSizes: const [_panelMinSize, _panelMidSize, _panelMaxSize],
      expand: true,
      builder: (context, scrollController) {
        return Material(
          color: Theme.of(context).colorScheme.surface,
          child: CustomScrollView(
            controller: scrollController,
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 6, 6, 6),
                  child: Column(
                    children: [
                      Container(
                        width: 48,
                        height: 4,
                        decoration: BoxDecoration(
                          color: Theme.of(context).colorScheme.outlineVariant,
                          borderRadius: BorderRadius.circular(99),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Đơn hàng trong khu vực',
                                  style: Theme.of(
                                    context,
                                  ).textTheme.titleMedium,
                                ),
                                const SizedBox(height: 2),
                              ],
                            ),
                          ),
                          AnimatedBuilder(
                            animation: _nearbyPanelController,
                            builder: (context, _) {
                              final expanded = _isPanelExpanded;
                              return IconButton(
                                onPressed: _togglePanelFullscreen,
                                icon: Icon(
                                  expanded
                                      ? Icons.fullscreen_exit_outlined
                                      : Icons.open_in_full_outlined,
                                ),
                                tooltip: expanded
                                    ? 'Thu về kích thước vừa'
                                    : 'Mở toàn màn hình',
                              );
                            },
                          ),
                          IconButton(
                            onPressed: () => _animatePanelTo(_panelMinSize),
                            icon: const Icon(
                              Icons.vertical_align_bottom_outlined,
                            ),
                            tooltip: 'Thu nhỏ danh sách',
                          ),
                          IconButton(
                            onPressed: () {
                              setState(() {
                                _showNearbyPanel = false;
                              });
                            },
                            icon: const Icon(Icons.close_outlined),
                            tooltip: 'Ẩn danh sách',
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(8, 0, 8, 12),
                sliver: SliverList(
                  delegate: SliverChildBuilderDelegate((context, index) {
                    final item = _nearbyItems[index];
                    return Padding(
                      padding: EdgeInsets.only(
                        bottom: index == _nearbyItems.length - 1 ? 0 : 8,
                      ),
                      child: _NearbyOrderUiCard(item: item),
                    );
                  }, childCount: _nearbyItems.length),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: true,
      body: Stack(
        fit: StackFit.expand,
        children: [
          _buildMapBackground(context),
          Positioned(
            top: MediaQuery.of(context).padding.top + 8,
            left: 12,
            right: 12,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surface.withAlpha(230),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Padding(
                padding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                child: Text(
                  'Bản đồ',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
            ),
          ),
          if (_showNearbyPanel) Positioned.fill(child: _buildNearbyPanel()),
          if (!_showNearbyPanel)
            Positioned(
              right: 12,
              bottom: 92,
              child: FloatingActionButton.small(
                onPressed: () {
                  setState(() {
                    _showNearbyPanel = true;
                  });
                },
                tooltip: 'Hiện danh sách đơn hàng',
                child: const Icon(Icons.layers_outlined),
              ),
            ),
        ],
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openCreateOrderSheet(context),
        icon: const Icon(Icons.add_box_outlined),
        label: const Text('Tạo đơn hàng mới'),
      ),
    );
  }
}

class _NearbyOrderUiCard extends StatelessWidget {
  const _NearbyOrderUiCard({required this.item});

  final _NearbyOrderPreview item;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      scheme.secondaryContainer,
                      scheme.primaryContainer,
                    ],
                  ),
                ),
                child: Icon(
                  Icons.inventory_2_outlined,
                  color: scheme.onPrimaryContainer,
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.title,
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(item.note),
                  const SizedBox(height: 8),
                  Chip(
                    visualDensity: VisualDensity.compact,
                    label: Text(item.priority),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            FilledButton.tonal(onPressed: () {}, child: const Text('Nhận đơn')),
          ],
        ),
      ),
    );
  }
}

class _NearbyOrderPreview {
  const _NearbyOrderPreview({
    required this.title,
    required this.note,
    required this.priority,
  });

  final String title;
  final String note;
  final String priority;
}

class _CreateOrderSheet extends StatefulWidget {
  const _CreateOrderSheet({
    required this.orderService,
    required this.userSessionService,
  });

  final OrderService orderService;
  final UserSessionService userSessionService;

  @override
  State<_CreateOrderSheet> createState() => _CreateOrderSheetState();
}

class _CreateOrderSheetState extends State<_CreateOrderSheet> {
  final TextEditingController _titleController = TextEditingController();
  final TextEditingController _descriptionController = TextEditingController();

  final TextEditingController _senderUserIdController = TextEditingController();
  final TextEditingController _receiverUserIdController =
      TextEditingController();

  final TextEditingController _senderNameController = TextEditingController();
  final TextEditingController _senderPhoneController = TextEditingController();
  final TextEditingController _senderAddressController =
      TextEditingController();

  final TextEditingController _receiverNameController = TextEditingController();
  final TextEditingController _receiverPhoneController =
      TextEditingController();
  final TextEditingController _receiverAddressController =
      TextEditingController();

  bool _hasSelectedImage = false;
  bool _createOnBehalf = false;

  @override
  void initState() {
    super.initState();
    _senderUserIdController.text = widget.userSessionService.currentUserId;
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();

    _senderUserIdController.dispose();
    _receiverUserIdController.dispose();

    _senderNameController.dispose();
    _senderPhoneController.dispose();
    _senderAddressController.dispose();
    _receiverNameController.dispose();
    _receiverPhoneController.dispose();
    _receiverAddressController.dispose();
    super.dispose();
  }

  void _showUiOnlyMessage(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
    );
  }

  void _selectImage(String source) {
    setState(() {
      _hasSelectedImage = true;
    });
    _showUiOnlyMessage('Đã chọn ảnh từ $source.');
  }

  void _submitOrder() {
    final currentUserId = widget.userSessionService.currentUserId;
    final title = _titleController.text.trim();
    final receiverId = _receiverUserIdController.text.trim();
    final senderId = _createOnBehalf
        ? _senderUserIdController.text.trim()
        : currentUserId;
    final description = _descriptionController.text.trim().isEmpty
        ? 'Không có mô tả chi tiết.'
        : _descriptionController.text.trim();

    if (title.isEmpty) {
      _showUiOnlyMessage('Vui lòng nhập tiêu đề đơn.');
      return;
    }

    if (senderId.isEmpty) {
      _showUiOnlyMessage('sender_id không được để trống.');
      return;
    }

    if (receiverId.isEmpty) {
      _showUiOnlyMessage('receiver_id không được để trống.');
      return;
    }

    final imageSeed = DateTime.now().millisecondsSinceEpoch;
    final createdOrder = widget.orderService.createOrder(
      currentUserId: currentUserId,
      title: title,
      description: description,
      imageUrl: 'https://picsum.photos/seed/order_$imageSeed/240/240',
      senderId: senderId,
      receiverId: receiverId,
    );

    _showUiOnlyMessage(
      'Đã tạo ${createdOrder.id}. sender_id=${createdOrder.senderId}, created_by=${createdOrder.createdBy}.',
    );
    Navigator.of(context).pop();
  }

  Widget _buildInput(
    String label,
    TextEditingController controller, {
    TextInputType keyboardType = TextInputType.text,
    int minLines = 1,
    int maxLines = 1,
    bool enabled = true,
  }) {
    return TextField(
      controller: controller,
      enabled: enabled,
      keyboardType: keyboardType,
      minLines: minLines,
      maxLines: maxLines,
      decoration: InputDecoration(labelText: label),
    );
  }

  @override
  Widget build(BuildContext context) {
    final currentUserId = widget.userSessionService.currentUserId;

    return Padding(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 12,
        bottom: MediaQuery.of(context).viewInsets.bottom + 16,
      ),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Tạo đơn hàng mới',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 12),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Ảnh hàng hóa',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 10),
                    Container(
                      width: double.infinity,
                      height: 150,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(12),
                        color: Theme.of(
                          context,
                        ).colorScheme.surfaceContainerHighest,
                      ),
                      alignment: Alignment.center,
                      child: _hasSelectedImage
                          ? const Icon(Icons.check_circle_outline, size: 34)
                          : const Icon(Icons.image_outlined, size: 34),
                    ),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        OutlinedButton.icon(
                          onPressed: () => _selectImage('thiết bị'),
                          icon: const Icon(Icons.photo_library_outlined),
                          label: const Text('Chọn từ thiết bị'),
                        ),
                        OutlinedButton.icon(
                          onPressed: () => _selectImage('camera'),
                          icon: const Icon(Icons.camera_alt_outlined),
                          label: const Text('Chụp ảnh'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 10),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Định danh user cho đơn hàng',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 10),
                    Text('current_user: $currentUserId'),
                    const SizedBox(height: 10),
                    SwitchListTile.adaptive(
                      contentPadding: EdgeInsets.zero,
                      value: _createOnBehalf,
                      title: const Text('Tạo đơn hộ người khác'),
                      subtitle: const Text(
                        'Mặc định current_user là sender. Bật tùy chọn này để nhập sender_id khác.',
                      ),
                      onChanged: (enabled) {
                        setState(() {
                          _createOnBehalf = enabled;
                          if (!enabled) {
                            _senderUserIdController.text = currentUserId;
                          }
                        });
                      },
                    ),
                    const SizedBox(height: 8),
                    _buildInput(
                      'sender_id',
                      _senderUserIdController,
                      enabled: _createOnBehalf,
                    ),
                    const SizedBox(height: 10),
                    _buildInput('receiver_id', _receiverUserIdController),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 10),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Thông tin hàng hóa',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 10),
                    _buildInput('Tiêu đề đơn', _titleController),
                    const SizedBox(height: 10),
                    _buildInput(
                      'Mô tả hàng hóa',
                      _descriptionController,
                      minLines: 2,
                      maxLines: 3,
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 10),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Thông tin người gửi',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 10),
                    _buildInput('Tên người gửi', _senderNameController),
                    const SizedBox(height: 10),
                    _buildInput(
                      'Số điện thoại người gửi',
                      _senderPhoneController,
                      keyboardType: TextInputType.phone,
                    ),
                    const SizedBox(height: 10),
                    _buildInput(
                      'Địa chỉ lấy hàng',
                      _senderAddressController,
                      minLines: 2,
                      maxLines: 3,
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 10),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Thông tin người nhận',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 10),
                    _buildInput('Tên người nhận', _receiverNameController),
                    const SizedBox(height: 10),
                    _buildInput(
                      'Số điện thoại người nhận',
                      _receiverPhoneController,
                      keyboardType: TextInputType.phone,
                    ),
                    const SizedBox(height: 10),
                    _buildInput(
                      'Địa chỉ giao hàng',
                      _receiverAddressController,
                      minLines: 2,
                      maxLines: 3,
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _submitOrder,
                icon: const Icon(Icons.check_circle_outline),
                label: const Text('Tạo đơn'),
              ),
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }
}
