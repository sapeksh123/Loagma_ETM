import 'package:client/services/api_service.dart';

class AttendanceService {
  static Future<Map<String, dynamic>> getToday(String userId) async {
    return ApiService.get('/attendance/today?user_id=$userId');
  }

  // Admin overview for today's attendance (or a specific date).
  static Future<Map<String, dynamic>> getOverview({String? date}) async {
    final endpoint =
        date == null ? '/attendance/overview' : '/attendance/overview?date=$date';
    return ApiService.get(endpoint);
  }

  static Future<Map<String, dynamic>> punchIn(String userId) async {
    return ApiService.post(
      '/attendance/punch-in',
      {'user_id': userId},
    );
  }

  static Future<Map<String, dynamic>> punchOut(String userId) async {
    return ApiService.post(
      '/attendance/punch-out',
      {'user_id': userId},
    );
  }

  static Future<Map<String, dynamic>> startBreak({
    required String userId,
    required String type,
    String? reason,
  }) async {
    final body = <String, dynamic>{
      'user_id': userId,
      'type': type,
    };
    if (reason != null && reason.trim().isNotEmpty) {
      body['reason'] = reason.trim();
    }
    return ApiService.post('/attendance/break/start', body);
  }

  static Future<Map<String, dynamic>> endBreak(String userId) async {
    return ApiService.post(
      '/attendance/break/end',
      {'user_id': userId},
    );
  }
}

