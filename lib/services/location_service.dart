import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart' as geolocator;
import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/order.dart' as models;

class LocationService {
  // Singleton pattern
  static final LocationService _instance = LocationService._internal();

  factory LocationService() {
    return _instance;
  }

  LocationService._internal();

  /// Kiểm tra quyền truy cập vị trí
  Future<bool> requestLocationPermission() async {
    try {
      final permission = await geolocator.Geolocator.requestPermission();

      return permission == geolocator.LocationPermission.always ||
          permission == geolocator.LocationPermission.whileInUse;
    } catch (e) {
      debugPrint('Error requesting location permission: $e');
      return false;
    }
  }

  /// Trạng thái quyền vị trí hiện tại
  Future<geolocator.LocationPermission> getLocationPermissionStatus() async {
    try {
      return await geolocator.Geolocator.checkPermission();
    } catch (e) {
      debugPrint('Error reading permission status: $e');
      return geolocator.LocationPermission.denied;
    }
  }

  /// Kiểm tra trường hợp user đã từ chối vĩnh viễn quyền vị trí
  Future<bool> isLocationPermissionDeniedForever() async {
    try {
      final permission = await geolocator.Geolocator.checkPermission();
      return permission == geolocator.LocationPermission.deniedForever;
    } catch (e) {
      debugPrint('Error checking deniedForever: $e');
      return false;
    }
  }

  /// Kiểm tra GPS/Location service có đang bật hay không
  Future<bool> isLocationServiceEnabled() async {
    try {
      return await geolocator.Geolocator.isLocationServiceEnabled();
    } catch (e) {
      debugPrint('Error checking location service: $e');
      return false;
    }
  }

  /// Mở màn hình cài đặt Location để user bật GPS
  Future<bool> openLocationSettings() async {
    try {
      return await geolocator.Geolocator.openLocationSettings();
    } catch (e) {
      debugPrint('Error opening location settings: $e');
      return false;
    }
  }

  /// Mở app settings khi user từ chối quyền vĩnh viễn
  Future<bool> openAppSettings() async {
    try {
      return await geolocator.Geolocator.openAppSettings();
    } catch (e) {
      debugPrint('Error opening app settings: $e');
      return false;
    }
  }

  /// Kiểm tra xem quyền vị trí đã được cấp chưa
  Future<bool> hasLocationPermission() async {
    try {
      final permission = await geolocator.Geolocator.checkPermission();

      return permission == geolocator.LocationPermission.always ||
          permission == geolocator.LocationPermission.whileInUse;
    } catch (e) {
      debugPrint('Error checking location permission: $e');
      return false;
    }
  }

  /// Lấy vị trí hiện tại của người dùng
  /// [accuracy]: độ chính xác mong muốn (mặc định: BEST)
  Future<models.Location?> getCurrentLocation({
    double distanceFilter = 0,
  }) async {
    try {
      // Kiểm tra quyền
      final hasPermission = await hasLocationPermission();
      if (!hasPermission) {
        debugPrint('Location permission denied');
        return null;
      }

      // Kiểm tra xem GPS có bật không
      final serviceEnabled = await isLocationServiceEnabled();
      if (!serviceEnabled) {
        debugPrint('Location service is disabled');
        return null;
      }

      // Lấy vị trí hiện tại
      final position = await geolocator.Geolocator.getCurrentPosition(
        desiredAccuracy: geolocator.LocationAccuracy.best,
      ).timeout(const Duration(seconds: 10));

      // Chuyển đổi tọa độ → địa chỉ con người đọc được
      final address = await _getAddressFromCoords(
        position.latitude,
        position.longitude,
      );

      return models.Location(
        latitude: position.latitude,
        longitude: position.longitude,
        address: address,
      );
    } catch (e) {
      debugPrint('Error getting current location: $e');
      return null;
    }
  }

  /// Theo dõi vị trí thời gian thực (dùng cho người trung gian C đang giao hàng)
  /// Trả về Stream các vị trí cập nhật
  Stream<models.Location?> watchLocation({
    int distanceFilter = 10, // Cập nhật khi di chuyển > 10m
  }) {
    return geolocator.Geolocator.getPositionStream(
          locationSettings: geolocator.LocationSettings(
            accuracy: geolocator.LocationAccuracy.best,
            distanceFilter: distanceFilter,
          ),
        )
        .asyncMap((position) async {
          final address = await _getAddressFromCoords(
            position.latitude,
            position.longitude,
          );

          return models.Location(
            latitude: position.latitude,
            longitude: position.longitude,
            address: address,
          );
        })
        .handleError((error) {
          debugPrint('Error in location stream: $error');
          return null;
        });
  }

