import '../config/app_config.dart';
import 'api_client.dart';
import 'package:dio/dio.dart';

/// Talks to the /api/recognition/* endpoints on the Flask backend.
/// The caller passes the JWT in; this class does not store the token.
///
/// - classifySequence: REAL trained LSTM (60 frames -> one word).
/// - classify:         old single-frame DUMMY (kept for now, to be removed).
/// - generate:         Urdu sentence (rule-based dummy until Day 4).
class RecognitionService {
  final Dio _dio = ApiClient.create();

  static String get baseUrl => '${AppConfig.apiHost}/api/recognition';

  Options _authHeader(String token, {Duration? receiveTimeout}) {
    return Options(
      headers: {'Authorization': 'Bearer $token'},
      receiveTimeout: receiveTimeout,
      sendTimeout: receiveTimeout,
    );
  }

  /// GET /api/recognition/model-status
  /// Returns {'success': true, 'ready': bool, 'word_count': int}.
  Future<Map<String, dynamic>> modelStatus({required String token}) async {
    try {
      final response = await _dio.get(
        '$baseUrl/model-status',
        options: _authHeader(token, receiveTimeout: const Duration(seconds: 30)),
      );
      if (response.statusCode == 200 && response.data is Map) {
        return {
          'success': true,
          'ready': response.data['ready'] == true,
          'word_count': (response.data['word_count'] as num?)?.toInt() ?? 0,
        };
      }
    } on DioException catch (e) {
      return {'success': false, 'message': _errorMessage(e)};
    }
    return {'success': false, 'message': 'Something went wrong'};
  }

  /// POST /api/recognition/classify-sequence
  /// [frames] = 60 frames x 126 numbers from MediaPipeService.recordWindow.
  /// Returns {'success': true, 'word': String?, 'confidence': double,
  /// 'top3': List, 'uncertain': bool, 'reason': String?, 'hands_found': ...}
  /// or {'success': false, 'message': String}.
  Future<Map<String, dynamic>> classifySequence({
    required String token,
    required List<List<double>> frames,
  }) async {
    try {
      final response = await _dio.post(
        '$baseUrl/classify-sequence',
        // NOTE: the JSON key below ('frames') must match recognition.py.
        data: {'frames': frames},
        options: _authHeader(token, receiveTimeout: const Duration(seconds: 30)),
      );
      if (response.statusCode == 200 && response.data is Map) {
        final d = response.data as Map;
        return {
          'success': true,
          'word': d['word'],
          'confidence': (d['confidence'] as num?)?.toDouble() ?? 0.0,
          'top3': d['top3'] ?? [],
          'uncertain': d['uncertain'] == true,
          'reason': d['reason'],
          'hands_found': d['hands_found'],
        };
      }
    } on DioException catch (e) {
      return {'success': false, 'message': _errorMessage(e)};
    }
    return {'success': false, 'message': 'Something went wrong'};
  }

  /// POST /api/recognition/classify  (old single-frame dummy)
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
