import 'dart:typed_data';
import '../config/app_config.dart';
import 'api_client.dart';
import 'package:dio/dio.dart';

/// Talks to the /api/dataset/* endpoints on the Flask backend.
/// Mirrors the style of AuthService: caller passes the JWT in,
/// this class does not store or manage the token itself.
class DatasetService {
  final Dio _dio = ApiClient.create();

  // Change this to your deployed backend URL when ready
  static String get baseUrl => '${AppConfig.apiHost}/api/dataset';

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

  /// POST /api/dataset/word/{id}/sample  (multipart upload of ONE video)
  /// Returns {'success': true, 'sample_count': int} or
  /// {'success': false, 'message': String}.
  Future<Map<String, dynamic>> uploadSample({
    required String token,
    required int wordId,
    required Uint8List bytes,
    required String filename,
    double? durationSeconds,
    double? lightingLevel,
  }) async {
    try {
      final form = FormData.fromMap({
        'video': MultipartFile.fromBytes(bytes, filename: filename),
        if (durationSeconds != null)
          'duration_seconds': durationSeconds.toStringAsFixed(2),
        if (lightingLevel != null)
          'lighting_level': lightingLevel.toStringAsFixed(1),
      });
      final response = await _dio.post(
        '$baseUrl/word/$wordId/sample',
        data: form,
        options: _authHeader(token),
      );
      if (response.statusCode == 201) {
        return {
          'success': true,
          'sample_count': (response.data['sample_count'] as num?)?.toInt() ?? 0,
        };
      }
    } on DioException catch (e) {
      return {'success': false, 'message': _errorMessage(e)};
    }
    return {'success': false, 'message': 'Something went wrong'};
  }

  /// PUT /api/dataset/word/<id>  - edit Urdu text / gloss / domain.
  Future<Map<String, dynamic>> updateWord({
    required String token,
    required int wordId,
    required String urduWord,
    required String englishGloss,
    String? domain,
  }) async {
    try {
      final response = await _dio.put(
        '$baseUrl/word/$wordId',
        data: {
          'urdu_word': urduWord,
          'english_gloss': englishGloss,
          if (domain != null && domain.isNotEmpty) 'domain': domain,
        },
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

  /// GET /api/dataset/word/<id>/samples
  Future<Map<String, dynamic>> getSamples({
    required String token,
    required int wordId,
  }) async {
    try {
      final response = await _dio.get(
        '$baseUrl/word/$wordId/samples',
        options: _authHeader(token),
      );
      if (response.statusCode == 200) {
        return {'success': true, 'samples': response.data['samples'] ?? []};
      }
    } on DioException catch (e) {
      return {'success': false, 'message': _errorMessage(e)};
    }
    return {'success': false, 'message': 'Something went wrong'};
  }

  /// DELETE /api/dataset/sample/<id>
  Future<Map<String, dynamic>> deleteSample({
    required String token,
    required int sampleId,
  }) async {
    try {
      final response = await _dio.delete(
        '$baseUrl/sample/$sampleId',
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
      return 'Admin access required';
    } else if (e.response?.data is Map && e.response?.data['error'] != null) {
      return e.response!.data['error'].toString();
    }
    return 'Cannot connect to server';
  }
}
