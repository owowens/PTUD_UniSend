import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:image_picker/image_picker.dart';
import 'package:latlong2/latlong.dart';

import '../../models/order.dart';
import '../../services/firestore_service.dart';
import '../../services/location_service.dart';
import '../../services/order_service.dart';
import '../../services/storage_service.dart';
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
  static const double _minMapZoom = 5.0;
  static const double _maxMapZoom = 18.0;
  static const String _osmTileUrlTemplate =
      'https://tile.openstreetmap.org/{z}/{x}/{y}.png';

  bool _showNearbyPanel = true;
  final DraggableScrollableController _nearbyPanelController =
      DraggableScrollableController();
  final MapController _mapController = MapController();
  final LocationService _locationService = LocationService();

  StreamSubscription<Location?>? _locationSubscription;
  Location? _currentLocation;
  bool _isLocating = false;
  bool _isCameraAnimating = false;
  bool _hasMainMapTileError = false;

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

  @override
  void initState() {
    super.initState();
    _bootstrapCurrentLocation();
  }

  Future<void> _bootstrapCurrentLocation() async {
    final serviceEnabled = await _locationService.isLocationServiceEnabled();
    if (!serviceEnabled) {
      return;
    }

    final hasPermission = await _locationService.hasLocationPermission();
    if (!hasPermission) {
      return;
    }

    var location = await _locationService.getCurrentLocation();
    location ??= await _locationService.getLastKnownLocation();

    if (!mounted || location == null) {
      return;
    }

    setState(() {
      _currentLocation = location;
    });

    _moveMapToLocation(location, zoom: 15.5);
    _startLocationTracking();
  }

  bool _isInVietnam(Location location) {
    return location.latitude >= 8.0 &&
        location.latitude <= 24.0 &&
        location.longitude >= 102.0 &&
        location.longitude <= 110.0;
  }

  Future<void> _animateCameraTo(
    LatLng targetCenter, {
    double? zoom,
    Duration duration = const Duration(milliseconds: 320),
  }) async {
    if (!mounted || _isCameraAnimating) {
      return;
    }

    _isCameraAnimating = true;
    final startCenter = _mapController.camera.center;
    final startZoom = _mapController.camera.zoom;
    final endZoom = (zoom ?? startZoom).clamp(_minMapZoom, _maxMapZoom);
    const steps = 12;
    final stepMs = (duration.inMilliseconds / steps).round();

    for (var i = 1; i <= steps; i++) {
      if (!mounted) {
        _isCameraAnimating = false;
        return;
      }

      final t = Curves.easeOutCubic.transform(i / steps);
      final nextLat =
          startCenter.latitude +
          (targetCenter.latitude - startCenter.latitude) * t;
      final nextLng =
          startCenter.longitude +
          (targetCenter.longitude - startCenter.longitude) * t;
      final nextZoom = startZoom + (endZoom - startZoom) * t;

      _mapController.move(LatLng(nextLat, nextLng), nextZoom);
      await Future.delayed(Duration(milliseconds: stepMs));
    }

    _isCameraAnimating = false;
  }

  void _moveMapToLocation(Location location, {double zoom = 16}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }

      _animateCameraTo(
        LatLng(location.latitude, location.longitude),
        zoom: zoom,
      );
    });
  }

  Future<void> _zoomBy(double delta) async {
    final camera = _mapController.camera;
    final targetZoom = (camera.zoom + delta).clamp(_minMapZoom, _maxMapZoom);
    await _animateCameraTo(
      camera.center,
      zoom: targetZoom,
      duration: const Duration(milliseconds: 220),
    );
  }

  void _zoomIn() {
    _zoomBy(1);
  }

  void _zoomOut() {
    _zoomBy(-1);
  }

  Future<void> _requestAndCenterCurrentLocation() async {
    if (_isLocating) {
      return;
    }

    setState(() {
      _isLocating = true;
    });

    final serviceEnabled = await _locationService.isLocationServiceEnabled();
    if (!serviceEnabled) {
      await _locationService.openLocationSettings();
      final recheckService = await _locationService.isLocationServiceEnabled();
      if (!recheckService) {
        if (!mounted) {
          return;
        }
        setState(() {
          _isLocating = false;
        });
        _showLocationMessage(
          'GPS đang tắt. Vui lòng bật định vị để xác định vị trí ở Việt Nam.',
        );
        return;
      }
    }

    final deniedForever = await _locationService
        .isLocationPermissionDeniedForever();
    if (deniedForever) {
      await _locationService.openAppSettings();
      if (!mounted) {
        return;
      }
      setState(() {
        _isLocating = false;
      });
      _showLocationMessage(
        'Quyền vị trí đang bị từ chối vĩnh viễn. Vui lòng bật lại trong App Settings.',
      );
      return;
    }

    var hasPermission = await _locationService.hasLocationPermission();
    if (!hasPermission) {
      hasPermission = await _locationService.requestLocationPermission();
    }

    if (!mounted) {
      return;
    }

    if (!hasPermission) {
      setState(() {
        _isLocating = false;
      });
      _showLocationMessage('Chưa có quyền truy cập GPS.');
      return;
    }

    var location = await _locationService.getCurrentLocation();
    location ??= await _locationService.getLastKnownLocation();

    if (!mounted) {
      return;
    }

    setState(() {
      _isLocating = false;
      _currentLocation = location;
    });

    if (location == null) {
      _showLocationMessage(
        'Không lấy được vị trí hiện tại. Nếu đang dùng emulator, hãy đặt mock location ở Việt Nam.',
      );
      return;
    }

    _moveMapToLocation(location, zoom: 16);

    if (_isInVietnam(location)) {
      _showLocationMessage('Đã định vị vị trí hiện tại của bạn.');
    } else {
      _showLocationMessage(
        'Đã lấy GPS nhưng tọa độ đang ngoài Việt Nam (${location.latitude.toStringAsFixed(4)}, ${location.longitude.toStringAsFixed(4)}).',
      );
    }

    _startLocationTracking();
  }

  void _startLocationTracking() {
    _locationSubscription?.cancel();
    _locationSubscription = _locationService
        .watchLocation(distanceFilter: 20)
        .listen((location) {
          if (!mounted || location == null) {
            return;
          }

          setState(() {
            _currentLocation = location;
          });
        });
  }

  void _showLocationMessage(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
    );
  }

  void _handleMainMapTileError(Object error) {
    if (!mounted || _hasMainMapTileError) {
      return;
    }

    setState(() {
      _hasMainMapTileError = true;
    });
    debugPrint('Main map tile error: $error');
  }

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
    _locationSubscription?.cancel();
    _nearbyPanelController.dispose();
    super.dispose();
  }

  Widget _buildMapBackground(BuildContext context) {
    const double defaultLat = 10.7769;
    const double defaultLng = 106.6997;
    final currentCenter = _currentLocation != null
        ? LatLng(_currentLocation!.latitude, _currentLocation!.longitude)
        : const LatLng(defaultLat, defaultLng);
    final courierPoint = _currentLocation != null
        ? LatLng(_currentLocation!.latitude, _currentLocation!.longitude)
        : const LatLng(defaultLat + 0.005, defaultLng + 0.005);

    return Stack(
      fit: StackFit.expand,
      children: [
        FlutterMap(
          mapController: _mapController,
          options: MapOptions(
            initialCenter: currentCenter,
            initialZoom: 15.0,
            minZoom: _minMapZoom,
            maxZoom: _maxMapZoom,
            backgroundColor: const Color(0xFFE9EEF2),
            interactionOptions: const InteractionOptions(
              flags:
                  InteractiveFlag.drag |
                  InteractiveFlag.flingAnimation |
                  InteractiveFlag.pinchMove |
                  InteractiveFlag.pinchZoom |
                  InteractiveFlag.doubleTapZoom |
                  InteractiveFlag.scrollWheelZoom,
            ),
          ),
          children: [
            TileLayer(
              urlTemplate: _osmTileUrlTemplate,
              userAgentPackageName: 'com.example.unisend',
              tileProvider: NetworkTileProvider(
                headers: {'User-Agent': 'UniSend/1.0'},
              ),
              maxNativeZoom: 19,
              errorTileCallback: (tile, error, stackTrace) {
                _handleMainMapTileError(error);
              },
            ),
            MarkerLayer(
              markers: [
                Marker(
                  point: const LatLng(defaultLat, defaultLng),
                  width: 80,
                  height: 90,
                  alignment: Alignment.bottomCenter,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        decoration: BoxDecoration(
                          color: Colors.green,
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: Colors.green.withAlpha(100),
                              blurRadius: 8,
                              spreadRadius: 2,
                            ),
                          ],
                        ),
                        padding: const EdgeInsets.all(8),
                        child: const Icon(
                          Icons.location_on,
                          color: Colors.white,
                          size: 24,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Container(
                        decoration: BoxDecoration(
                          color: Colors.green,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        child: const Text(
                          'A',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                Marker(
                  point: const LatLng(defaultLat + 0.01, defaultLng + 0.01),
                  width: 80,
                  height: 90,
                  alignment: Alignment.bottomCenter,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        decoration: BoxDecoration(
                          color: Colors.red,
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: Colors.red.withAlpha(100),
                              blurRadius: 8,
                              spreadRadius: 2,
                            ),
                          ],
                        ),
                        padding: const EdgeInsets.all(8),
                        child: const Icon(
                          Icons.location_on,
                          color: Colors.white,
                          size: 24,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Container(
                        decoration: BoxDecoration(
                          color: Colors.red,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        child: const Text(
                          'B',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                Marker(
                  point: courierPoint,
                  width: 80,
                  height: 90,
                  alignment: Alignment.bottomCenter,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        decoration: BoxDecoration(
                          color: Colors.blue,
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: Colors.blue.withAlpha(100),
                              blurRadius: 8,
                              spreadRadius: 2,
                            ),
                          ],
                        ),
                        padding: const EdgeInsets.all(8),
                        child: const Icon(
                          Icons.delivery_dining,
                          color: Colors.white,
                          size: 24,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Container(
                        decoration: BoxDecoration(
                          color: Colors.blue,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        child: Text(
                          _currentLocation == null ? 'C' : 'Bạn',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SimpleAttributionWidget(
              source: Text('© OpenStreetMap contributors'),
              alignment: Alignment.bottomLeft,
            ),
          ],
        ),
        if (_hasMainMapTileError)
          Positioned(
            top: MediaQuery.of(context).padding.top + 48,
            left: 12,
            right: 12,
            child: Material(
              color: Colors.transparent,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.errorContainer,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  'Không tải được dữ liệu bản đồ. Hãy kiểm tra mạng trên emulator hoặc thử lại sau.',
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onErrorContainer,
                  ),
                ),
              ),
            ),
          ),
      ],
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
          Positioned(
            right: 12,
            bottom: 168,
            child: FloatingActionButton.small(
              heroTag: 'gps_current_location_fab',
              onPressed: _requestAndCenterCurrentLocation,
              tooltip: 'Lấy vị trí GPS hiện tại',
              child: _isLocating
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.my_location_outlined),
            ),
          ),
          Positioned(
            right: 12,
            bottom: 228,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                FloatingActionButton.small(
                  heroTag: 'map_zoom_in_fab',
                  tooltip: 'Phóng to bản đồ',
                  onPressed: _zoomIn,
                  child: const Icon(Icons.add),
                ),
                const SizedBox(height: 8),
                FloatingActionButton.small(
                  heroTag: 'map_zoom_out_fab',
                  tooltip: 'Thu nhỏ bản đồ',
                  onPressed: _zoomOut,
                  child: const Icon(Icons.remove),
                ),
              ],
            ),
          ),
          if (!_showNearbyPanel)
            Positioned(
              right: 12,
              bottom: 92,
              child: FloatingActionButton.small(
                heroTag: 'show_nearby_panel_fab',
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

  final TextEditingController _receiverNameController = TextEditingController();
  final TextEditingController _receiverPhoneController =
      TextEditingController();

  final LocationService _locationService = LocationService();
  final FirestoreService _firestoreService = FirestoreService();
  final StorageService _storageService = StorageService();
  final ImagePicker _imagePicker = ImagePicker();

  bool _hasSelectedImage = false;
  bool _isSubmitting = false;
  bool _createOnBehalf = false;
  bool _isPickingSenderLocation = false;
  bool _isPickingReceiverLocation = false;

  Location? _senderLocation;
  Location? _receiverLocation;
  File? _selectedImageFile;

  @override
  void initState() {
    super.initState();
    _senderUserIdController.text = widget.userSessionService.currentUserId;
    _prefillSenderLocation();
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();

    _senderUserIdController.dispose();
    _receiverUserIdController.dispose();

    _senderNameController.dispose();
    _senderPhoneController.dispose();
    _receiverNameController.dispose();
    _receiverPhoneController.dispose();
    super.dispose();
  }

  Future<void> _prefillSenderLocation() async {
    final hasPermission = await _locationService.hasLocationPermission();
    if (!hasPermission) {
      return;
    }

    final location = await _locationService.getCurrentLocation();
    if (!mounted || location == null) {
      return;
    }

    setState(() {
      _senderLocation = location;
    });
  }

  String _formatLocationLabel(Location? location) {
    if (location == null) {
      return 'Chưa chọn vị trí trên bản đồ.';
    }

    final address = location.address?.trim();
    if (address != null && address.isNotEmpty) {
      return address;
    }

    return '${location.latitude.toStringAsFixed(5)}, ${location.longitude.toStringAsFixed(5)}';
  }

  Future<void> _pickLocationOnMap({required bool isSender}) async {
    if (isSender && _isPickingSenderLocation) {
      return;
    }
    if (!isSender && _isPickingReceiverLocation) {
      return;
    }

    setState(() {
      if (isSender) {
        _isPickingSenderLocation = true;
      } else {
        _isPickingReceiverLocation = true;
      }
    });

    final selectedLocation = await showModalBottomSheet<Location>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => FractionallySizedBox(
        heightFactor: 0.95,
        child: _MapLocationPickerSheet(
          title: isSender ? 'Chọn địa chỉ lấy hàng' : 'Chọn địa chỉ giao hàng',
          initialLocation: isSender ? _senderLocation : _receiverLocation,
        ),
      ),
    );

    if (!mounted) {
      return;
    }

    setState(() {
      if (isSender) {
        _isPickingSenderLocation = false;
        if (selectedLocation != null) {
          _senderLocation = selectedLocation;
        }
      } else {
        _isPickingReceiverLocation = false;
        if (selectedLocation != null) {
          _receiverLocation = selectedLocation;
        }
      }
    });
  }

  Widget _buildLocationPickerTile({
    required String title,
    required Location? location,
    required bool isLoading,
    required VoidCallback onPick,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: Theme.of(context).textTheme.labelLarge),
          const SizedBox(height: 6),
          Text(
            _formatLocationLabel(location),
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          if (location != null) ...[
            const SizedBox(height: 4),
            Text(
              'Toa do: ${location.latitude.toStringAsFixed(5)}, ${location.longitude.toStringAsFixed(5)}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
          const SizedBox(height: 10),
          OutlinedButton.icon(
            onPressed: isLoading ? null : onPick,
            icon: isLoading
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.map_outlined),
            label: Text(isLoading ? 'Đang mở bản đồ...' : 'Chọn trên bản đồ'),
          ),
        ],
      ),
    );
  }

  void _showUiOnlyMessage(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
    );
  }

  Future<void> _selectImage(String source) async {
    final imageSource = source == 'camera'
        ? ImageSource.camera
        : ImageSource.gallery;

    try {
      final pickedFile = await _imagePicker.pickImage(
        source: imageSource,
        imageQuality: 85,
      );

      if (!mounted || pickedFile == null) {
        return;
      }

      setState(() {
        _selectedImageFile = File(pickedFile.path);
        _hasSelectedImage = true;
      });
    } catch (e) {
      if (!mounted) {
        return;
      }
      _showUiOnlyMessage('Không thể chọn ảnh: $e');
    }
  }

  Future<void> _submitOrder() async {
    if (_isSubmitting) {
      return;
    }

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

    if (_selectedImageFile == null) {
      _showUiOnlyMessage('Vui lòng chọn ảnh món đồ trước khi tạo đơn.');
      return;
    }

    if (_senderLocation == null) {
      _showUiOnlyMessage('Vui lòng chọn địa chỉ lấy hàng trên bản đồ.');
      return;
    }

    if (_receiverLocation == null) {
      _showUiOnlyMessage('Vui lòng chọn địa chỉ giao hàng trên bản đồ.');
      return;
    }

    setState(() {
      _isSubmitting = true;
    });

    try {
      final uploadedImageUrl = await _storageService.uploadImage(
        file: _selectedImageFile!,
        isAvatar: false,
      );

      if (!mounted) {
        return;
      }

      if (uploadedImageUrl == null || uploadedImageUrl.trim().isEmpty) {
        _showUiOnlyMessage('Upload ảnh thất bại. Vui lòng thử lại.');
        return;
      }

      final now = DateTime.now();
      final newOrder = DeliveryOrder(
        id: 'ORD-${now.microsecondsSinceEpoch}',
        title: title,
        description: description,
        imageUrl: uploadedImageUrl,
        senderId: senderId,
        receiverId: receiverId,
        senderLocation: _senderLocation!,
        receiverLocation: _receiverLocation!,
        carrierId: null,
        createdBy: currentUserId,
        status: OrderStatus.waitingCarrier,
        createdAt: now,
        deadlineAt: now.add(const Duration(hours: 4)),
      );

      await _firestoreService.createOrder(newOrder);

      if (!mounted) {
        return;
      }

      _showUiOnlyMessage('Đã tạo đơn và lưu lên Firestore thành công.');
      Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) {
        return;
      }
      _showUiOnlyMessage('Tạo đơn thất bại: $e');
    } finally {
      if (mounted) {
        setState(() {
          _isSubmitting = false;
        });
      }
    }
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
                      child: _selectedImageFile != null
                          ? ClipRRect(
                              borderRadius: BorderRadius.circular(10),
                              child: Image.file(
                                _selectedImageFile!,
                                fit: BoxFit.cover,
                                width: double.infinity,
                                height: 150,
                              ),
                            )
                          : (_hasSelectedImage
                                ? const Icon(
                                    Icons.check_circle_outline,
                                    size: 34,
                                  )
                                : const Icon(Icons.image_outlined, size: 34)),
                    ),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        OutlinedButton.icon(
                          onPressed: _isSubmitting
                              ? null
                              : () => _selectImage('thiết bị'),
                          icon: const Icon(Icons.photo_library_outlined),
                          label: const Text('Chọn từ thiết bị'),
                        ),
                        OutlinedButton.icon(
                          onPressed: _isSubmitting
                              ? null
                              : () => _selectImage('camera'),
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
                    _buildLocationPickerTile(
                      title: 'Địa chỉ lấy hàng',
                      location: _senderLocation,
                      isLoading: _isPickingSenderLocation,
                      onPick: () => _pickLocationOnMap(isSender: true),
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
                    _buildLocationPickerTile(
                      title: 'Địa chỉ giao hàng',
                      location: _receiverLocation,
                      isLoading: _isPickingReceiverLocation,
                      onPick: () => _pickLocationOnMap(isSender: false),
                    ),
                    if (_senderLocation != null &&
                        _receiverLocation != null) ...[
                      const SizedBox(height: 10),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(8),
                          color: Theme.of(
                            context,
                          ).colorScheme.primaryContainer.withAlpha(110),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.route_outlined, size: 18),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'Khoang cach gui -> nhan: ${_senderLocation!.distanceTo(_receiverLocation!).toStringAsFixed(2)} km',
                                style: Theme.of(context).textTheme.bodyMedium,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _isSubmitting ? null : _submitOrder,
                icon: _isSubmitting
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.check_circle_outline),
                label: Text(_isSubmitting ? 'Đang tạo đơn...' : 'Tạo đơn'),
              ),
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }
}

class _MapLocationPickerSheet extends StatefulWidget {
  const _MapLocationPickerSheet({required this.title, this.initialLocation});

  final String title;
  final Location? initialLocation;

  @override
  State<_MapLocationPickerSheet> createState() =>
      _MapLocationPickerSheetState();
}

class _MapLocationPickerSheetState extends State<_MapLocationPickerSheet> {
  static const LatLng _defaultCenter = LatLng(10.7769, 106.6997);
  static const String _pickerTileUrlTemplate =
      'https://tile.openstreetmap.org/{z}/{x}/{y}.png';
  static const double _minPickerZoom = 5.0;
  static const double _maxPickerZoom = 18.0;
  static const double _initialPickerZoom = 15.0;

  final MapController _mapController = MapController();
  final LocationService _locationService = LocationService();

  late LatLng _selectedPoint;
  late double _currentZoom;
  Timer? _resolveDebounce;
  String? _selectedAddress;
  bool _isResolvingAddress = false;
  bool _isLocating = false;
  bool _hasPickerMapTileError = false;

  @override
  void initState() {
    super.initState();
    _currentZoom = _initialPickerZoom;

    if (widget.initialLocation != null) {
      _selectedPoint = LatLng(
        widget.initialLocation!.latitude,
        widget.initialLocation!.longitude,
      );
      _selectedAddress = widget.initialLocation!.address;
    } else {
      _selectedPoint = _defaultCenter;
    }

    if (_selectedAddress == null || _selectedAddress!.trim().isEmpty) {
      _resolveAddressForSelection();
    }
  }

  @override
  void dispose() {
    _resolveDebounce?.cancel();
    super.dispose();
  }

  String _fallbackAddressLabel(LatLng point) {
    return '${point.latitude.toStringAsFixed(5)}, ${point.longitude.toStringAsFixed(5)}';
  }

  void _scheduleAddressResolution() {
    _resolveDebounce?.cancel();
    _resolveDebounce = Timer(const Duration(milliseconds: 600), () {
      _resolveAddressForSelection();
    });
  }

  Future<void> _resolveAddressForSelection() async {
    final targetPoint = _selectedPoint;

    setState(() {
      _isResolvingAddress = true;
    });

    final location = await _locationService.getLocationFromCoordinates(
      targetPoint.latitude,
      targetPoint.longitude,
    );

    if (!mounted) {
      return;
    }

    final stillCurrent =
        (targetPoint.latitude - _selectedPoint.latitude).abs() < 0.000001 &&
        (targetPoint.longitude - _selectedPoint.longitude).abs() < 0.000001;

    if (!stillCurrent) {
      return;
    }

    setState(() {
      _isResolvingAddress = false;
      _selectedAddress = location?.address;
    });
  }

  void _onMapPositionChanged(MapPosition position, bool hasGesture) {
    final center = position.center;
    if (center == null) {
      return;
    }

    final zoom = (position.zoom ?? _currentZoom).clamp(
      _minPickerZoom,
      _maxPickerZoom,
    );

    final centerChanged =
        (center.latitude - _selectedPoint.latitude).abs() > 0.0000001 ||
        (center.longitude - _selectedPoint.longitude).abs() > 0.0000001;
    final zoomChanged = (zoom - _currentZoom).abs() > 0.0001;

    if (!centerChanged && !zoomChanged) {
      return;
    }

    setState(() {
      _selectedPoint = center;
      _currentZoom = zoom;
      if (centerChanged) {
        _selectedAddress = null;
      }
    });

    if (centerChanged) {
      _scheduleAddressResolution();
    }
  }

  void _zoomBy(double delta) {
    final center = _mapController.camera.center;
    final targetZoom = (_currentZoom + delta).clamp(
      _minPickerZoom,
      _maxPickerZoom,
    );
    _mapController.move(center, targetZoom);
    setState(() {
      _selectedPoint = center;
      _currentZoom = targetZoom;
    });
  }

  void _zoomIn() {
    _zoomBy(1);
  }

  void _zoomOut() {
    _zoomBy(-1);
  }

  void _handlePickerTileError(Object error) {
    if (!mounted || _hasPickerMapTileError) {
      return;
    }

    setState(() {
      _hasPickerMapTileError = true;
    });
    debugPrint('Picker map tile error: $error');
  }

  Future<void> _useCurrentLocation() async {
    if (_isLocating) {
      return;
    }

    setState(() {
      _isLocating = true;
    });

    var hasPermission = await _locationService.hasLocationPermission();
    if (!hasPermission) {
      hasPermission = await _locationService.requestLocationPermission();
    }

    if (!mounted) {
      return;
    }

    if (!hasPermission) {
      setState(() {
        _isLocating = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Chưa có quyền truy cập vị trí.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    final location = await _locationService.getCurrentLocation();
    if (!mounted) {
      return;
    }

    setState(() {
      _isLocating = false;
    });

    if (location == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Không lấy được vị trí hiện tại.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    final point = LatLng(location.latitude, location.longitude);
    setState(() {
      _selectedPoint = point;
      _selectedAddress = location.address;
      _currentZoom = 16;
    });
    _mapController.move(point, _currentZoom);
    if ((location.address ?? '').trim().isEmpty) {
      _scheduleAddressResolution();
    }
  }

  void _confirmSelection() {
    final result = Location(
      latitude: _selectedPoint.latitude,
      longitude: _selectedPoint.longitude,
      address: _selectedAddress ?? _fallbackAddressLabel(_selectedPoint),
    );
    Navigator.of(context).pop(result);
  }

  @override
  Widget build(BuildContext context) {
    final addressLabel =
        (_selectedAddress != null && _selectedAddress!.trim().isNotEmpty)
        ? _selectedAddress!
        : _fallbackAddressLabel(_selectedPoint);

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
        actions: [
          IconButton(
            onPressed: () => Navigator.of(context).pop(),
            icon: const Icon(Icons.close),
            tooltip: 'Đóng',
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: Stack(
              fit: StackFit.expand,
              children: [
                FlutterMap(
                  mapController: _mapController,
                  options: MapOptions(
                    initialCenter: _selectedPoint,
                    initialZoom: _currentZoom,
                    minZoom: _minPickerZoom,
                    maxZoom: _maxPickerZoom,
                    backgroundColor: const Color(0xFFE9EEF2),
                    onPositionChanged: _onMapPositionChanged,
                  ),
                  children: [
                    TileLayer(
                      urlTemplate: _pickerTileUrlTemplate,
                      userAgentPackageName: 'com.example.unisend',
                      tileProvider: NetworkTileProvider(
                        headers: {'User-Agent': 'UniSend/1.0'},
                      ),
                      maxNativeZoom: 19,
                      errorTileCallback: (tile, error, stackTrace) {
                        _handlePickerTileError(error);
                      },
                    ),
                    const SimpleAttributionWidget(
                      source: Text('© OpenStreetMap contributors'),
                      alignment: Alignment.bottomLeft,
                    ),
                  ],
                ),
                IgnorePointer(
                  child: Center(
                    child: Transform.translate(
                      offset: const Offset(0, -18),
                      child: const Icon(
                        Icons.location_pin,
                        size: 52,
                        color: Colors.red,
                      ),
                    ),
                  ),
                ),
                Positioned(
                  top: 12,
                  right: 12,
                  child: Material(
                    color: Theme.of(context).colorScheme.surface.withAlpha(225),
                    borderRadius: BorderRadius.circular(12),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          tooltip: 'Phóng to',
                          onPressed: _zoomIn,
                          icon: const Icon(Icons.add),
                        ),
                        const SizedBox(height: 2),
                        IconButton(
                          tooltip: 'Thu nhỏ',
                          onPressed: _zoomOut,
                          icon: const Icon(Icons.remove),
                        ),
                      ],
                    ),
                  ),
                ),
                if (_hasPickerMapTileError)
                  Positioned(
                    top: 12,
                    left: 12,
                    right: 76,
                    child: Material(
                      color: Colors.transparent,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          color: Theme.of(context).colorScheme.errorContainer,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          'Không tải được dữ liệu bản đồ. Hãy kiểm tra kết nối mạng.',
                          style: TextStyle(
                            color: Theme.of(
                              context,
                            ).colorScheme.onErrorContainer,
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surface,
              border: Border(
                top: BorderSide(
                  color: Theme.of(context).colorScheme.outlineVariant,
                ),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.place_outlined, size: 18),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _isResolvingAddress
                            ? 'Đang lấy địa chỉ...'
                            : addressLabel,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  'Kéo bản đồ để chọn điểm. Ghim đỏ ở giữa chính là vị trí sẽ lưu.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    OutlinedButton.icon(
                      onPressed: _isLocating ? null : _useCurrentLocation,
                      icon: _isLocating
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.my_location_outlined),
                      label: Text(
                        _isLocating ? 'Đang lấy GPS...' : 'Vị trí của tôi',
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: _confirmSelection,
                        icon: const Icon(Icons.check_circle_outline),
                        label: const Text('Xác nhận điểm này'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
