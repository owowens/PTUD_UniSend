import 'dart:io';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';

class StorageService {
  SupabaseClient? _tryGetSupabaseClient() {
    try {
      return Supabase.instance.client;
    } catch (_) {
      return null;
    }
  }

  String _resolveUploaderId() {
    try {
      if (Firebase.apps.isEmpty) {
        return 'anonymous';
      }
      return FirebaseAuth.instance.currentUser?.uid ?? 'anonymous';
    } catch (_) {
      return 'anonymous';
    }
  }

  /// Hàm upload ảnh dùng chung cho toàn bộ dự án
  /// [file]: File ảnh lấy từ ImagePicker
  /// [isAvatar]: true nếu là ảnh hồ sơ (bucket avatars), false nếu là ảnh đơn hàng (bucket orders)
  Future<String?> uploadImage({
    required File file,
    bool isAvatar = false,
  }) async {
    try {
      final supabase = _tryGetSupabaseClient();
      if (supabase == null) {
        debugPrint('--- Supabase chưa được khởi tạo. Không thể upload ảnh.');
        return null;
      }

      // 1. Xác định bucket
      final String bucketName = isAvatar ? 'avatars' : 'orders';

      // 2. Dùng user id hiện tại cho mục đích tổ chức đường dẫn lưu file.
      final String userId = _resolveUploaderId();

      // 3. Tạo đường dẫn file: userId/timestamp.jpg để tránh trùng lặp và dễ quản lý
      final String fileName = "${DateTime.now().millisecondsSinceEpoch}.jpg";
      final String path = "$userId/$fileName";

      // 4. Metadata chỉ phục vụ truy vết thao tác upload, không dùng để gán quyền trên order.
      final Map<String, String> metadata = {'uploaded_by': userId};

      // 5. Thực hiện upload lên Supabase Storage kèm metadata
      await supabase.storage
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
        url = supabase.storage.from(bucketName).getPublicUrl(path);
      } else {
        // thời hạn 1 giờ (3600s)
        url = await supabase.storage
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
