import '../config/app_config.dart';
import 'api_client.dart';
import 'package:dio/dio.dart';

/// Talks to the /api/admin/* endpoints on the Flask backend.
/// Mirrors the style of AuthService/DatasetService: caller passes the
/// JWT in, this class does not store or manage the token itself.
class AdminService {
  final Dio _dio = ApiClient.create();

  // Change this to your deployed backend URL when ready
  static String get baseUrl => '${AppConfig.apiHost}/api/admin';

  Options _authHeader(String token) {
    return Options(headers: {'Authorization': 'Bearer $token'});
  }

  /// GET /api/admin/users
  Future<Map<String, dynamic>> getUsers(String token) async {
    try {
      final response = await _dio.get(
        '$baseUrl/users',
        options: _authHeader(token),
      );
      if (response.statusCode == 200) {
        return {
          'success': true,
          'users': response.data['users'] ?? [],
          'total': response.data['total'] ?? 0,
        };
      }
    } on DioException catch (e) {
      return {'success': false, 'message': _errorMessage(e)};
    }
    return {'success': false, 'message': 'Something went wrong'};
  }

  /// PUT /api/admin/user/<id>/role
  /// newRole must be 'User' or 'Admin'.
  Future<Map<String, dynamic>> updateRole({
    required String token,
    required int userId,
    required String newRole,
  }) async {
    try {
      final response = await _dio.put(
        '$baseUrl/user/$userId/role',
        data: {'role': newRole},
        options: _authHeader(token),
      );
      if (response.statusCode == 200) {
        return {'success': true, 'user': response.data['user']};
      }
    } on DioException catch (e) {
      return {'success': false, 'message': _errorMessage(e)};
    }
    return {'success': false, 'message': 'Something went wrong'};
  }

  /// PUT /api/admin/user/<id>/status
  Future<Map<String, dynamic>> updateStatus({
    required String token,
    required int userId,
    required bool isActive,
  }) async {
    try {
      final response = await _dio.put(
        '$baseUrl/user/$userId/status',
        data: {'is_active': isActive},
        options: _authHeader(token),
      );
      if (response.statusCode == 200) {
        return {'success': true, 'user': response.data['user']};
      }
    } on DioException catch (e) {
      return {'success': false, 'message': _errorMessage(e)};
    }
    return {'success': false, 'message': 'Something went wrong'};
  }

  /// GET /api/admin/system-stats?tz=<minutes east of UTC>
  Future<Map<String, dynamic>> getSystemStats(String token) async {
    try {
      final tz = DateTime.now().timeZoneOffset.inMinutes;
      final response = await _dio.get(
        '$baseUrl/system-stats',
        queryParameters: {'tz': tz},
        options: _authHeader(token),
      );
      if (response.statusCode == 200 && response.data is Map) {
        return {'success': true, 'data': Map<String, dynamic>.from(response.data)};
      }
    } on DioException catch (e) {
      return {'success': false, 'message': _errorMessage(e)};
    }
    return {'success': false, 'message': 'Something went wrong'};
  }

  /// GET /api/admin/model-status
  Future<Map<String, dynamic>> getModelStatus(String token) async {
    try {
      final response = await _dio.get(
        '$baseUrl/model-status',
        options: _authHeader(token),
      );
      if (response.statusCode == 200 && response.data is Map) {
        return {'success': true, 'data': Map<String, dynamic>.from(response.data)};
      }
    } on DioException catch (e) {
      return {'success': false, 'message': _errorMessage(e)};
    }
    return {'success': false, 'message': 'Something went wrong'};
  }

  /// POST /api/admin/model/reload  (loading the model can take ~10 s)
  Future<Map<String, dynamic>> reloadModel(String token) async {
    try {
      final response = await _dio.post(
        '$baseUrl/model/reload',
        options: Options(
          headers: {'Authorization': 'Bearer $token'},
          receiveTimeout: const Duration(seconds: 60),
          sendTimeout: const Duration(seconds: 60),
        ),
      );
      if (response.statusCode == 200) {
        return {
          'success': true,
          'word_count': (response.data['word_count'] as num?)?.toInt() ?? 0,
        };
      }
    } on DioException catch (e) {
      return {'success': false, 'message': _errorMessage(e)};
    }
    return {'success': false, 'message': 'Something went wrong'};
  }

  String _errorMessage(DioException e) {
    if (e.response?.statusCode == 401) {
      return 'Session expired, please log in again';
    } else if (e.response?.statusCode == 403) {
      return 'Admin access required';
    } else if (e.response?.data is Map && e.response?.data['error'] != null) {
      return e.response!.data['error'].toString();
    }
    return 'Cannot connect to server';
  }
}
