import '../config/app_config.dart';
import 'api_client.dart';
import 'package:dio/dio.dart';

/// Talks to the /api/recognition/* endpoints on the Flask backend.
/// Mirrors the style of the other services: caller passes the JWT
/// in, this class does not store or manage the token itself.
///
/// NOTE: as of Phase 4, these hit DUMMY rule-based classifiers on
/// the backend, not real trained models. See app/ai/*.py comments
/// on the Flask side. word/expression results are pipeline-shape
/// placeholders, not accurate PSL recognition yet.
class RecognitionService {
  final Dio _dio = ApiClient.create();

  // Change this to your deployed backend URL when ready
  static String get baseUrl => '${AppConfig.apiHost}/api/recognition';

  Options _authHeader(String token) {
    return Options(headers: {'Authorization': 'Bearer $token'});
  }

  /// POST /api/recognition/classify
  /// Returns {'success': true, 'word': String?, 'confidence': double,
  /// 'expression': String} or {'success': false, 'message': String}.
  Future<Map<String, dynamic>> classify({
    required String token,
    required List<double> handLandmarks,
    List<double> faceLandmarks = const [],
  }) async {
    try {
      final response = await _dio.post(
        '$baseUrl/classify',
        data: {
          'hand_landmarks': handLandmarks,
          'face_landmarks': faceLandmarks,
        },
        options: _authHeader(token),
      );
      if (response.statusCode == 200) {
        return {
          'success': true,
          'word': response.data['word'],
          'confidence': (response.data['confidence'] as num?)?.toDouble() ?? 0.0,
          'expression': response.data['expression'] ?? 'Neutral',
        };
      }
    } on DioException catch (e) {
      return {'success': false, 'message': _errorMessage(e)};
    }
    return {'success': false, 'message': 'Something went wrong'};
  }

  /// POST /api/recognition/generate
  Future<Map<String, dynamic>> generate({
    required String token,
    required List<String> wordSequence,
    String? expressionContext,
  }) async {
    try {
      final response = await _dio.post(
        '$baseUrl/generate',
        data: {
          'word_sequence': wordSequence,
          if (expressionContext != null) 'expression_context': expressionContext,
        },
        options: _authHeader(token),
      );
      if (response.statusCode == 200) {
        return {'success': true, 'urdu_sentence': response.data['urdu_sentence']};
      }
    } on DioException catch (e) {
      return {'success': false, 'message': _errorMessage(e)};
    }
    return {'success': false, 'message': 'Something went wrong'};
  }

  String _errorMessage(DioException e) {
    if (e.response?.statusCode == 401) {
      return 'Session expired, please log in again';
    } else if (e.response?.data is Map && e.response?.data['error'] != null) {
      return e.response!.data['error'].toString();
    }
    return 'Cannot connect to server';
  }
}
