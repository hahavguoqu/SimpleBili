import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:qr_flutter/qr_flutter.dart';

import 'auth_provider.dart';
import 'geetest_captcha_page.dart';

enum _UiLoginMode { sms, cookie, qrcode }

class LoginPage extends ConsumerStatefulWidget {
  const LoginPage({super.key});

  @override
  ConsumerState<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends ConsumerState<LoginPage> {
  _UiLoginMode _mode = _UiLoginMode.sms;

  final _phoneController = TextEditingController();
  final _smsCodeController = TextEditingController();
  final _sessdataController = TextEditingController();
  final _biliJctController = TextEditingController();
  final _dedeUserIdController = TextEditingController();

  @override
  void dispose() {
    _phoneController.dispose();
    _smsCodeController.dispose();
    _sessdataController.dispose();
    _biliJctController.dispose();
    _dedeUserIdController.dispose();
    super.dispose();
  }

  Future<Map<String, dynamic>?> _solveCaptcha(AuthNotifier notifier) async {
    final captcha = await notifier.prepareCaptchaForUi();
    if (captcha['status'] != true) {
      _toast(captcha['message'] ?? '验证码初始化失败');
      return null;
    }

    final gt = captcha['gt'] as String?;
    final challenge = captcha['challenge'] as String?;
    if (gt == null || challenge == null || gt.isEmpty || challenge.isEmpty) {
      _toast('验证码参数无效');
      return null;
    }

    final result = await Navigator.of(context).push<GeetestResult>(
      MaterialPageRoute(
        builder: (_) => GeetestCaptchaPage(gt: gt, challenge: challenge),
      ),
    );
    if (result == null) return null;

    return {'token': captcha['token'] as String? ?? '', 'result': result};
  }

  Future<void> _sendSms(AuthNotifier notifier, AuthState state) async {
    final phone = _phoneController.text.trim();
    if (phone.isEmpty) {
      _toast('请输入手机号');
      return;
    }
    if (state.smsCountdown > 0) return;

    final solved = await _solveCaptcha(notifier);
    if (solved == null) return;
    final geetest = solved['result'] as GeetestResult;

    await notifier.sendSmsCode(
      phone: phone,
      captchaToken: solved['token'] as String? ?? '',
      challenge: geetest.challenge,
      validate: geetest.validate,
      seccode: geetest.seccode,
    );
  }

  Future<void> _doSmsLogin(AuthNotifier notifier) async {
    final phone = _phoneController.text.trim();
    final code = _smsCodeController.text.trim();
    if (phone.isEmpty || code.isEmpty) {
      _toast('请输入手机号和短信验证码');
      return;
    }
    await notifier.loginWithSms(phone: phone, code: code);
  }

  Future<void> _doCookieLogin(AuthNotifier notifier) async {
    final sess = _sessdataController.text.trim();
    final biliJct = _biliJctController.text.trim();
    final uid = _dedeUserIdController.text.trim();
    if (sess.isEmpty || biliJct.isEmpty || uid.isEmpty) {
      _toast('请完整填写 SESSDATA / bili_jct / DedeUserID');
      return;
    }
    await notifier.loginWithCookie(
      sessdata: sess,
      biliJct: biliJct,
      dedeUserId: uid,
    );
  }

  Future<void> _openQrDialog(AuthNotifier notifier) async {
    await showDialog<void>(
      context: context,
      builder: (_) {
        return Consumer(
          builder: (context, ref, child) {
            final authState = ref.watch(authProvider);
            return AlertDialog(
              title: const Text('扫码登录'),
              content: SizedBox(
                width: 260,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (authState.qrcodeUrl != null)
                      Container(
                        color: Colors.white,
                        padding: const EdgeInsets.all(8),
                        child: QrImageView(
                          data: authState.qrcodeUrl!,
                          size: 180,
                        ),
                      )
                    else
                      const Padding(
                        padding: EdgeInsets.all(24),
                        child: CircularProgressIndicator(),
                      ),
                    const SizedBox(height: 10),
                    Text(
                      authState.status == AuthStatus.waitingConfirm
                          ? '请在手机确认登录'
                          : '请使用 B 站 APP 扫码',
                      style: const TextStyle(fontSize: 12, color: Colors.grey),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('关闭'),
                ),
                FilledButton(
                  onPressed: () async {
                    await notifier.startQrLogin();
                  },
                  child: const Text('刷新二维码'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _toast(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authProvider);
    final notifier = ref.read(authProvider.notifier);
    final busy =
        authState.status == AuthStatus.loading ||
        authState.status == AuthStatus.sendingSms ||
        authState.status == AuthStatus.loggingIn;

    ref.listen(authProvider, (previous, next) {
      if (next.status == AuthStatus.authenticated && mounted) {
        _toast('登录成功');
      }
    });

    return Scaffold(
      appBar: AppBar(title: const Text('登录')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 460),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'SimpleBili',
                  style: TextStyle(
                    fontSize: 30,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFFFB7299),
                  ),
                ),
                const SizedBox(height: 16),
                SegmentedButton<_UiLoginMode>(
                  segments: const [
                    ButtonSegment(value: _UiLoginMode.sms, label: Text('短信')),
                    ButtonSegment(
                      value: _UiLoginMode.cookie,
                      label: Text('Cookie'),
                    ),
                    ButtonSegment(
                      value: _UiLoginMode.qrcode,
                      label: Text('扫码'),
                    ),
                  ],
                  selected: {_mode},
                  onSelectionChanged: (value) {
                    setState(() => _mode = value.first);
                  },
                ),
                const SizedBox(height: 18),
                if (_mode == _UiLoginMode.sms) ...[
                  _input(_phoneController, '手机号', '请输入手机号'),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: _input(_smsCodeController, '短信验证码', '请输入验证码'),
                      ),
                      const SizedBox(width: 8),
                      FilledButton.tonal(
                        onPressed: busy || authState.smsCountdown > 0
                            ? null
                            : () => _sendSms(notifier, authState),
                        child: Text(
                          authState.smsCountdown > 0
                              ? '${authState.smsCountdown}s'
                              : '发送',
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  _fullButton(
                    busy ? null : () => _doSmsLogin(notifier),
                    busy ? const CircularProgressIndicator() : const Text('登录'),
                  ),
                ] else if (_mode == _UiLoginMode.cookie) ...[
                  _input(_sessdataController, 'SESSDATA', 'SESSDATA'),
                  const SizedBox(height: 10),
                  _input(_biliJctController, 'bili_jct', 'bili_jct'),
                  const SizedBox(height: 10),
                  _input(_dedeUserIdController, 'DedeUserID', 'DedeUserID'),
                  const SizedBox(height: 14),
                  _fullButton(
                    busy ? null : () => _doCookieLogin(notifier),
                    busy ? const CircularProgressIndicator() : const Text('登录'),
                  ),
                ] else ...[
                  const Text(
                    '点击下方按钮生成二维码',
                    style: TextStyle(color: Colors.grey),
                  ),
                  const SizedBox(height: 14),
                  _fullButton(() async {
                    await notifier.startQrLogin();
                    if (!mounted) return;
                    await _openQrDialog(notifier);
                  }, const Text('打开扫码登录')),
                ],
                const SizedBox(height: 10),
                if (authState.errorMessage != null &&
                    authState.errorMessage!.isNotEmpty)
                  Text(
                    authState.errorMessage!,
                    style: const TextStyle(color: Colors.red, fontSize: 12),
                    textAlign: TextAlign.center,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _fullButton(VoidCallback? onPressed, Widget child) {
    return SizedBox(
      width: double.infinity,
      child: FilledButton(onPressed: onPressed, child: child),
    );
  }

  Widget _input(
    TextEditingController controller,
    String label,
    String hint, {
    bool obscureText = false,
  }) {
    return TextField(
      controller: controller,
      obscureText: obscureText,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
      ),
    );
  }
}
