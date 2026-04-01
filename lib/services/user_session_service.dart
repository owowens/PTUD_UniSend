import 'package:flutter/foundation.dart';

class UserSessionService extends ChangeNotifier {
  UserSessionService({required String initialUserId})
    : _currentUserId = initialUserId.trim().isEmpty
          ? 'local_user'
          : initialUserId.trim();

  String _currentUserId;

  String get currentUserId => _currentUserId;

  void setCurrentUserId(String userId) {
    final normalizedUserId = userId.trim();
    if (normalizedUserId.isEmpty || normalizedUserId == _currentUserId) {
      return;
    }

    _currentUserId = normalizedUserId;
    notifyListeners();
  }
}
