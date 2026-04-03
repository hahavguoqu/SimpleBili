import 'dart:convert';
import 'dart:math';
import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:riverpod/riverpod.dart';

final biliClientProvider = Provider<BiliClient>((ref) {
  return BiliClient();
});

class BiliClient {
  late Dio _dio;
  String _cookie = '';
  String? _refreshToken;
  bool _isInitialized = false;
  bool _isRefreshing = false;

  BiliClient() {
    _dio = Dio(
      BaseOptions(
        baseUrl: 'https://api.bilibili.com',
        connectTimeout: const Duration(seconds: 10),
        receiveTimeout: const Duration(seconds: 10),
        headers: {
          'User-Agent':
              'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/123.0.0.0 Safari/537.36',
          'Referer': 'https://www.bilibili.com',
          'Origin': 'https://www.bilibili.com',
        },
      ),
    );

    _dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) async {
          if (!_isInitialized) {
            await init();
          }
          if (_cookie.isNotEmpty) {
            options.headers['Cookie'] = _cookie;
          }
          return handler.next(options);
        },
        onResponse: (response, handler) async {
          // Auto-update cookies from set-cookie headers
          final setCookies = response.headers['set-cookie'];
          if (setCookies != null && setCookies.isNotEmpty) {
            await _mergeCookies(setCookies);
          }

          // Auto-refresh on login expiry (code -101 = not logged in)
          if (response.data is Map &&
              response.data['code'] == -101 &&
              !_isRefreshing &&
              _refreshToken != null) {
            _isRefreshing = true;
            try {
              final refreshed = await _tryRefreshCookie();
              if (refreshed) {
                // Retry the original request with new cookie
                final opts = response.requestOptions;
                opts.headers['Cookie'] = _cookie;
                final retryResponse = await _dio.fetch(opts);
                _isRefreshing = false;
                return handler.next(retryResponse);
              }
            } catch (_) {}
            _isRefreshing = false;
          }

          return handler.next(response);
        },
      ),
    );
  }

  Dio get dio => _dio;
  String get cookie => _cookie;
  String? get refreshToken => _refreshToken;

  Future<void> init() async {
    if (_isInitialized) return;
    final prefs = await SharedPreferences.getInstance();
    _cookie = prefs.getString('bili_cookie') ?? '';
    _refreshToken = prefs.getString('bili_refresh_token');
    _isInitialized = true;

    // Ensure buvid cookies exist
    if (_cookie.isNotEmpty && !_cookie.contains('buvid3')) {
      await _ensureBuvidCookies();
    }
  }

  Future<void> saveCookie(String cookie) async {
    _cookie = cookie;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('bili_cookie', cookie);
    _isInitialized = true;
  }

  Future<void> saveRefreshToken(String token) async {
    _refreshToken = token;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('bili_refresh_token', token);
  }

  Future<void> clearCookie() async {
    _cookie = '';
    _refreshToken = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('bili_cookie');
    await prefs.remove('bili_refresh_token');
  }

  /// Generate a buvid-style string (matches Bilibili's format)
  static String _generateBuvid() {
    final mac = <String>[];
    final random = Random();
    for (var i = 0; i < 6; i++) {
      final num = random.nextInt(256).toRadixString(16).padLeft(2, '0');
      mac.add(num);
    }
    final md5Str = md5Hash(mac.join(':'));
    final arr = md5Str.split('');
    return 'XY${arr[2]}${arr[12]}${arr[22]}$md5Str';
  }

  static String md5Hash(String input) {
    return md5.convert(utf8.encode(input)).toString();
  }

  /// Ensure buvid3 and buvid4 cookies are present.
  /// These fingerprint cookies are required by B站 to maintain session stability.
  Future<void> _ensureBuvidCookies() async {
    final cookieMap = _parseCookieMap();
    bool changed = false;

    if (!cookieMap.containsKey('buvid3')) {
      cookieMap['buvid3'] = '${_generateBuvid()}infoc';
      changed = true;
    }
    if (!cookieMap.containsKey('buvid4')) {
      final uuid = _generateBuvid();
      final now = DateTime.now();
      final formatted =
          '${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}'
          '${now.hour.toString().padLeft(2, '0')}${now.minute.toString().padLeft(2, '0')}${now.second.toString().padLeft(2, '0')}';
      cookieMap['buvid4'] = '$uuid$formatted';
      changed = true;
    }
    if (!cookieMap.containsKey('b_nut')) {
      cookieMap['b_nut'] = (DateTime.now().millisecondsSinceEpoch ~/ 1000)
          .toString();
      changed = true;
    }

    if (changed) {
      final newCookie = cookieMap.entries
          .map((e) => '${e.key}=${e.value}')
          .join('; ');
      await saveCookie(newCookie);
    }
  }

  Map<String, String> _parseCookieMap() {
    final cookieMap = <String, String>{};
    for (final part in _cookie.split(';')) {
      final trimmed = part.trim();
      final idx = trimmed.indexOf('=');
      if (idx > 0) {
        cookieMap[trimmed.substring(0, idx).trim()] = trimmed
            .substring(idx + 1)
            .trim();
      }
    }
    return cookieMap;
  }

  /// Merge new set-cookie values into the existing cookie string.
  Future<void> _mergeCookies(List<String> setCookies) async {
    final cookieMap = _parseCookieMap();
    bool changed = false;
    for (final raw in setCookies) {
      final pair = raw.split(';').first.trim();
      final idx = pair.indexOf('=');
      if (idx > 0) {
        final key = pair.substring(0, idx).trim();
        final value = pair.substring(idx + 1).trim();
        if (cookieMap[key] != value) {
          cookieMap[key] = value;
          changed = true;
        }
      }
    }
    if (changed) {
      final newCookie = cookieMap.entries
          .map((e) => '${e.key}=${e.value}')
          .join('; ');
      await saveCookie(newCookie);
    }
  }

  /// Try to refresh the cookie using the refresh_token.
  /// B站 API: POST https://passport.bilibili.com/x/passport-login/web/cookie/refresh
  Future<bool> _tryRefreshCookie() async {
    if (_refreshToken == null) return false;
    final cookieMap = _parseCookieMap();
    final csrf = cookieMap['bili_jct'] ?? '';

    try {
      final res = await _dio.post(
        'https://passport.bilibili.com/x/passport-login/web/cookie/refresh',
        data: {
          'csrf': csrf,
          'refresh_csrf': '',
          'refresh_token': _refreshToken,
          'source': 'main_web',
        },
        options: Options(
          contentType: Headers.formUrlEncodedContentType,
          headers: {'Cookie': _cookie},
        ),
      );

      if (res.data['code'] == 0) {
        // Extract new cookies from set-cookie headers
        final setCookies = res.headers['set-cookie'];
        if (setCookies != null && setCookies.isNotEmpty) {
          await _mergeCookies(setCookies);
        }
        // Save new refresh_token
        final newRefreshToken = res.data['data']?['refresh_token'];
        if (newRefreshToken != null) {
          await saveRefreshToken(newRefreshToken);
        }
        return true;
      }
    } catch (e) {
      print('Cookie refresh failed: $e');
    }
    return false;
  }

  /// Check if the current cookie is still valid.
  /// If invalid but refresh_token exists, try refreshing first.
  Future<bool> checkCookieValid() async {
    if (_cookie.isEmpty) return false;
    try {
      final res = await _dio.get('/x/web-interface/nav');
      if (res.data['code'] == 0 && res.data['data']['isLogin'] == true) {
        return true;
      }
      // Not logged in — attempt refresh
      if (_refreshToken != null) {
        final refreshed = await _tryRefreshCookie();
        if (refreshed) {
          final retryRes = await _dio.get('/x/web-interface/nav');
          return retryRes.data['code'] == 0 &&
              retryRes.data['data']['isLogin'] == true;
        }
      }
      return false;
    } catch (_) {
      return false;
    }
  }

  String? wbiImgKey;
  String? wbiSubKey;

  Future<void> fetchWbiKeys() async {
    if (wbiImgKey != null && wbiSubKey != null) return;

    try {
      final res = await _dio.get('/x/web-interface/nav');
      if (res.data['code'] == 0) {
        final wbiImg = res.data['data']['wbi_img'];
        final imgUrl = wbiImg['img_url'] as String;
        final subUrl = wbiImg['sub_url'] as String;

        wbiImgKey = imgUrl.split('/').last.split('.').first;
        wbiSubKey = subUrl.split('/').last.split('.').first;
      }
    } catch (e) {
      print('Fetch WBI keys failed: $e');
    }
  }
}
