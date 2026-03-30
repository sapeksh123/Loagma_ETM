import 'package:client/services/api_service.dart';

class DashboardService {
  static Future<Map<String, dynamic>>? _inflightSummary;

  static Future<Map<String, dynamic>> getSummary() async {
    final inflight = _inflightSummary;
    if (inflight != null) {
      return inflight;
    }

    final future = ApiService.get('/dashboard/summary');
    _inflightSummary = future;
    try {
      return await future;
    } finally {
      _inflightSummary = null;
    }
  }
}

