import 'dart:typed_data';
import 'package:dio/dio.dart';

/// Talks to the /api/audio/speak endpoint on the Flask backend, which
/// securely proxies ElevenLabs (API key stays server-side). Returns
/// raw MP3 bytes ready to hand to an AudioPlayer.
class AudioService {
  final Dio _dio = Dio();

  // Change this to your deployed backend URL when ready
  static const String baseUrl = 'http://127.0.0.1:5000/api/audio';

  /// Returns {'success': true, 'bytes': Uint8List} or
  /// {'success': false, 'message': String}.
  Future<Map<String, dynamic>> speak({
    required String token,
    required String text,
  }) async {
    try {
      final response = await _dio.post(
        '$baseUrl/speak',
        data: {'text': text},
        options: Options(
          headers: {'Authorization': 'Bearer $token'},
          responseType: ResponseType.bytes,
        ),
      );
      if (response.statusCode == 200) {
        return {
          'success': true,
          'bytes': Uint8List.fromList(response.data as List<int>),
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
    }
    if (e.response?.statusCode == 502) {
      return 'Text-to-speech service is unavailable right now';
    }
    // Response data is bytes here (responseType.bytes), so we can't
    // reliably read a JSON error message out of it — keep this generic.
    return 'Could not generate audio';
  }
}