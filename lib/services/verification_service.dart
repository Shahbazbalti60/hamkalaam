import '../config/app_config.dart';
import 'api_client.dart';
import 'package:dio/dio.dart';

/// E-mail verification calls (SRDS FR-02):
///   POST /api/auth/verify-email         {email, code}
///   POST /api/auth/verify-email/resend  {email}
class VerificationService {
  final Dio _dio = ApiClient.create();

  static String get baseUrl => '${AppConfig.apiHost}/api/auth';

  /// Returns {'success': true} or {'success': false, 'message': String}.
  Future<Map<String, dynamic>> verify({
    required String email,
    required String code,
  }) async {
    try {
      final response = await _dio.post(
        '$baseUrl/verify-email',
        data: {'email': email, 'code': code},
      );
      if (response.statusCode == 200) return {'success': true};
    } on DioException catch (e) {
      return {'success': false, 'message': _errorMessage(e)};
    }
    return {'success': false, 'message': 'Something went wrong'};
  }

  /// Returns {'success': true} or {'success': false, 'message': String,
  /// 'retry_after': int?} (retry_after = seconds to wait).
  Future<Map<String, dynamic>> resend({required String email}) async {
    try {
      final response = await _dio.post(
        '$baseUrl/verify-email/resend',
        data: {'email': email},
      );
      if (response.statusCode == 200) return {'success': true};
    } on DioException catch (e) {
      final data = e.response?.data;
      return {
        'success': false,
        'message': _errorMessage(e),
        if (data is Map && data['retry_after'] is num)
          'retry_after': (data['retry_after'] as num).toInt(),
      };
    }
    return {'success': false, 'message': 'Something went wrong'};
  }

  String _errorMessage(DioException e) {
    final data = e.response?.data;
    if (data is Map && data['error'] != null) return data['error'].toString();
    if (data is Map && data['message'] != null) return data['message'].toString();
    return 'Cannot connect to server';
  }
}
