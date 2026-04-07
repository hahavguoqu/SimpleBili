import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/bili_client.dart';
import 'auth_service.dart';

enum AuthStatus {
  initial,
  unauthenticated,
  loading,
  waitingScan,
  waitingConfirm,
  sendingSms,
  loggingIn,
  authenticated,
  qrcodeExpired,
  error,
}

enum LoginMethod { qrcode, cookie, password, sms }

class AuthState {
  final AuthStatus status;
  final LoginMethod loginMethod;
  final String? qrcodeUrl;
  final String? errorMessage;
  final String? captchaKey;
  final int smsCountdown;
  final String phone;

  AuthState({
    required this.status,
    this.loginMethod = LoginMethod.qrcode,
    this.qrcodeUrl,
    this.errorMessage,
    this.captchaKey,
    this.smsCountdown = 0,
    this.phone = '',
  });

  AuthState copyWith({
    AuthStatus? status,
    LoginMethod? loginMethod,
    String? qrcodeUrl,
    String? errorMessage,
    String? captchaKey,
    int? smsCountdown,
    String? phone,
    bool clearErrorMessage = false,
    bool clearCaptchaKey = false,
  }) {
    return AuthState(
      status: status ?? this.status,
      loginMethod: loginMethod ?? this.loginMethod,
      qrcodeUrl: qrcodeUrl ?? this.qrcodeUrl,
      errorMessage: clearErrorMessage
          ? null
          : (errorMessage ?? this.errorMessage),
      captchaKey: clearCaptchaKey ? null : (captchaKey ?? this.captchaKey),
      smsCountdown: smsCountdown ?? this.smsCountdown,
      phone: phone ?? this.phone,
    );
  }
}

class AuthNotifier extends StateNotifier<AuthState> {
  final Ref _ref;
  final AuthService _authService;
  Timer? _pollTimer;
  Timer? _smsTimer;

  AuthNotifier(this._ref, this._authService)
    : super(AuthState(status: AuthStatus.initial)) {
    _checkInitialLoginState();
  }

  Future<void> _checkInitialLoginState() async {
    final client = _ref.read(biliClientProvider);
    await client.init();

    if (client.cookie.isNotEmpty) {
      // Validate cookie is still working (will auto-attempt refresh if needed)
      final isValid = await client.checkCookieValid();
      if (isValid) {
        state = state.copyWith(status: AuthStatus.authenticated);
      } else {
        await client.clearCookie();
        state = state.copyWith(status: AuthStatus.unauthenticated);
      }
    } else {
      state = state.copyWith(status: AuthStatus.unauthenticated);
    }
  }

  void setLoginMethod(LoginMethod method) {
    state = state.copyWith(
      loginMethod: method,
      status: AuthStatus.unauthenticated,
      qrcodeUrl: null,
      clearErrorMessage: true,
      clearCaptchaKey: true,
    );
    _pollTimer?.cancel();
  }

  void setPhone(String phone) {
    if (state.phone == phone) return;
    state = state.copyWith(phone: phone);
  }

  // --- QR Code Login ---

  Future<void> startQrLogin() async {
    state = state.copyWith(status: AuthStatus.loading);
    _pollTimer?.cancel();

    final data = await _authService.getQrcode();
    if (data.containsKey('url') && data.containsKey('qrcode_key')) {
      state = state.copyWith(
        status: AuthStatus.waitingScan,
        qrcodeUrl: data['url'],
      );
      _startPolling(data['qrcode_key']);
    } else {
      state = state.copyWith(
        status: AuthStatus.error,
        errorMessage: 'Failed to get QR code',
      );
    }
  }

  void _startPolling(String qrcodeKey) {
    _pollTimer = Timer.periodic(const Duration(seconds: 3), (timer) async {
      final res = await _authService.pollQrcode(qrcodeKey);
      final int code = res['code'] ?? -1;

      if (code == 86101) {
        state = state.copyWith(status: AuthStatus.waitingScan);
      } else if (code == 86090) {
        state = state.copyWith(status: AuthStatus.waitingConfirm);
      } else if (code == 86038) {
        timer.cancel();
        state = state.copyWith(status: AuthStatus.qrcodeExpired);
      } else if (code == 0) {
        timer.cancel();
        state = state.copyWith(status: AuthStatus.authenticated);
      } else {
        timer.cancel();
        state = state.copyWith(
          status: AuthStatus.error,
          errorMessage: res['message'] ?? 'Unknown error',
        );
      }
    });
  }

  // --- Cookie Login ---

  Future<void> loginWithCookie({
    required String sessdata,
    required String biliJct,
    required String dedeUserId,
  }) async {
    state = state.copyWith(status: AuthStatus.loading);
    try {
      final client = _ref.read(biliClientProvider);

      // Construct cookie string
      final cookieString =
          'SESSDATA=$sessdata; bili_jct=$biliJct; DedeUserID=$dedeUserId';

      // Temporary save to test it
      await client.saveCookie(cookieString);

      // Validate by fetching nav info
      final res = await client.dio.get('/x/web-interface/nav');
      if (res.data['code'] == 0 && res.data['data']['isLogin'] == true) {
        state = state.copyWith(
          status: AuthStatus.authenticated,
          errorMessage: null,
        );
      } else {
        await client.clearCookie();
        state = state.copyWith(
          status: AuthStatus.error,
          errorMessage: 'Invalid Cookie or session expired',
        );
      }
    } catch (e) {
      state = state.copyWith(
        status: AuthStatus.error,
        errorMessage: 'Login error: $e',
      );
    }
  }

