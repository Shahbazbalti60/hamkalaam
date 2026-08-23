import 'package:dio/dio.dart';

/// Talks to the /api/dataset/* endpoints on the Flask backend.
/// Mirrors the style of AuthService: caller passes the JWT in,
/// this class does not store or manage the token itself.
class DatasetService {
  final Dio _dio = Dio();

  // Change this to your deployed backend URL when ready
  static const String baseUrl = 'http://127.0.0.1:5000/api/dataset';

  Options _authHeader(String token) {
    return Options(headers: {'Authorization': 'Bearer $token'});
  }

  /// GET /api/dataset/words
  /// Returns {'success': true, 'words': [...], 'total': int}
  /// or {'success': false, 'message': String}
  Future<Map<String, dynamic>> getWords(String token) async {
    try {
      final response = await _dio.get(
        '$baseUrl/words',
        options: _authHeader(token),
      );
      if (response.statusCode == 200) {
        return {
          'success': true,
          'words': response.data['words'] ?? [],
          'total': response.data['total'] ?? 0,
        };
      }
    } on DioException catch (e) {
      return {'success': false, 'message': _errorMessage(e)};
    }
    return {'success': false, 'message': 'Something went wrong'};
  }

  /// POST /api/dataset/word
  /// domain is optional.
  Future<Map<String, dynamic>> addWord({
    required String token,
    required String urduWord,
    required String englishGloss,
    String? domain,
  }) async {
    try {
      final response = await _dio.post(
        '$baseUrl/word',
        data: {
          'urdu_word': urduWord,
          'english_gloss': englishGloss,
          if (domain != null && domain.isNotEmpty) 'domain': domain,
        },
        options: _authHeader(token),
      );
      if (response.statusCode == 201) {
        return {'success': true, 'word': response.data['word']};
      }
    } on DioException catch (e) {
      return {'success': false, 'message': _errorMessage(e)};
    }
    return {'success': false, 'message': 'Something went wrong'};
  }

  /// DELETE /api/dataset/word/<id>
  Future<Map<String, dynamic>> deleteWord({
    required String token,
    required int wordId,
  }) async {
    try {
      final response = await _dio.delete(
        '$baseUrl/word/$wordId',
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

  /// GET /api/dataset/statistics
  Future<Map<String, dynamic>> getStatistics(String token) async {
    try {
      final response = await _dio.get(
        '$baseUrl/statistics',
        options: _authHeader(token),
      );
      if (response.statusCode == 200) {
        return {'success': true, 'stats': response.data};
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