import 'dart:async';
import 'dart:typed_data';

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

// ============================================================================
// MAIN MAP SCREEN
// ============================================================================

class MapScreen extends StatefulWidget {
  const MapScreen({
    super.key,
    required this.orderService,
    required this.userSessionService,
    this.onOpenChat,
  });

  final OrderService orderService;
  final UserSessionService userSessionService;
  final Future<void> Function(String roomId)? onOpenChat;

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  // Constants
  static const double panelMinSize = 0.12;
  static const double panelMidSize = 0.34;
  static const double panelMaxSize = 1.0;
  static const double nearbySearchRadiusKm = 5.0;
  static const double minMapZoom = 5.0;
  static const double maxMapZoom = 18.0;
  static const String osmTileUrl =
      'https://tile.openstreetmap.org/{z}/{x}/{y}.png';
  static const double defaultLat = 10.7769;
  static const double defaultLng = 106.6997;
  static const double vietnamMinLat = 8.0;
  static const double vietnamMaxLat = 24.0;
  static const double vietnamMinLng = 102.0;
  static const double vietnamMaxLng = 110.0;

  // Controllers & Services
  final panelController = DraggableScrollableController();
  final mapController = MapController();
  final locationService = LocationService();
  final firestoreService = FirestoreService();
  final storageService = StorageService();

  // State
  bool showNearbyPanel = true;
  bool isLocating = false;
  bool isCameraAnimating = false;
  bool hasMapTileError = false;
  Timer? _mapTileErrorTimer;
  Timer? _nearbyRefreshTimer;
  int _mapTileErrorCount = 0;
  String? _lastMapTileError;
  bool isLoadingNearbyOrders = false;
  bool isRefreshingNearbyOrders = false;
  String? nearbyOrdersError;
  Location? currentLocation;
  Location? lastNearbyQueryLocation;
  DateTime? lastNearbyQueryAt;
  String? selectedNearbyOrderId;
  StreamSubscription<Location?>? locationSubscription;
  List<DeliveryOrder> nearbyOrders = const [];
  final Map<String, String?> _resolvedOrderImageUrls = <String, String?>{};
  final Map<String, Future<String?>> _pendingOrderImageUrlFutures =
      <String, Future<String?>>{};

  @override
  void initState() {
    super.initState();
    _initLocation();
    _startNearbyAutoRefresh();
  }

  Future<void> _initLocation() async {
    final enabled = await locationService.isLocationServiceEnabled();
    if (!enabled) return;

    final hasPermission = await locationService.hasLocationPermission();
    if (!hasPermission) return;

    var location = await locationService.getCurrentLocation();
    location ??= await locationService.getLastKnownLocation();

    if (!mounted || location == null) return;

    setState(() => currentLocation = location);
    await _loadNearbyOrders(location, force: true);
    _moveMapTo(location, zoom: 15.5);
    _startTracking();
  }

  bool _isInVietnam(Location location) {
    return location.latitude >= vietnamMinLat &&
        location.latitude <= vietnamMaxLat &&
        location.longitude >= vietnamMinLng &&
        location.longitude <= vietnamMaxLng;
  }

  Future<void> _animateCameraTo(
    LatLng target, {
    double? zoom,
    Duration duration = const Duration(milliseconds: 320),
  }) async {
    if (!mounted || isCameraAnimating) return;

    isCameraAnimating = true;
    final startCenter = mapController.camera.center;
    final startZoom = mapController.camera.zoom;
    final endZoom = (zoom ?? startZoom).clamp(minMapZoom, maxMapZoom);
    const steps = 12;
    final stepMs = (duration.inMilliseconds / steps).round();

    for (var i = 1; i <= steps; i++) {
      if (!mounted) {
        isCameraAnimating = false;
        return;
      }

      final progress = Curves.easeOutCubic.transform(i / steps);
      final lat =
          startCenter.latitude +
          (target.latitude - startCenter.latitude) * progress;
      final lng =
          startCenter.longitude +
          (target.longitude - startCenter.longitude) * progress;
      final z = startZoom + (endZoom - startZoom) * progress;

      mapController.move(LatLng(lat, lng), z);
      await Future.delayed(Duration(milliseconds: stepMs));
    }

    isCameraAnimating = false;
  }

