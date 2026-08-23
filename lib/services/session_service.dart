import 'package:dio/dio.dart';

/// Talks to the /api/session/* endpoints on the Flask backend.
/// Mirrors the style of AuthService: caller passes the JWT in,
/// this class does not store or manage the token itself.
class SessionService {
  final Dio _dio = Dio();

  // Change this to your deployed backend URL when ready
  static const String baseUrl = 'http://127.0.0.1:5000/api/session';

  Options _authHeader(String token) {
    return Options(headers: {'Authorization': 'Bearer $token'});
  }

  /// POST /api/session/start
  /// Call this when the user opens the recognition screen / turns the camera on.
  Future<Map<String, dynamic>> startSession(String token) async {
    try {
      final response = await _dio.post(
        '$baseUrl/start',
        options: _authHeader(token),
      );
      if (response.statusCode == 201) {
        return {'success': true, 'session': response.data['session']};
      }
    } on DioException catch (e) {
      return {'success': false, 'message': _errorMessage(e)};
    }
    return {'success': false, 'message': 'Something went wrong'};
  }

  /// POST /api/session/sentence
  /// wordSequence can be a List<String> or a plain String — backend
  /// accepts both and normalizes lists to a comma-separated string.
  Future<Map<String, dynamic>> saveSentence({
    required String token,
    required int sessionId,
    required String urduSentence,
    List<String>? wordSequence,
    String? expressionContext,
  }) async {
    try {
      final response = await _dio.post(
        '$baseUrl/sentence',
        data: {
          'session_id': sessionId,
          'urdu_sentence': urduSentence,
          if (wordSequence != null) 'word_sequence': wordSequence,
          if (expressionContext != null) 'expression_context': expressionContext,
        },
        options: _authHeader(token),
      );
      if (response.statusCode == 201) {
        return {'success': true, 'sentence': response.data['sentence']};
      }
    } on DioException catch (e) {
      return {'success': false, 'message': _errorMessage(e)};
    }
    return {'success': false, 'message': 'Something went wrong'};
  }

  /// GET /api/session/history
  /// Returns sessions with nested sentences for the current user.
  Future<Map<String, dynamic>> getHistory(String token) async {
    try {
      final response = await _dio.get(
        '$baseUrl/history',
        options: _authHeader(token),
      );
      if (response.statusCode == 200) {
        return {
          'success': true,
          'sessions': response.data['sessions'] ?? [],
          'total': response.data['total'] ?? 0,
        };
      }
    } on DioException catch (e) {
      return {'success': false, 'message': _errorMessage(e)};
    }
    return {'success': false, 'message': 'Something went wrong'};
  }

  /// DELETE /api/session/<id>
  Future<Map<String, dynamic>> deleteSession({
    required String token,
    required int sessionId,
  }) async {
    try {
      final response = await _dio.delete(
        '$baseUrl/$sessionId',
        options: _authHeader(token),
      );
      if (response.statusCode == 200) {
        return {'success': true};
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
      return 'You do not have access to this session';
    } else if (e.response?.data is Map && e.response?.data['error'] != null) {
      return e.response!.data['error'].toString();
    }
    return 'Cannot connect to server';
  }
}