  Future<Map<String, dynamic>> _prepareCaptcha() async {
    final captchaRes = await _authService.queryCaptcha();
    if (captchaRes['status'] != true) {
      return {
        'status': false,
        'message': captchaRes['message'] ?? 'Failed to init captcha',
      };
    }
    return {
      'status': true,
      'token': captchaRes['data']?['token'],
      'gt': captchaRes['data']?['geetest']?['gt'],
      'challenge': captchaRes['data']?['geetest']?['challenge'],
    };
  }

  Future<void> loginWithPassword({
    required String phone,
    required String password,
    required String captchaToken,
    required String challenge,
    required String validate,
    required String seccode,
  }) async {
    state = state.copyWith(
      status: AuthStatus.loggingIn,
      clearErrorMessage: true,
    );
    final keyRes = await _authService.getWebKey();
    if (keyRes['status'] != true) {
      state = state.copyWith(
        status: AuthStatus.error,
        errorMessage: keyRes['message'] ?? 'Get web key failed',
      );
      return;
    }
    final encryptedPassword = _authService.encryptPassword(
      hash: keyRes['data']?['hash'] ?? '',
      publicKeyPem: keyRes['data']?['key'] ?? '',
      password: password,
    );
    final loginRes = await _authService.loginByWebPassword(
      username: phone,
      encryptedPassword: encryptedPassword,
      token: captchaToken,
      challenge: challenge,
      validate: validate,
      seccode: seccode,
    );
    if (loginRes['status'] == true) {
      final isValid = await _ref.read(biliClientProvider).checkCookieValid();
      state = state.copyWith(
        status: isValid ? AuthStatus.authenticated : AuthStatus.error,
        errorMessage: isValid ? null : 'Cookie not valid after password login',
        clearErrorMessage: isValid,
      );
      return;
    }
    state = state.copyWith(
      status: AuthStatus.error,
      errorMessage: loginRes['message'] ?? 'Password login failed',
    );
  }

  Future<void> sendSmsCode({
    required String phone,
    required String captchaToken,
    required String challenge,
    required String validate,
    required String seccode,
  }) async {
    state = state.copyWith(
      status: AuthStatus.sendingSms,
      clearErrorMessage: true,
    );
    final res = await _authService.sendWebSmsCode(
      tel: phone,
      token: captchaToken,
      challenge: challenge,
      validate: validate,
      seccode: seccode,
    );
    if (res['status'] == true) {
      state = state.copyWith(
        status: AuthStatus.unauthenticated,
        captchaKey: res['data']?['captcha_key'] as String?,
        smsCountdown: 60,
      );
      _smsTimer?.cancel();
      _smsTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
        final next = state.smsCountdown - 1;
        if (next <= 0) {
          timer.cancel();
          state = state.copyWith(smsCountdown: 0);
        } else {
          state = state.copyWith(smsCountdown: next);
        }
      });
      return;
    }
    state = state.copyWith(
      status: AuthStatus.error,
      errorMessage: res['message'] ?? 'Send SMS failed',
    );
  }

  Future<void> loginWithSms({
    required String phone,
    required String code,
  }) async {
    if (state.captchaKey == null || state.captchaKey!.isEmpty) {
      state = state.copyWith(status: AuthStatus.error, errorMessage: '请先发送验证码');
      return;
    }
    state = state.copyWith(
      status: AuthStatus.loggingIn,
      clearErrorMessage: true,
    );
    final res = await _authService.loginByWebSmsCode(
      tel: phone,
      code: code,
      captchaKey: state.captchaKey!,
    );
    if (res['status'] == true) {
      final isValid = await _ref.read(biliClientProvider).checkCookieValid();
      state = state.copyWith(
        status: isValid ? AuthStatus.authenticated : AuthStatus.error,
        errorMessage: isValid ? null : 'Cookie not valid after SMS login',
        clearErrorMessage: isValid,
      );
      return;
    }
    state = state.copyWith(
      status: AuthStatus.error,
      errorMessage: res['message'] ?? 'SMS login failed',
    );
  }

  Future<Map<String, dynamic>> prepareCaptchaForUi() async {
    return _prepareCaptcha();
  }

  Future<void> logout() async {
    _pollTimer?.cancel();
    _smsTimer?.cancel();
    await _ref.read(biliClientProvider).clearCookie();
    state = state.copyWith(
      status: AuthStatus.unauthenticated,
      qrcodeUrl: null,
      clearCaptchaKey: true,
      smsCountdown: 0,
      clearErrorMessage: true,
    );
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _smsTimer?.cancel();
    super.dispose();
  }
}

final authProvider = StateNotifierProvider<AuthNotifier, AuthState>((ref) {
  return AuthNotifier(ref, ref.read(authServiceProvider));
});
