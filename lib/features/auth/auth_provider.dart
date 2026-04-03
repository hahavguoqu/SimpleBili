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
  authenticated,
  qrcodeExpired,
  error,
}

enum LoginMethod { qrcode, cookie }

class AuthState {
  final AuthStatus status;
  final LoginMethod loginMethod;
  final String? qrcodeUrl;
  final String? errorMessage;

  AuthState({
    required this.status,
    this.loginMethod = LoginMethod.qrcode,
    this.qrcodeUrl,
    this.errorMessage,
  });

  AuthState copyWith({
    AuthStatus? status,
    LoginMethod? loginMethod,
    String? qrcodeUrl,
    String? errorMessage,
  }) {
    return AuthState(
      status: status ?? this.status,
      loginMethod: loginMethod ?? this.loginMethod,
      qrcodeUrl: qrcodeUrl ?? this.qrcodeUrl,
      errorMessage: errorMessage ?? this.errorMessage,
    );
  }
}

class AuthNotifier extends StateNotifier<AuthState> {
  final Ref _ref;
  final AuthService _authService;
  Timer? _pollTimer;

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
    );
    _pollTimer?.cancel();
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

  Future<void> logout() async {
    _pollTimer?.cancel();
    await _ref.read(biliClientProvider).clearCookie();
    state = state.copyWith(status: AuthStatus.unauthenticated, qrcodeUrl: null);
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    super.dispose();
  }
}

final authProvider = StateNotifierProvider<AuthNotifier, AuthState>((ref) {
  return AuthNotifier(ref, ref.read(authServiceProvider));
});
