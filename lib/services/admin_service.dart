import 'package:dio/dio.dart';

/// Talks to the /api/admin/* endpoints on the Flask backend.
/// Mirrors the style of AuthService/DatasetService: caller passes the
/// JWT in, this class does not store or manage the token itself.
class AdminService {
  final Dio _dio = Dio();

  // Change this to your deployed backend URL when ready
  static const String baseUrl = 'http://127.0.0.1:5000/api/admin';

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