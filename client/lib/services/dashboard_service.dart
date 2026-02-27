import 'package:client/services/api_service.dart';

class DashboardService {
  static Future<Map<String, dynamic>> getSummary() async {
    return ApiService.get('/dashboard/summary');
  }
}

