import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

class GeetestResult {
  final String validate;
  final String seccode;
  final String challenge;

  GeetestResult({
    required this.validate,
    required this.seccode,
    required this.challenge,
  });

  Map<String, String> toMap() {
    return {'validate': validate, 'seccode': seccode, 'challenge': challenge};
  }
}

class GeetestCaptchaPage extends StatefulWidget {
  final String gt;
  final String challenge;

  const GeetestCaptchaPage({
    super.key,
    required this.gt,
    required this.challenge,
  });

  @override
  State<GeetestCaptchaPage> createState() => _GeetestCaptchaPageState();
}

class _GeetestCaptchaPageState extends State<GeetestCaptchaPage> {
  final GlobalKey webViewKey = GlobalKey();
  InAppWebViewController? webViewController;
  bool _isLoading = true;
  String? _errorMessage;

  @override
  Widget build(BuildContext context) {
    final String htmlContent =
        '''
<!DOCTYPE html>
<html>
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Captcha</title>
    <style>
        html, body { margin: 0; width: 100%; height: 100%; background: #ffffff; }
        body {
          display: flex;
          justify-content: center;
          align-items: center;
          font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, Arial, sans-serif;
        }
        #captcha {
          width: 320px;
          min-height: 100px;
          border: 1px solid #e8e8e8;
          border-radius: 10px;
          padding: 12px;
          box-sizing: border-box;
        }
        #status {
          color: #666;
          margin-top: 10px;
          font-size: 12px;
          text-align: center;
        }
    </style>
</head>
<body>
    <div>
      <div id="captcha"></div>
      <div id="status">正在加载验证码...</div>
    </div>
    <script>
        function setStatus(text) {
          var el = document.getElementById('status');
          if (el) el.innerText = text;
        }

        function startCaptcha() {
          try {
            initGeetest({
                gt: "${widget.gt}",
                challenge: "${widget.challenge}",
                offline: false,
                new_captcha: true,
                product: "embed",
                width: "100%",
                protocol: "https://",
                api_server: "api.geetest.com"
            }, function (captchaObj) {
                captchaObj.onReady(function () {
                    setStatus("请完成滑块验证");
                });
                captchaObj.appendTo('#captcha');
                captchaObj.onSuccess(function () {
                    var result = captchaObj.getValidate();
                    setStatus("验证成功，正在提交...");
                    window.flutter_inappwebview.callHandler('onSuccess', result);
                });
                captchaObj.onError(function (error) {
                    setStatus("验证组件报错，请重试");
                    window.flutter_inappwebview.callHandler('onError', error ? error.msg || error.message || "unknown" : "unknown");
                });
            });
          } catch (e) {
            setStatus("验证码初始化异常: " + e.message);
            window.flutter_inappwebview.callHandler('onError', "initGeetest exception: " + e.message);
          }
        }

        // 动态加载 gt.js，避免 initialData 下 <head> 外部脚本加载时序问题
        var s = document.createElement('script');
        s.src = 'https://static.geetest.com/static/tools/gt.js';
        s.onload = function () {
          if (typeof initGeetest === 'function') {
            startCaptcha();
          } else {
            setStatus("验证码脚本加载异常");
            window.flutter_inappwebview.callHandler('onError', "initGeetest not found after load");
          }
        };
        s.onerror = function () {
          setStatus("验证码脚本加载失败，请检查网络后重试");
          window.flutter_inappwebview.callHandler('onError', "gt.js load failed");
        };
        document.head.appendChild(s);

        // 超时兜底，防止用户无限等待
        setTimeout(function () {
          var el = document.getElementById('status');
          if (el && el.innerText === '正在加载验证码...') {
            setStatus("验证码加载超时，请返回重试");
            window.flutter_inappwebview.callHandler('onError', "captcha load timeout");
          }
        }, 15000);
    </script>
</body>
</html>
''';

    return Scaffold(
      appBar: AppBar(title: const Text('验证码校验')),
      body: Stack(
        children: [
          InAppWebView(
            key: webViewKey,
            initialSettings: InAppWebViewSettings(
              javaScriptEnabled: true,
              transparentBackground: false,
              isInspectable: true,
              mixedContentMode: MixedContentMode.MIXED_CONTENT_ALWAYS_ALLOW,
              mediaPlaybackRequiresUserGesture: false,
            ),
            initialData: InAppWebViewInitialData(
              data: htmlContent,
              baseUrl: WebUri('https://www.bilibili.com'),
              historyUrl: WebUri('https://www.bilibili.com'),
            ),
            onWebViewCreated: (controller) {
              webViewController = controller;
              controller.addJavaScriptHandler(
                handlerName: 'onSuccess',
                callback: (args) {
                  final result = args[0];
                  Navigator.of(context).pop(
                    GeetestResult(
                      validate: result['geetest_validate'],
                      seccode: result['geetest_seccode'],
                      challenge: result['geetest_challenge'],
                    ),
                  );
                },
              );
              controller.addJavaScriptHandler(
                handlerName: 'onError',
                callback: (args) {
                  setState(() {
                    _errorMessage =
                        '验证失败: ${args.isNotEmpty ? args[0] : "unknown"}';
                  });
                },
              );
            },
            onLoadStart: (controller, url) {
              setState(() {
                _isLoading = true;
                _errorMessage = null;
              });
            },
            onLoadStop: (controller, url) {
              setState(() {
                _isLoading = false;
              });
            },
            onReceivedError: (controller, request, error) {
              setState(() {
                _isLoading = false;
                _errorMessage = '页面加载失败: ${error.description}';
              });
            },
            onConsoleMessage: (controller, consoleMessage) {
              debugPrint(
                '[Geetest] ${consoleMessage.messageLevel}: ${consoleMessage.message}',
              );
            },
          ),
          if (_isLoading) const Center(child: CircularProgressIndicator()),
          if (_errorMessage != null)
            Align(
              alignment: Alignment.bottomCenter,
              child: Container(
                margin: const EdgeInsets.all(12),
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.red.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.red.shade200),
                ),
                child: Text(
                  _errorMessage!,
                  style: const TextStyle(fontSize: 12, color: Colors.red),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
