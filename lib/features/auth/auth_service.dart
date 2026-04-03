import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/bili_client.dart';

final authServiceProvider = Provider<AuthService>((ref) {
  return AuthService(ref.read(biliClientProvider));
});

class AuthService {
  final BiliClient _client;

  AuthService(this._client);

  Future<Map<String, dynamic>> getQrcode() async {
    try {
      final res = await _client.dio.get(
        'https://passport.bilibili.com/x/passport-login/web/qrcode/generate',
      );
      if (res.data['code'] == 0) {
        return {
          'url': res.data['data']['url'],
          'qrcode_key': res.data['data']['qrcode_key'],
        };
      }
    } catch (e) {
      print('Failed to get QR code: $e');
    }
    return {};
  }

  Future<Map<String, dynamic>> pollQrcode(String qrcodeKey) async {
    try {
      final res = await _client.dio.get(
        'https://passport.bilibili.com/x/passport-login/web/qrcode/poll',
        queryParameters: {'qrcode_key': qrcodeKey},
      );
      if (res.data['code'] == 0) {
        final data = res.data['data'];
        if (data['code'] == 0) {
          // Save cookies from response headers
          final cookies = res.headers['set-cookie'];
          if (cookies != null) {
            final cookieString = cookies
                .map((c) => c.split(';').first)
                .join('; ');
            await _client.saveCookie(cookieString);
          }
          // Save refresh_token for cookie auto-refresh
          final refreshToken = data['refresh_token'];
          if (refreshToken != null &&
              refreshToken is String &&
              refreshToken.isNotEmpty) {
            await _client.saveRefreshToken(refreshToken);
          }
        }
        return data;
      }
    } catch (e) {
      print('Poll QR code failed: $e');
    }
    return {'code': -1, 'message': 'Network error'};
  }
}