  /// Lấy vị trí cache gần nhất (fallback khi GPS hiện tại không phản hồi kịp)
  Future<models.Location?> getLastKnownLocation() async {
    try {
      final position = await geolocator.Geolocator.getLastKnownPosition();
      if (position == null) {
        return null;
      }

      final address = await _getAddressFromCoords(
        position.latitude,
        position.longitude,
      );

      return models.Location(
        latitude: position.latitude,
        longitude: position.longitude,
        address: address,
      );
    } catch (e) {
      debugPrint('Error getting last known location: $e');
      return null;
    }
  }

  /// Chuyển đổi tọa độ thành địa chỉ con người đọc được
  /// Ví dụ: "123 Đường Nguyễn Huệ, Quận 1, TP HCM"
  /// Dùng Nominatim API (miễn phí, không cần key)
  Future<String?> _getAddressFromCoords(
    double latitude,
    double longitude,
  ) async {
    try {
      // Gọi Nominatim reverse geocoding API
      final url = Uri.parse(
        'https://nominatim.openstreetmap.org/reverse?format=json&lat=$latitude&lon=$longitude&language=vi&zoom=18',
      );

      final response = await http.get(url).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final json = jsonDecode(response.body);
        final address = json['address'] as Map<String, dynamic>?;

        if (address != null) {
          // Xây dựng địa chỉ từ các thành phần
          final parts = <String>[];

          if (address['house_number'] != null) {
            parts.add('${address['house_number']}');
          }
          if (address['road'] != null) {
            parts.add(address['road']);
          }
          if (address['hamlet'] != null &&
              address['hamlet'] != address['road']) {
            parts.add(address['hamlet']);
          }
          if (address['suburb'] != null) {
            parts.add(address['suburb']);
          }
          if (address['city'] != null) {
            parts.add(address['city']);
          }
          if (address['state'] != null) {
            parts.add(address['state']);
          }

          final formatted = parts.isNotEmpty
              ? parts.join(', ')
              : json['display_name'] ??
                    '${latitude.toStringAsFixed(4)}, ${longitude.toStringAsFixed(4)}';

          return formatted;
        }
      }

      return null;
    } catch (e) {
      debugPrint('Error getting address: $e');
      return null;
    }
  }

  /// Lấy đầy đủ thông tin vị trí từ tọa độ (tọa độ -> Location)
  Future<models.Location?> getLocationFromCoordinates(
    double latitude,
    double longitude,
  ) async {
    try {
      final address = await _getAddressFromCoords(latitude, longitude);
      return models.Location(
        latitude: latitude,
        longitude: longitude,
        address: address,
      );
    } catch (e) {
      debugPrint('Error building location from coordinates: $e');
      return null;
    }
  }

  /// Tìm tọa độ từ địa chỉ (địa chỉ → tọa độ)
  /// Ví dụ: "123 Nguyễn Huệ, Q1, HCM" → Location(...)
  /// Dùng Nominatim API (miễn phí, không cần key)
  Future<models.Location?> getLocationFromAddress(String address) async {
    try {
      // Gọi Nominatim forward geocoding API
      final url = Uri.parse(
        'https://nominatim.openstreetmap.org/search?format=json&q=${Uri.encodeComponent(address)}&language=vi&limit=1',
      );

      final response = await http.get(url).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final results = jsonDecode(response.body) as List<dynamic>;

        if (results.isNotEmpty) {
          final result = results.first as Map<String, dynamic>;
          final lat = double.tryParse(result['lat'].toString());
          final lon = double.tryParse(result['lon'].toString());

          if (lat != null && lon != null) {
            return models.Location(
              latitude: lat,
              longitude: lon,
              address: result['display_name'] ?? address,
            );
          }
        }
      }

      return null;
    } catch (e) {
      debugPrint('Error getting location from address: $e');
      return null;
    }
  }

  /// Tính khoảng cách giữa 2 vị trí (tính bằng km)
  /// [from] và [to] là hai vị trí cần tính
  /// Trả về khoảng cách tính bằng km
  double calculateDistance(models.Location from, models.Location to) {
    return geolocator.Geolocator.distanceBetween(
          from.latitude,
          from.longitude,
          to.latitude,
          to.longitude,
        ) /
        1000; // Chuyển từ meter sang km
  }

  /// Kiểm tra xem 2 vị trí có gần nhau không
  /// [from] từ vị trí
  /// [to] đến vị trí
  /// [radiusKm] bán kính tính bằng km (mặc định: 0.5 km)
  bool isNearby(
    models.Location from,
    models.Location to, {
    double radiusKm = 0.5,
  }) {
    final distance = calculateDistance(from, to);
    return distance <= radiusKm;
  }

  /// Lấy danh sách địa điểm gần vị trí hiện tại trong bán kính cho trước
  /// Dùng cho việc tìm người gửi/nhận gần vị trí hiện tại của người trung gian
  bool isWithinRadius(
    models.Location currentLocation,
    models.Location targetLocation,
    double radiusKm,
  ) {
    return calculateDistance(currentLocation, targetLocation) <= radiusKm;
  }
}