  void _moveMapTo(Location location, {double zoom = 16}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _animateCameraTo(
          LatLng(location.latitude, location.longitude),
          zoom: zoom,
        );
      }
    });
  }

  Future<void> _adjustZoom(double delta) async {
    final center = mapController.camera.center;
    final targetZoom = (mapController.camera.zoom + delta).clamp(
      minMapZoom,
      maxMapZoom,
    );
    await _animateCameraTo(center, zoom: targetZoom);
  }

  Future<void> _requestCurrentLocation() async {
    if (isLocating) return;
    setState(() => isLocating = true);

    final enabled = await locationService.isLocationServiceEnabled();
    if (!enabled) {
      await locationService.openLocationSettings();
      final rechecked = await locationService.isLocationServiceEnabled();
      if (!rechecked && mounted) {
        setState(() => isLocating = false);
        _showMsg('GPS tắt. Bật định vị để xác định vị trí ở Việt Nam.');
        return;
      }
    }

    final denied = await locationService.isLocationPermissionDeniedForever();
    if (denied) {
      await locationService.openAppSettings();
      if (mounted) {
        setState(() => isLocating = false);
        _showMsg('Quyền vị trí từ chối vĩnh viễn. Bật lại ở App Settings.');
      }
      return;
    }

    var havePermission = await locationService.hasLocationPermission();
    if (!havePermission) {
      havePermission = await locationService.requestLocationPermission();
    }

    if (!mounted) return;
    if (!havePermission) {
      setState(() => isLocating = false);
      _showMsg('Không có quyền GPS.');
      return;
    }

    var location = await locationService.getCurrentLocation();
    location ??= await locationService.getLastKnownLocation();

    if (!mounted) return;

    setState(() {
      isLocating = false;
      currentLocation = location;
    });

    if (location == null) {
      _showMsg(
        'Không lấy được vị trí. Dùng mock location ở Việt Nam nếu dùng emulator.',
      );
      return;
    }

    await _loadNearbyOrders(location, force: true);
    _moveMapTo(location, zoom: 16);

    if (_isInVietnam(location)) {
      _showMsg('Đã định vị vị trí.');
    } else {
      _showMsg(
        'GPS ngoài Việt Nam (${location.latitude.toStringAsFixed(4)}, ${location.longitude.toStringAsFixed(4)}).',
      );
    }

    _startTracking();
  }

  void _startTracking() {
    locationSubscription?.cancel();
    locationSubscription = locationService
        .watchLocation(distanceFilter: 20)
        .listen((loc) {
          if (!mounted || loc == null) return;
          setState(() => currentLocation = loc);
          _loadNearbyOrders(loc);
        });
  }

  void _startNearbyAutoRefresh() {
    _nearbyRefreshTimer?.cancel();
    _nearbyRefreshTimer = Timer.periodic(const Duration(seconds: 18), (_) {
      final location = currentLocation;
      if (!mounted || location == null) {
        return;
      }

      _loadNearbyOrders(location, force: true);
    });
  }

  Future<void> _loadNearbyOrders(
    Location location, {
    bool force = false,
  }) async {
    if (!mounted) return;

    if (!force && (isLoadingNearbyOrders || isRefreshingNearbyOrders)) {
      return;
    }

    if (!force && lastNearbyQueryLocation != null) {
      final movedKm = lastNearbyQueryLocation!.distanceTo(location);
      if (movedKm < 0.15) return;
    }

    if (!force && lastNearbyQueryAt != null) {
      final elapsed = DateTime.now().difference(lastNearbyQueryAt!);
      if (elapsed.inSeconds < 8) return;
    }

    setState(() {
      nearbyOrdersError = null;
      if (nearbyOrders.isEmpty) {
        isLoadingNearbyOrders = true;
        isRefreshingNearbyOrders = false;
      } else {
        isRefreshingNearbyOrders = true;
      }
    });

    try {
      if (!FirestoreService.isFirebaseReady) {
        if (!mounted) return;
        setState(() {
          nearbyOrders = const [];
          isLoadingNearbyOrders = false;
          isRefreshingNearbyOrders = false;
          lastNearbyQueryLocation = location;
          lastNearbyQueryAt = DateTime.now();
          selectedNearbyOrderId = null;
          _resolvedOrderImageUrls.clear();
          _pendingOrderImageUrlFutures.clear();
        });
        return;
      }

      final orders = await firestoreService.getAvailableOrdersNearby(
        location,
        radiusKm: nearbySearchRadiusKm,
      );
      final validImageKeys = orders.map(_orderImageCacheKey).toSet();
      if (!mounted) return;

      setState(() {
        nearbyOrders = orders;
        isLoadingNearbyOrders = false;
        isRefreshingNearbyOrders = false;
        lastNearbyQueryLocation = location;
        lastNearbyQueryAt = DateTime.now();
        _resolvedOrderImageUrls.removeWhere(
          (key, _) => !validImageKeys.contains(key),
        );
        _pendingOrderImageUrlFutures.removeWhere(
          (key, _) => !validImageKeys.contains(key),
        );
        if (selectedNearbyOrderId != null &&
            !orders.any((order) => order.id == selectedNearbyOrderId)) {
          selectedNearbyOrderId = null;
        }
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        nearbyOrders = const [];
        nearbyOrdersError = 'Không tải được đơn gần bạn.';
        isLoadingNearbyOrders = false;
        isRefreshingNearbyOrders = false;
        lastNearbyQueryLocation = location;
        lastNearbyQueryAt = DateTime.now();
        selectedNearbyOrderId = null;
        _resolvedOrderImageUrls.clear();
        _pendingOrderImageUrlFutures.clear();
      });
      debugPrint('Failed to load nearby orders: $e');
    }
  }

  void _showMsg(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), behavior: SnackBarBehavior.floating),
    );
  }

  String _formatLocation(Location location) {
    final address = location.address?.trim();
    if (address != null && address.isNotEmpty) {
      return address;
    }
    return '${location.latitude.toStringAsFixed(5)}, ${location.longitude.toStringAsFixed(5)}';
  }

  double? _nearestNearbyOrderDistanceKm() {
    final location = currentLocation;
    if (location == null || nearbyOrders.isEmpty) return null;

    double nearestDistance = double.infinity;
    for (final order in nearbyOrders) {
      final distance = location.distanceTo(
        order.deliveryLocation ?? order.receiverLocation,
      );
      if (distance < nearestDistance) {
        nearestDistance = distance;
      }
    }

    return nearestDistance.isFinite ? nearestDistance : null;
  }

  List<DeliveryOrder> get _sortedNearbyOrders {
    final selectedId = selectedNearbyOrderId;
    if (selectedId == null || selectedId.trim().isEmpty) {
      return nearbyOrders;
    }

    final selectedIndex = nearbyOrders.indexWhere(
      (order) => order.id == selectedId,
    );
    if (selectedIndex <= 0) {
      return nearbyOrders;
    }

    final selectedOrder = nearbyOrders[selectedIndex];
    return <DeliveryOrder>[
      selectedOrder,
      ...nearbyOrders.where((order) => order.id != selectedId),
    ];
  }

  String _orderImageCacheKey(DeliveryOrder order) {
    final id = order.id.trim();
    if (id.isNotEmpty) {
      return id;
    }
    return '${order.imageUrl.trim()}::${order.createdAt.millisecondsSinceEpoch}';
  }

  Future<String?> _resolveOrderMarkerImageUrl(DeliveryOrder order) {
    final key = _orderImageCacheKey(order);

    if (_resolvedOrderImageUrls.containsKey(key)) {
      return Future<String?>.value(_resolvedOrderImageUrls[key]);
    }

    final pending = _pendingOrderImageUrlFutures[key];
    if (pending != null) {
      return pending;
    }

    final future = storageService.resolveStoredImageUrl(order.imageUrl).then((
      resolved,
    ) {
      if (mounted) {
        setState(() {
          _resolvedOrderImageUrls[key] = resolved;
          _pendingOrderImageUrlFutures.remove(key);
        });
      } else {
        _pendingOrderImageUrlFutures.remove(key);
      }
      return resolved;
    });

    _pendingOrderImageUrlFutures[key] = future;
    return future;
  }

  void _focusOrderInPanel(DeliveryOrder order) {
    setState(() {
      selectedNearbyOrderId = order.id;
      showNearbyPanel = true;
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _animatePanelTo(panelMidSize);
      }
    });
  }

  List<Marker> _buildMapMarkers() {
    final markers = <Marker>[];
    final location = currentLocation;

    if (location != null) {
      markers.add(
        _buildMarker(
          LatLng(location.latitude, location.longitude),
          'Bạn',
          Colors.blue,
          isDelivery: true,
        ),
      );
    }

    for (final order in nearbyOrders) {
      final pickupLocation = order.pickupLocation ?? order.senderLocation;
      final deliveryLocation = order.deliveryLocation ?? order.receiverLocation;

      markers.add(
        _buildOrderLocationMarker(
          point: LatLng(pickupLocation.latitude, pickupLocation.longitude),
          order: order,
          tag: 'Nhận',
          tagColor: Colors.green,
        ),
      );
      markers.add(
        _buildOrderLocationMarker(
          point: LatLng(deliveryLocation.latitude, deliveryLocation.longitude),
          order: order,
          tag: 'Giao',
          tagColor: Colors.red,
        ),
      );
    }

    return markers;
  }

  Marker _buildOrderLocationMarker({
    required LatLng point,
    required DeliveryOrder order,
    required String tag,
    required Color tagColor,
  }) {
    return Marker(
      point: point,
      width: 90,
      height: 120,
      alignment: Alignment.bottomCenter,
      child: GestureDetector(
        onTap: () => _focusOrderInPanel(order),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              decoration: BoxDecoration(
                color: tagColor,
                borderRadius: BorderRadius.circular(99),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              child: Text(
                tag,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            const SizedBox(height: 4),
            Container(
              width: 62,
              height: 62,
              padding: const EdgeInsets.all(2),
              decoration: BoxDecoration(
                color: Colors.white,
                shape: BoxShape.circle,
                border: Border.all(color: tagColor, width: 2),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withAlpha(35),
                    blurRadius: 7,
                    spreadRadius: 1,
                  ),
                ],
              ),
              child: ClipOval(
                child: FutureBuilder<String?>(
                  future: _resolveOrderMarkerImageUrl(order),
                  builder: (context, snapshot) {
                    final imageUrl = snapshot.data?.trim();
                    if (imageUrl != null && imageUrl.isNotEmpty) {
                      return Image.network(
                        imageUrl,
                        fit: BoxFit.cover,
                        errorBuilder: (context, error, stackTrace) {
                          return Container(
                            color: Theme.of(
                              context,
                            ).colorScheme.surfaceContainerHighest,
                            child: const Icon(Icons.image_not_supported_outlined),
                          );
                        },
                      );
                    }

                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return const Center(
                        child: SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      );
                    }

                    return Container(
                      color: Theme.of(context).colorScheme.surfaceContainerHighest,
                      child: const Icon(Icons.inventory_2_outlined),
                    );
                  },
                ),
              ),
            ),
            Icon(Icons.location_on, color: tagColor, size: 20),
          ],
        ),
      ),
    );
  }

  void _handleMapError(Object error) {
    if (!mounted || hasMapTileError) return;

    _lastMapTileError = error.toString();
    _mapTileErrorCount += 1;
    _mapTileErrorTimer ??= Timer(const Duration(seconds: 2), () {
      final shouldShowBanner = _mapTileErrorCount >= 6;
      final lastError = _lastMapTileError;

      _mapTileErrorTimer = null;
      _mapTileErrorCount = 0;
      _lastMapTileError = null;

      if (!mounted || hasMapTileError || !shouldShowBanner) {
        return;
      }

      debugPrint('Map tile load failed repeatedly: ${lastError ?? 'unknown'}');
      setState(() => hasMapTileError = true);
    });
  }

  bool get _isPanelExpanded =>
      panelController.isAttached && panelController.size >= 0.95;

  void _animatePanelTo(double size) {
    if (panelController.isAttached) {
      panelController.animateTo(
        size,
        duration: const Duration(milliseconds: 240),
        curve: Curves.easeOutCubic,
      );
    }
  }

  void _togglePanelFullscreen() {
    final target = _isPanelExpanded ? panelMidSize : panelMaxSize;
    _animatePanelTo(target);
  }

  Future<void> _reloadNearbyOrders() async {
    final location = currentLocation;
    if (location == null) {
      _showMsg('Chưa có GPS để tải đơn gần bạn.');
      return;
    }

    await _loadNearbyOrders(location, force: true);
  }

  Future<void> _acceptNearbyOrder(DeliveryOrder order) async {
    final currentUserId = widget.userSessionService.currentUserId.trim();
    final currentAccountId = widget.userSessionService.currentAccountId.trim();
    if (currentUserId.isEmpty) {
      _showMsg('Thiếu thông tin người dùng hiện tại.');
      return;
    }

    try {
      await widget.orderService.acceptOrder(
        order.id,
        currentUserId,
        currentAccountId: currentAccountId,
      );
      await widget.onOpenChat?.call(order.id);
      _showMsg('Đã nhận đơn thành công.');
    } catch (e) {
      _showMsg('Không thể nhận đơn: $e');
    }
  }

  Future<void> _openCreateOrder() async {
    final created = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => _CreateOrderPage(
          orderService: widget.orderService,
          userSessionService: widget.userSessionService,
        ),
      ),
    );

    if (!mounted || created != true) return;

    final location = currentLocation;
    if (location != null) {
      await _loadNearbyOrders(location, force: true);
    }
  }

  @override
  void dispose() {
    locationSubscription?.cancel();
    _mapTileErrorTimer?.cancel();
    _nearbyRefreshTimer?.cancel();
    panelController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final currentLat = currentLocation?.latitude ?? defaultLat;
    final currentLng = currentLocation?.longitude ?? defaultLng;

    return Scaffold(
      extendBodyBehindAppBar: true,
      body: Stack(
        fit: StackFit.expand,
        children: [
          _buildMapLayer(LatLng(currentLat, currentLng)),
          _buildTitleBar(context),
          if (showNearbyPanel) Positioned.fill(child: _buildNearbyPanel()),
          _buildCreateOrderBtn(),
          _buildGpsBtn(),
          _buildZoomBtns(),
          _buildTogglePanelBtn(),
        ],
      ),
    );
  }

  Widget _buildMapLayer(LatLng center) {
    final markers = _buildMapMarkers();

    return Stack(
      fit: StackFit.expand,
      children: [
        FlutterMap(
          mapController: mapController,
          options: MapOptions(
            initialCenter: center,
            initialZoom: 15.0,
            minZoom: minMapZoom,
            maxZoom: maxMapZoom,
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
              urlTemplate: osmTileUrl,
              userAgentPackageName: 'com.example.unisend',
              tileProvider: NetworkTileProvider(
                headers: {'User-Agent': 'UniSend/1.0'},
              ),
              maxNativeZoom: 19,
              errorTileCallback: (tile, error, stackTrace) =>
                  _handleMapError(error),
            ),
            MarkerLayer(
              markers: markers,
            ),
          ],
        ),
        if (hasMapTileError) _buildMapError(context),
      ],
    );
  }

  Marker _buildMarker(
    LatLng point,
    String label,
    Color color, {
    bool isDelivery = false,
  }) {
    return Marker(
      point: point,
      width: 80,
      height: 90,
      alignment: Alignment.bottomCenter,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: color.withAlpha(100),
                  blurRadius: 8,
                  spreadRadius: 2,
                ),
              ],
            ),
            padding: const EdgeInsets.all(8),
            child: Icon(
              isDelivery ? Icons.delivery_dining : Icons.location_on,
              color: Colors.white,
              size: 24,
            ),
          ),
          const SizedBox(height: 4),
          Container(
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(4),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            child: Text(
              label,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 10,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMapError(BuildContext context) {
    return Positioned(
      top: MediaQuery.of(context).padding.top + 48,
      left: 12,
      right: 12,
      child: Material(
        color: Colors.transparent,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.errorContainer,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Text(
            'Không tải bản đồ. Kiểm tra kết nối.',
            style: TextStyle(
              color: Theme.of(context).colorScheme.onErrorContainer,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTitleBar(BuildContext context) {
    return Positioned(
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
    );
  }

  Widget _buildNearbyPanel() {
    final location = currentLocation;
    final panelLocation = location;
    final sortedOrders = _sortedNearbyOrders;
    final bottomPadding = MediaQuery.of(context).padding.bottom + 24.0;

    return DraggableScrollableSheet(
      controller: panelController,
      initialChildSize: panelMidSize,
      minChildSize: panelMinSize,
      maxChildSize: panelMaxSize,
      snap: true,
      snapSizes: const [panelMinSize, panelMidSize, panelMaxSize],
      expand: true,
      builder: (context, scrollController) => Material(
        color: Colors.transparent,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withAlpha(36),
                blurRadius: 18,
                offset: const Offset(0, -3),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
            child: Padding(
              padding: EdgeInsets.only(bottom: bottomPadding),
              child: CustomScrollView(
                controller: scrollController,
                physics: const AlwaysScrollableScrollPhysics(),
                slivers: [
                  SliverToBoxAdapter(child: _buildPanelHeader()),
                  if (isLoadingNearbyOrders)
                    SliverPadding(
                      padding: const EdgeInsets.all(16),
                      sliver: SliverToBoxAdapter(
                        child: _buildPanelStateCard(
                          icon: Icons.hourglass_top_outlined,
                          title: 'Đang tải đơn gần bạn',
                          message:
                              'Đợi một chút để lấy dữ liệu quanh vị trí hiện tại.',
                        ),
                      ),
                    )
                  else if (nearbyOrdersError != null)
                    SliverPadding(
                      padding: const EdgeInsets.all(16),
                      sliver: SliverToBoxAdapter(
                        child: _buildPanelStateCard(
                          icon: Icons.error_outline,
                          title: 'Không tải được danh sách',
                          message: nearbyOrdersError!,
                        ),
                      ),
                    )
                  else if (currentLocation == null)
                    SliverPadding(
                      padding: const EdgeInsets.all(16),
                      sliver: SliverToBoxAdapter(
                        child: _buildPanelStateCard(
                          icon: Icons.my_location_outlined,
                          title: 'Chưa có vị trí GPS',
                          message: 'Bấm nút vị trí để tải các đơn gần bạn.',
                        ),
                      ),
                    )
                  else if (nearbyOrders.isEmpty)
                    SliverPadding(
                      padding: const EdgeInsets.all(16),
                      sliver: SliverToBoxAdapter(
                        child: _buildPanelStateCard(
                          icon: Icons.inbox_outlined,
                          title: 'Chưa có đơn gần bạn',
                          message:
                              'Hiện tại không có đơn nào trong bán kính ${nearbySearchRadiusKm.toStringAsFixed(0)} km.',
                        ),
                      ),
                    )
                  else
                    SliverPadding(
                      padding: const EdgeInsets.fromLTRB(8, 0, 8, 12),
                      sliver: SliverList(
                        delegate: SliverChildBuilderDelegate(
                          (context, i) => Padding(
                            padding: EdgeInsets.only(
                              bottom: i == sortedOrders.length - 1 ? 0 : 8,
                            ),
                            child: _NearbyOrderCard(
                              order: sortedOrders[i],
                              userLocation: panelLocation!,
                              isHighlighted:
                                  sortedOrders[i].id == selectedNearbyOrderId,
                              onTap: () => _focusOrderInPanel(sortedOrders[i]),
                              onAccept: () =>
                                  _acceptNearbyOrder(sortedOrders[i]),
                            ),
                          ),
                          childCount: sortedOrders.length,
                        ),
                      ),
                    ),
                  if (isRefreshingNearbyOrders && nearbyOrders.isNotEmpty)
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: Text(
                            'Đang cập nhật đơn gần bạn...',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPanelHeader() {
    final location = currentLocation;
    final nearestDistance = _nearestNearbyOrderDistanceKm();
    final countLabel = isLoadingNearbyOrders
        ? 'Đang tải...'
        : nearbyOrders.isEmpty
        ? '0 đơn gần bạn'
        : '${nearbyOrders.length} đơn gần bạn';

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 6, 6, 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
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
                child: Text(
                  'Đơn hàng trong khu vực',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              AnimatedBuilder(
                animation: panelController,
                builder: (context, _) => IconButton(
                  onPressed: _togglePanelFullscreen,
                  icon: Icon(
                    _isPanelExpanded
                        ? Icons.fullscreen_exit_outlined
                        : Icons.open_in_full_outlined,
                  ),
                  tooltip: _isPanelExpanded ? 'Thu về' : 'Mở toàn màn hình',
                ),
              ),
              IconButton(
                onPressed: _reloadNearbyOrders,
                icon: const Icon(Icons.refresh_outlined),
                tooltip: 'Tải lại đơn gần bạn',
              ),
              IconButton(
                onPressed: () => _animatePanelTo(panelMinSize),
                icon: const Icon(Icons.vertical_align_bottom_outlined),
                tooltip: 'Thu nhỏ',
              ),
              IconButton(
                onPressed: () => setState(() => showNearbyPanel = false),
                icon: const Icon(Icons.close_outlined),
                tooltip: 'Ẩn',
              ),
            ],
          ),
          const SizedBox(height: 6),
          Align(
            alignment: Alignment.centerLeft,
            child: Chip(
              visualDensity: VisualDensity.compact,
              avatar: const Icon(Icons.route_outlined, size: 16),
              label: Text(countLabel),
            ),
          ),
          const SizedBox(height: 6),
          DecoratedBox(
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: Theme.of(context).colorScheme.outlineVariant,
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.all(10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    location == null
                        ? 'GPS: chưa xác định'
                        : 'GPS: ${_formatLocation(location)}',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Bán kính lọc: ${nearbySearchRadiusKm.toStringAsFixed(0)} km',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    nearestDistance == null
                        ? 'Đơn gần nhất: chưa có dữ liệu'
                        : 'Đơn gần nhất: ${nearestDistance.toStringAsFixed(2)} km',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  if (isRefreshingNearbyOrders && nearbyOrders.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      'Đang cập nhật dữ liệu...',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCreateOrderBtn() {
    return Positioned(
      left: 12,
      bottom: MediaQuery.of(context).padding.bottom + 92,
      child: FloatingActionButton.extended(
        heroTag: 'create_order_fab',
        onPressed: _openCreateOrder,
        icon: const Icon(Icons.add_box_outlined),
        label: const Text('Tạo đơn hàng'),
      ),
    );
  }

  Widget _buildPanelStateCard({
    required IconData icon,
    required String title,
    required String message,
  }) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Card(
          elevation: 0,
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircleAvatar(
                  radius: 22,
                  backgroundColor: Theme.of(
                    context,
                  ).colorScheme.primaryContainer,
                  child: Icon(
                    icon,
                    color: Theme.of(context).colorScheme.onPrimaryContainer,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  title,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 6),
                Text(
                  message,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildGpsBtn() {
    return Positioned(
      right: 12,
      bottom: 168,
      child: FloatingActionButton.small(
        heroTag: 'gps_fab',
        onPressed: _requestCurrentLocation,
        tooltip: 'Vị trí GPS',
        child: isLocating
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Icon(Icons.my_location_outlined),
      ),
    );
  }

  Widget _buildZoomBtns() {
    return Positioned(
      right: 12,
      bottom: 228,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          FloatingActionButton.small(
            heroTag: 'zoom_in',
            tooltip: 'Phóng to',
            onPressed: () => _adjustZoom(1),
            child: const Icon(Icons.add),
          ),
          const SizedBox(height: 8),
          FloatingActionButton.small(
            heroTag: 'zoom_out',
            tooltip: 'Thu nhỏ',
            onPressed: () => _adjustZoom(-1),
            child: const Icon(Icons.remove),
          ),
        ],
      ),
    );
  }

  Widget _buildTogglePanelBtn() {
    if (showNearbyPanel) return const SizedBox.shrink();
    return Positioned(
      top: MediaQuery.of(context).padding.top + 56,
      right: 12,
      child: FloatingActionButton.small(
        heroTag: 'toggle_panel',
        onPressed: () => setState(() => showNearbyPanel = true),
        tooltip: 'Hiện danh sách',
        child: const Icon(Icons.layers_outlined),
      ),
    );
  }
}

// ============================================================================
// NEARBY ORDER CARD
// ============================================================================

class _NearbyOrderCard extends StatelessWidget {
  _NearbyOrderCard({
    required this.order,
    required this.userLocation,
    required this.onTap,
    required this.onAccept,
    this.isHighlighted = false,
  });

  final DeliveryOrder order;
  final Location userLocation;
  final VoidCallback onTap;
  final VoidCallback onAccept;
  final bool isHighlighted;
  final StorageService _storageService = StorageService();

  String _formatLocation(Location location) {
    final address = location.address?.trim();
    if (address != null && address.isNotEmpty) {
      return address;
    }
    return '${location.latitude.toStringAsFixed(5)}, ${location.longitude.toStringAsFixed(5)}';
  }

  Future<String?> _resolveImageUrl() {
    return _storageService.resolveStoredImageUrl(order.imageUrl);
  }

  Future<void> _openOrderInfoSheet(BuildContext context) async {
    final imageUrlFuture = _resolveImageUrl();

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: EdgeInsets.only(
            left: 16,
            right: 16,
            top: 8,
            bottom: MediaQuery.of(sheetContext).viewInsets.bottom + 16,
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Thông tin đơn hàng',
                  style: Theme.of(sheetContext).textTheme.titleLarge,
                ),
                const SizedBox(height: 16),
                ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: AspectRatio(
                    aspectRatio: 1.6,
                    child: FutureBuilder<String?>(
                      future: imageUrlFuture,
                      builder: (context, snapshot) {
                        final resolvedUrl = snapshot.data?.trim();
                        if (snapshot.connectionState != ConnectionState.done ||
                            resolvedUrl == null ||
                            resolvedUrl.isEmpty) {
                          return Container(
                            color: Theme.of(
                              context,
                            ).colorScheme.surfaceContainerHighest,
                            child: const Center(
                              child: Icon(
                                Icons.image_not_supported_outlined,
                                size: 48,
                              ),
                            ),
                          );
                        }

                        return Image.network(
                          resolvedUrl,
                          fit: BoxFit.cover,
                          errorBuilder: (context, error, stackTrace) {
                            return Container(
                              color: Theme.of(
                                context,
                              ).colorScheme.surfaceContainerHighest,
                              child: const Center(
                                child: Icon(
                                  Icons.image_not_supported_outlined,
                                  size: 48,
                                ),
                              ),
                            );
                          },
                        );
                      },
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  'Tiêu đề',
                  style: Theme.of(sheetContext).textTheme.labelLarge,
                ),
                const SizedBox(height: 4),
                Text(
                  order.title,
                  style: Theme.of(
                    sheetContext,
                  ).textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 16),
                Text(
                  'Mô tả',
                  style: Theme.of(sheetContext).textTheme.labelLarge,
                ),
                const SizedBox(height: 4),
                Text(
                  order.description.isEmpty
                      ? 'Chưa có mô tả.'
                      : order.description,
                  style: Theme.of(sheetContext).textTheme.bodyMedium,
                ),
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: () => Navigator.of(sheetContext).pop(),
                    child: const Text('Đóng'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final pickupDistanceKm = userLocation.distanceTo(
      order.pickupLocation ?? order.senderLocation,
    );
    final deliveryDistanceKm = userLocation.distanceTo(
      order.deliveryLocation ?? order.receiverLocation,
    );
    return Card(
      margin: EdgeInsets.zero,
      color: isHighlighted ? scheme.primaryContainer.withAlpha(70) : null,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: isHighlighted
            ? BorderSide(color: scheme.primary, width: 1.3)
            : BorderSide.none,
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: () => _openOrderInfoSheet(context),
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
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      order.title,
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text('Lấy hàng: ${_formatLocation(order.senderLocation)}'),
                    const SizedBox(height: 2),
                    Text('Giao hàng: ${_formatLocation(order.receiverLocation)}'),
                    const SizedBox(height: 4),
                    Text(
                      'Cách điểm giao: ${deliveryDistanceKm.toStringAsFixed(2)} km',
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Cách điểm lấy: ${pickupDistanceKm.toStringAsFixed(2)} km',
                    ),
                    const SizedBox(height: 8),
                    Chip(
                      visualDensity: VisualDensity.compact,
                      label: Text(order.status.name),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                width: 84,
                child: FilledButton.tonal(
                  onPressed: onAccept,
                  child: const Text('Nhận'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ============================================================================
// CREATE ORDER PAGE
// ============================================================================

class _CreateOrderPage extends StatelessWidget {
  const _CreateOrderPage({
    required this.orderService,
    required this.userSessionService,
  });
  final OrderService orderService;
  final UserSessionService userSessionService;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Tạo đơn hàng'), centerTitle: false),
      body: _CreateOrderForm(
        orderService: orderService,
        userSessionService: userSessionService,
      ),
    );
  }
}

class _CreateOrderForm extends StatefulWidget {
  const _CreateOrderForm({
    required this.orderService,
    required this.userSessionService,
  });
  final OrderService orderService;
  final UserSessionService userSessionService;

  @override
  State<_CreateOrderForm> createState() => _CreateOrderFormState();
}

class _CreateOrderFormState extends State<_CreateOrderForm> {
  final titleCtrl = TextEditingController();
  final descCtrl = TextEditingController();
  final receiverAccCtrl = TextEditingController();
  final senderNameCtrl = TextEditingController();
  final senderPhoneCtrl = TextEditingController();
  final receiverNameCtrl = TextEditingController();
  final receiverPhoneCtrl = TextEditingController();

  final locService = LocationService();
  final fsService = FirestoreService();
  final storageService = StorageService();
  final imagePicker = ImagePicker();

  bool hasImage = false;
  bool isSubmitting = false;
  bool isPickingSender = false;
  bool isPickingReceiver = false;
  bool isLookingupReceiver = false;
  bool receiverFound = false;
  String? receiverLookupMsg;
  String? currentAccountId;
  String? resolvedReceiverId;
  Location? senderLoc;
  Location? receiverLoc;
  XFile? imageFile;
  Uint8List? imageBytes;
  Timer? lookupDebounce;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    await _prefillSenderLoc();
    await _loadSenderProfile(widget.userSessionService.currentUserId);
  }

  Future<void> _loadSenderProfile(String senderId) async {
    final normalized = senderId.trim();
    if (normalized.isEmpty) return;

    final profile = await fsService.getUserProfile(normalized);
    if (!mounted || profile == null) return;

    setState(() {
      senderNameCtrl.text = (profile['name'] as String?)?.trim() ?? '';
      senderPhoneCtrl.text = (profile['phone'] as String?)?.trim() ?? '';
      currentAccountId = (profile['accountId'] as String?)?.trim();
    });
    widget.userSessionService.setCurrentAccountId(currentAccountId ?? '');
  }

  void _onReceiverAccChanged(String val) {
    lookupDebounce?.cancel();
    final accId = val.trim();

    if (accId.isEmpty) {
      setState(() {
        receiverFound = false;
        isLookingupReceiver = false;
        receiverLookupMsg = null;
        resolvedReceiverId = null;
        receiverNameCtrl.clear();
        receiverPhoneCtrl.clear();
      });
      return;
    }

    setState(() {
      isLookingupReceiver = true;
      receiverLookupMsg = null;
    });

    lookupDebounce = Timer(
      const Duration(milliseconds: 350),
      () => _lookupReceiver(accId),
    );
  }

  bool _isSelfReceiverAccount(String receiverAcc, String senderAcc) {
    return receiverAcc.trim().isNotEmpty &&
        senderAcc.trim().isNotEmpty &&
        receiverAcc.trim().toLowerCase() == senderAcc.trim().toLowerCase();
  }

  Future<void> _lookupReceiver(String accId) async {
    final senderAcc = currentAccountId?.trim() ?? '';
    if (_isSelfReceiverAccount(accId, senderAcc)) {
      setState(() {
        receiverFound = false;
        isLookingupReceiver = false;
        receiverLookupMsg = 'Không thể chọn chính mình';
        resolvedReceiverId = null;
        receiverNameCtrl.clear();
        receiverPhoneCtrl.clear();
      });
      return;
    }

    final profile = await fsService.getUserProfileByAccountId(accId);
    if (!mounted) return;

    if (profile == null) {
      setState(() {
        receiverFound = false;
        isLookingupReceiver = false;
        receiverLookupMsg = 'Không tìm thấy';
        resolvedReceiverId = null;
        receiverNameCtrl.clear();
        receiverPhoneCtrl.clear();
      });
      return;
    }

    setState(() {
      receiverFound = true;
      isLookingupReceiver = false;
      receiverLookupMsg = 'Tìm thấy';
      resolvedReceiverId = (profile['id'] as String?)?.trim();
      receiverNameCtrl.text = (profile['name'] as String?)?.trim() ?? '';
      receiverPhoneCtrl.text = (profile['phone'] as String?)?.trim() ?? '';
    });
  }

  Future<void> _prefillSenderLoc() async {
    final hasPerm = await locService.hasLocationPermission();
    if (!hasPerm) return;

    final loc = await locService.getCurrentLocation();
    if (!mounted || loc == null) return;

    setState(() => senderLoc = loc);
  }

  String _formatLoc(Location? loc) {
    if (loc == null) return 'Chưa chọn';
    final addr = loc.address?.trim();
    return addr?.isNotEmpty ?? false
        ? addr!
        : '${loc.latitude.toStringAsFixed(5)}, ${loc.longitude.toStringAsFixed(5)}';
  }

  Future<void> _pickLoc({required bool isSender}) async {
    final loading = isSender ? isPickingSender : isPickingReceiver;
    if (loading) return;

    setState(
      () => isSender ? (isPickingSender = true) : (isPickingReceiver = true),
    );

    final sel = await Navigator.of(context).push<Location>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => _MapLocationPickerPage(
          title: isSender ? 'Địa chỉ lấy hàng' : 'Địa chỉ giao hàng',
          initialLocation: isSender ? senderLoc : receiverLoc,
        ),
      ),
    );

    if (!mounted) return;

    setState(() {
      if (isSender) {
        isPickingSender = false;
        if (sel != null) senderLoc = sel;
      } else {
        isPickingReceiver = false;
        if (sel != null) receiverLoc = sel;
      }
    });
  }

  Widget _buildLocTile({
    required String title,
    required Location? loc,
    required bool loading,
    required VoidCallback onPick,
  }) {
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: Theme.of(context).textTheme.labelLarge),
            const SizedBox(height: 6),
            Text(
              _formatLoc(loc),
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            if (loc != null) ...[
              const SizedBox(height: 4),
              Text(
                'Tọa độ: ${loc.latitude.toStringAsFixed(5)}, ${loc.longitude.toStringAsFixed(5)}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
            const SizedBox(height: 10),
            OutlinedButton.icon(
              onPressed: loading ? null : onPick,
              icon: loading
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.map_outlined),
              label: Text(loading ? 'Đang mở...' : 'Chọn'),
            ),
          ],
        ),
      ),
    );
  }

  void _showMsg(String msg) => ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text(msg), behavior: SnackBarBehavior.floating),
  );

  Future<void> _pickImg(String src) async {
    final source = src == 'camera' ? ImageSource.camera : ImageSource.gallery;
    try {
      final file = await imagePicker.pickImage(
        source: source,
        imageQuality: 85,
      );
      if (!mounted || file == null) return;
      final bytes = await file.readAsBytes();
      setState(() {
        imageFile = file;
        imageBytes = bytes;
        hasImage = true;
      });
    } catch (e) {
      if (mounted) _showMsg('Lỗi: $e');
    }
  }

  Future<void> _submit() async {
    if (isSubmitting) return;

    final uid = widget.userSessionService.currentUserId;
    final title = titleCtrl.text.trim();
    final receiverAcc = receiverAccCtrl.text.trim();
    final senderAcc = currentAccountId?.trim();
    final desc = descCtrl.text.trim().isEmpty ? 'N/A' : descCtrl.text;

    if (title.isEmpty) {
      _showMsg('Nhập tiêu đề');
      return;
    }
    if (uid.isEmpty) {
      _showMsg('Lỗi sender');
      return;
    }
    if (senderAcc == null || senderAcc.isEmpty) {
      _showMsg('Cập nhật mã tài khoản');
      return;
    }
    if (_isSelfReceiverAccount(receiverAcc, senderAcc)) {
      _showMsg('Người nhận không thể là chính bạn');
      return;
    }
    if (receiverAcc.isEmpty) {
      _showMsg('Nhập mã người nhận');
      return;
    }
    if (!receiverFound || resolvedReceiverId == null) {
      _showMsg('Người nhận không tồn tại');
      return;
    }
    if (imageFile == null) {
      _showMsg('Chọn ảnh');
      return;
    }
    if (senderLoc == null) {
      _showMsg('Chọn địa chỉ lấy hàng');
      return;
    }
    if (receiverLoc == null) {
      _showMsg('Chọn địa chỉ giao hàng');
      return;
    }

    final senderLocation = senderLoc!;
    final receiverLocation = receiverLoc!;

    setState(() => isSubmitting = true);

    try {
      final imgUrl = await storageService.uploadImage(
        file: imageFile!,
        isAvatar: false,
      );
      if (!mounted) return;

      if (imgUrl == null || imgUrl.trim().isEmpty) {
        _showMsg('Upload ảnh thất bại');
        return;
      }

      final now = DateTime.now();
      final order = DeliveryOrder(
        id: 'ORD-${now.microsecondsSinceEpoch}',
        title: title,
        description: desc,
        imageUrl: imgUrl,
        senderId: uid,
        receiverId: resolvedReceiverId!,
        senderAccountId: senderAcc,
        receiverAccountId: receiverAcc,
        createdByAccountId: senderAcc,
        senderLocation: senderLocation,
        receiverLocation: receiverLocation,
        carrierId: null,
        createdBy: uid,
        status: OrderStatus.waitingCarrier,
        createdAt: now,
        deadlineAt: now.add(const Duration(hours: 4)),
      );

      await fsService.createOrder(order);

      if (!mounted) return;

      _showMsg('Tạo đơn thành công');
      Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) _showMsg('Lỗi: $e');
    } finally {
      if (mounted) setState(() => isSubmitting = false);
    }
  }

  Widget _buildInput(
    String label,
    TextEditingController ctrl, {
    TextInputType keyboardType = TextInputType.text,
    int minLines = 1,
    int maxLines = 1,
    bool enabled = true,
    ValueChanged<String>? onChanged,
    String? helperText,
  }) {
    return Material(
      type: MaterialType.transparency,
      child: TextField(
        controller: ctrl,
        enabled: enabled,
        keyboardType: keyboardType,
        minLines: minLines,
        maxLines: maxLines,
        onChanged: onChanged,
        decoration: InputDecoration(labelText: label, helperText: helperText),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final senderLocation = senderLoc;
    final receiverLocation = receiverLoc;

    return ListView(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 12,
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Ảnh', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 10),
                ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: Theme.of(
                        context,
                      ).colorScheme.surfaceContainerHighest,
                    ),
                    child: SizedBox(
                      height: 150,
                      child: imageBytes != null
                          ? Image.memory(imageBytes!, fit: BoxFit.cover)
                          : Center(
                              child: Icon(
                                hasImage
                                    ? Icons.check_circle_outline
                                    : Icons.image_outlined,
                                size: 34,
                              ),
                            ),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  children: [
                    OutlinedButton.icon(
                      onPressed: isSubmitting
                          ? null
                          : () => _pickImg('gallery'),
                      icon: const Icon(Icons.photo_library_outlined),
                      label: const Text('Thư viện'),
                    ),
                    OutlinedButton.icon(
                      onPressed: isSubmitting ? null : () => _pickImg('camera'),
                      icon: const Icon(Icons.camera_alt_outlined),
                      label: const Text('Camera'),
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
                  'Người nhận',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 10),
                Text('Tài khoản: ${currentAccountId ?? '---'}'),
                const SizedBox(height: 10),
                _buildInput(
                  'Mã tài khoản người nhận',
                  receiverAccCtrl,
                  onChanged: _onReceiverAccChanged,
                  helperText: receiverLookupMsg,
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
                  'Hàng hóa',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 10),
                _buildInput('Tiêu đề', titleCtrl),
                const SizedBox(height: 10),
                _buildInput('Mô tả', descCtrl, minLines: 2, maxLines: 3),
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
                  'Người gửi',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 10),
                _buildInput('Tên', senderNameCtrl),
                const SizedBox(height: 10),
                _buildInput(
                  'Số điện thoại',
                  senderPhoneCtrl,
                  keyboardType: TextInputType.phone,
                ),
                const SizedBox(height: 10),
                _buildLocTile(
                  title: 'Địa chỉ lấy',
                  loc: senderLoc,
                  loading: isPickingSender,
                  onPick: () => _pickLoc(isSender: true),
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
                  'Người nhận',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 10),
                _buildInput('Tên', receiverNameCtrl),
                const SizedBox(height: 10),
                _buildInput(
                  'Số điện thoại',
                  receiverPhoneCtrl,
                  keyboardType: TextInputType.phone,
                ),
                const SizedBox(height: 10),
                _buildLocTile(
                  title: 'Địa chỉ giao',
                  loc: receiverLoc,
                  loading: isPickingReceiver,
                  onPick: () => _pickLoc(isSender: false),
                ),
                if (senderLocation != null && receiverLocation != null) ...[
                  const SizedBox(height: 10),
                  Container(
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
                            'Khoảng cách: ${senderLocation.distanceTo(receiverLocation).toStringAsFixed(2)} km',
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
        Row(
          children: [
            Expanded(
              child: FilledButton.icon(
                onPressed: isSubmitting ? null : _submit,
                icon: isSubmitting
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.check_circle_outline),
                label: Text(isSubmitting ? 'Đang tạo...' : 'Tạo đơn'),
              ),
            ),
          ],
        ),
        const SizedBox(height: 20),
      ],
    );
  }

  @override
  void dispose() {
    lookupDebounce?.cancel();
    titleCtrl.dispose();
    descCtrl.dispose();
    receiverAccCtrl.dispose();
    senderNameCtrl.dispose();
    senderPhoneCtrl.dispose();
    receiverNameCtrl.dispose();
    receiverPhoneCtrl.dispose();
    super.dispose();
  }
}

// ============================================================================
// MAP LOCATION PICKER
// ============================================================================

class _MapLocationPickerPage extends StatelessWidget {
  const _MapLocationPickerPage({required this.title, this.initialLocation});
  final String title;
  final Location? initialLocation;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(title), centerTitle: false),
      body: _MapLocationPickerSheet(
        title: title,
        initialLocation: initialLocation,
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
  static const LatLng defaultCenter = LatLng(10.7769, 106.6997);
  static const String tileUrl =
      'https://tile.openstreetmap.org/{z}/{x}/{y}.png';
  static const double minZoom = 5.0;
  static const double maxZoom = 18.0;
  static const double initialZoom = 15.0;

  final mapCtrl = MapController();
  final locSvc = LocationService();

  late LatLng selectedPoint;
  late double currentZoom;
  Timer? resolveTimer;
  int resolveId = 0;
  bool selectionUpdateQueued = false;
  String? selectedAddress;
  bool isResolvingAddress = false;
  bool isLocating = false;
  bool hasTileError = false;
  LatLng? pendingSelectedPoint;
  double? pendingSelectedZoom;
  bool pendingSelectedPointChanged = false;

  @override
  void initState() {
    super.initState();
    currentZoom = initialZoom;

    final initialLocation = widget.initialLocation;
    if (initialLocation != null) {
      selectedPoint = LatLng(
        initialLocation.latitude,
        initialLocation.longitude,
      );
      selectedAddress = initialLocation.address;
    } else {
      selectedPoint = defaultCenter;
    }

    final initialAddress = selectedAddress?.trim();
    if (initialAddress == null || initialAddress.isEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _resolveAddress();
      });
    }
  }

  @override
  void dispose() {
    resolveTimer?.cancel();
    super.dispose();
  }

  String _fallbackAddress(LatLng pt) =>
      '${pt.latitude.toStringAsFixed(5)}, ${pt.longitude.toStringAsFixed(5)}';

  void _scheduleResolve() {
    resolveTimer?.cancel();
    resolveTimer = Timer(const Duration(milliseconds: 600), _resolveAddress);
  }

  Future<void> _resolveAddress() async {
    final pt = selectedPoint;
    final id = ++resolveId;
    setState(() => isResolvingAddress = true);

    final loc = await locSvc.getLocationFromCoordinates(
      pt.latitude,
      pt.longitude,
    );
    if (!mounted || id != resolveId) return;

    setState(() {
      isResolvingAddress = false;
      selectedAddress = loc?.address;
    });
  }

  void _updateSelection(LatLng center, double zoom) {
    final moved =
        (center.latitude - selectedPoint.latitude).abs() > 0.0000005 ||
        (center.longitude - selectedPoint.longitude).abs() > 0.0000005;
    final zoomChanged = (zoom - currentZoom).abs() > 0.001;

    if (!moved && !zoomChanged) return;

    pendingSelectedPoint = center;
    pendingSelectedZoom = zoom;
    pendingSelectedPointChanged = pendingSelectedPointChanged || moved;

    if (selectionUpdateQueued) return;

    selectionUpdateQueued = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      selectionUpdateQueued = false;
      if (!mounted ||
          pendingSelectedPoint == null ||
          pendingSelectedZoom == null) {
        return;
      }

      final point = pendingSelectedPoint!;
      final zoomValue = pendingSelectedZoom!;
      final changed = pendingSelectedPointChanged;
      pendingSelectedPoint = null;
      pendingSelectedZoom = null;
      pendingSelectedPointChanged = false;

      setState(() {
        selectedPoint = point;
        currentZoom = zoomValue;
        if (changed) selectedAddress = null;
      });

      if (changed) _scheduleResolve();
    });
  }

  void _adjustZoom(double delta) {
    final center = mapCtrl.camera.center;
    final targetZoom = (currentZoom + delta).clamp(minZoom, maxZoom);
    mapCtrl.move(center, targetZoom);
    _updateSelection(center, targetZoom);
  }

  Future<void> _useCurrentLocation() async {
    if (isLocating) return;
    setState(() => isLocating = true);

    var havePermission = await locSvc.hasLocationPermission();
    if (!havePermission) {
      havePermission = await locSvc.requestLocationPermission();
    }

    if (!mounted) return;

    if (!havePermission) {
      setState(() => isLocating = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Chưa có quyền'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    final location = await locSvc.getCurrentLocation();
    if (!mounted) return;
    setState(() => isLocating = false);

    if (location == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Không lấy được vị trí'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    final pt = LatLng(location.latitude, location.longitude);
    setState(() {
      selectedPoint = pt;
      selectedAddress = location.address;
      currentZoom = 16;
    });
    mapCtrl.move(pt, currentZoom);
    if ((location.address ?? '').trim().isEmpty) _scheduleResolve();
  }

  void _confirm() {
    final center = mapCtrl.camera.center;
    final addr = selectedAddress ?? _fallbackAddress(center);
    Navigator.of(context).pop(
      Location(
        latitude: center.latitude,
        longitude: center.longitude,
        address: addr,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final address = selectedAddress?.trim();
    final addressLabel = (address != null && address.isNotEmpty)
        ? address
        : _fallbackAddress(selectedPoint);

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  widget.title,
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ),
              IconButton(
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.close),
              ),
            ],
          ),
        ),
        Expanded(
          child: Stack(
            fit: StackFit.expand,
            children: [
              FlutterMap(
                mapController: mapCtrl,
                options: MapOptions(
                  initialCenter: selectedPoint,
                  initialZoom: currentZoom,
                  minZoom: minZoom,
                  maxZoom: maxZoom,
                  onPositionChanged: (pos, hasGesture) {
                    if (!hasGesture || pos.center == null) return;
                    _updateSelection(
                      pos.center!,
                      (pos.zoom ?? currentZoom).toDouble(),
                    );
                  },
                  backgroundColor: const Color(0xFFE9EEF2),
                ),
                children: [
                  TileLayer(
                    urlTemplate: tileUrl,
                    userAgentPackageName: 'com.example.unisend',
                    tileProvider: NetworkTileProvider(
                      headers: {'User-Agent': 'UniSend/1.0'},
                    ),
                    maxNativeZoom: 19,
                    errorTileCallback: (tile, error, stackTrace) {
                      if (!mounted || hasTileError) return;
                      setState(() => hasTileError = true);
                    },
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
                        onPressed: () => _adjustZoom(1),
                        icon: const Icon(Icons.add),
                      ),
                      const SizedBox(height: 2),
                      IconButton(
                        onPressed: () => _adjustZoom(-1),
                        icon: const Icon(Icons.remove),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
        SafeArea(
          top: false,
          child: Container(
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surface,
              border: Border(
                top: BorderSide(
                  color: Theme.of(context).colorScheme.outlineVariant,
                ),
              ),
            ),
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.place_outlined, size: 18),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        isResolvingAddress ? 'Đang lấy...' : addressLabel,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  'Kéo bản đồ. Ghim đỏ là vị trí sẽ lưu.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    OutlinedButton.icon(
                      onPressed: isLocating ? null : _useCurrentLocation,
                      icon: isLocating
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.my_location_outlined),
                      label: const Text('Vị trí của tôi'),
                    ),
                    FilledButton.icon(
                      onPressed: _confirm,
                      icon: const Icon(Icons.check_circle_outline),
                      label: const Text('Xác nhận'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
