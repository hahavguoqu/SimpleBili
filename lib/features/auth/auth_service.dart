import 'dart:async';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:encrypt/encrypt.dart';
import 'package:pointycastle/asymmetric/api.dart';
import '../../core/bili_client.dart';

final authServiceProvider = Provider<AuthService>((ref) {
  return AuthService(ref.read(biliClientProvider));
});

class AuthService {
  final BiliClient _client;

  AuthService(this._client);

  Map<String, String> _parseCookieMap(String cookie) {
    final cookieMap = <String, String>{};
    for (final part in cookie.split(';')) {
      final trimmed = part.trim();
      if (trimmed.isEmpty) continue;
      final idx = trimmed.indexOf('=');
      if (idx > 0) {
        cookieMap[trimmed.substring(0, idx).trim()] = trimmed
            .substring(idx + 1)
            .trim();
      }
    }
    return cookieMap;
  }

  Future<void> _mergeAndSaveLoginCookies({
    required Map<String, dynamic> loginData,
    List<String>? setCookies,
  }) async {
    final cookieMap = _parseCookieMap(_client.cookie);

    if (setCookies != null) {
      for (final raw in setCookies) {
        final pair = raw.split(';').first.trim();
        final idx = pair.indexOf('=');
        if (idx > 0) {
          final key = pair.substring(0, idx).trim();
          final value = pair.substring(idx + 1).trim();
          cookieMap[key] = value;
        }
      }
    }

    final cookieInfo = loginData['cookie_info'];
    final cookies = cookieInfo is Map ? cookieInfo['cookies'] : null;
    if (cookies is List) {
      for (final item in cookies) {
        if (item is Map &&
            item['name'] is String &&
            item['value'] is String &&
            (item['name'] as String).isNotEmpty) {
          cookieMap[item['name'] as String] = item['value'] as String;
        }
      }
    }

    if (cookieMap.isNotEmpty) {
      final cookieString = cookieMap.entries
          .map((e) => '${e.key}=${e.value}')
          .join('; ');
      await _client.saveCookie(cookieString);
    }
  }

  Future<void> _saveRefreshTokenFromLoginData(Map<String, dynamic> data) async {
    final refreshToken =
        data['refresh_token'] ??
        (data['token_info'] is Map
            ? data['token_info']['refresh_token']
            : null);
    if (refreshToken is String && refreshToken.isNotEmpty) {
      await _client.saveRefreshToken(refreshToken);
    }
  }

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

  Future<Map<String, dynamic>> queryCaptcha() async {
    try {
      final res = await _client.dio.get(
        'https://passport.bilibili.com/x/passport-login/captcha',
        queryParameters: {'source': 'main_web'},
      );
      if (res.data['code'] == 0) {
        return {'status': true, 'data': res.data['data']};
      }
      return {
        'status': false,
        'message': res.data['message'] ?? 'Captcha query failed',
      };
    } catch (e) {
      return {'status': false, 'message': 'Captcha network error: $e'};
    }
  }

  Future<Map<String, dynamic>> getWebKey() async {
    try {
      final res = await _client.dio.get(
        'https://passport.bilibili.com/x/passport-login/web/key',
        queryParameters: {'disable_rcmd': 0},
      );
      if (res.data['code'] == 0) {
        return {'status': true, 'data': res.data['data']};
      }
      return {
        'status': false,
        'message': res.data['message'] ?? 'Get web key failed',
      };
    } catch (e) {
      return {'status': false, 'message': 'Get key network error: $e'};
    }
  }

  String encryptPassword({
    required String hash,
    required String publicKeyPem,
    required String password,
  }) {
    final publicKey = RSAKeyParser().parse(publicKeyPem);
    if (publicKey is! RSAPublicKey) {
      throw Exception('Invalid RSA public key');
    }
    return Encrypter(
      RSA(publicKey: publicKey),
    ).encrypt('$hash$password').base64;
  }

  Future<Map<String, dynamic>> loginByWebPassword({
    required String username,
    required String encryptedPassword,
    required String token,
    required String challenge,
    required String validate,
    required String seccode,
  }) async {
    try {
      final res = await _client.dio.post(
        'https://passport.bilibili.com/x/passport-login/web/login',
        data: FormData.fromMap({
          'username': username,
          'password': encryptedPassword,
          'keep': 'true',
          'token': token,
          'challenge': challenge,
          'validate': validate,
          'seccode': seccode,
          'source': 'main_web',
        }),
        options: Options(contentType: Headers.formUrlEncodedContentType),
      );
      if (res.data['code'] == 0) {
        final data = (res.data['data'] ?? {}) as Map<String, dynamic>;
        await _mergeAndSaveLoginCookies(
          loginData: data,
          setCookies: res.headers['set-cookie'],
        );
        await _saveRefreshTokenFromLoginData(data);
        return {'status': true, 'data': data};
      }
      return {
        'status': false,
        'message': res.data['message'] ?? 'Password login failed',
      };
    } catch (e) {
      return {'status': false, 'message': 'Password login network error: $e'};
    }
  }

  Future<Map<String, dynamic>> sendWebSmsCode({
    required String tel,
    required String token,
    required String challenge,
    required String validate,
    required String seccode,
    int cid = 86,
  }) async {
    try {
      final res = await _client.dio.post(
        'https://passport.bilibili.com/x/passport-login/web/sms/send',
        data: FormData.fromMap({
          'cid': cid,
          'tel': tel,
          'source': 'main_web',
          'token': token,
          'challenge': challenge,
          'validate': validate,
          'seccode': seccode,
        }),
        options: Options(contentType: Headers.formUrlEncodedContentType),
      );
      if (res.data['code'] == 0) {
        return {'status': true, 'data': res.data['data']};
      }
      return {
        'status': false,
        'message': res.data['message'] ?? 'Send SMS failed',
      };
    } catch (e) {
      return {'status': false, 'message': 'Send SMS network error: $e'};
    }
  }

  Future<Map<String, dynamic>> loginByWebSmsCode({
    required String tel,
    required String code,
    required String captchaKey,
    int cid = 86,
  }) async {
    try {
      final res = await _client.dio.post(
        'https://passport.bilibili.com/x/passport-login/web/login/sms',
        data: FormData.fromMap({
          'cid': cid,
          'tel': tel,
          'code': code,
          'captcha_key': captchaKey,
          'source': 'main_web',
          'keep': 'true',
        }),
        options: Options(contentType: Headers.formUrlEncodedContentType),
      );
      if (res.data['code'] == 0) {
        final data = (res.data['data'] ?? {}) as Map<String, dynamic>;
        await _mergeAndSaveLoginCookies(
          loginData: data,
          setCookies: res.headers['set-cookie'],
        );
        await _saveRefreshTokenFromLoginData(data);
        return {'status': true, 'data': data};
      }
      return {
        'status': false,
        'message': res.data['message'] ?? 'SMS login failed',
      };
    } catch (e) {
      return {'status': false, 'message': 'SMS login network error: $e'};
    }
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
