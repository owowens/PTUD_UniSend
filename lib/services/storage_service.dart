import 'dart:io';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

class StorageService {
  // Khởi tạo client Supabase
  final _supabase = Supabase.instance.client;
  final _auth = FirebaseAuth.instance;

  /// Hàm upload ảnh dùng chung cho toàn bộ dự án
  /// [file]: File ảnh lấy từ ImagePicker
  /// [isAvatar]: true nếu là ảnh hồ sơ (bucket avatars), false nếu là ảnh đơn hàng (bucket orders)
  Future<String?> uploadImage({
    required File file,
    bool isAvatar = false,
  }) async {
    try {
      // 1. Xác định bucket
      final String bucketName = isAvatar ? 'avatars' : 'orders';

      // 2. Dùng user id hiện tại cho mục đích tổ chức đường dẫn lưu file.
      final String userId = _auth.currentUser?.uid ?? 'anonymous';

      // 3. Tạo đường dẫn file: userId/timestamp.jpg để tránh trùng lặp và dễ quản lý
      final String fileName = "${DateTime.now().millisecondsSinceEpoch}.jpg";
      final String path = "$userId/$fileName";

      // 4. Metadata chỉ phục vụ truy vết thao tác upload, không dùng để gán quyền trên order.
      final Map<String, String> metadata = {'uploaded_by': userId};

      // 5. Thực hiện upload lên Supabase Storage kèm metadata
      await _supabase.storage
          .from(bucketName)
          .upload(
            path,
            file,
            fileOptions: FileOptions(
              cacheControl: '3600',
              upsert: false,
              metadata: metadata,
            ),
          );

      // 6. Lấy URL để sử dụng:
      // - Nếu là avatars (public), có thể lấy public URL.
      // - Nếu là orders (private), tạo signed URL tạm thời.
      String url;
      if (isAvatar) {
        url = _supabase.storage.from(bucketName).getPublicUrl(path);
      } else {
        // thời hạn 1 giờ (3600s)
        url = await _supabase.storage
            .from(bucketName)
            .createSignedUrl(path, 3600);
      }

      debugPrint('--- Upload thành công: $url');
      return url;
    } catch (e) {
      debugPrint('--- Lỗi StorageService: $e');
      return null;
    }
  }
}
