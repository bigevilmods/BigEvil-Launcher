import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:material_ui/material_ui.dart';
import 'package:webview_all/webview_all.dart';

import 'library.dart';
import 'localization.dart';

class OnlineBrowser extends StatefulWidget {
  const OnlineBrowser({
    super.key,
    required this.title,
    required this.initialUrl,
  });

  final String title;
  final Uri initialUrl;

  @override
  State<OnlineBrowser> createState() => _OnlineBrowserState();
}

class _OnlineBrowserState extends State<OnlineBrowser> {
  WebViewController? _controller;
  WebViewSession? _session;
  int _progress = 0;
  Object? _error;
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    _start();
  }

  @override
  void dispose() {
    unawaited(_closeSession());
    super.dispose();
  }

  Future<void> _closeSession() async {
    final session = _session;
    _session = null;
    try {
      await session?.close();
    } catch (error) {
      debugPrint('Falha ao fechar a sessão WebView: $error');
    }
  }

  void _report(Object error) {
    if (mounted) setState(() => _error = error);
  }

  Future<void> _start() async {
    setState(() {
      _controller = null;
      _ready = false;
      _error = null;
      _progress = 0;
    });
    try {
      await _closeSession();
      final session = await WebViewSession.create(
        mode: WebViewSessionMode.shared,
        onPermissionRequest: (request) => unawaited(request.deny()),
      );
      if (session == null)
        throw LocalizedFailure((messages) => messages.browserUnavailable);
      if (!mounted) {
        await session.close();
        return;
      }
      _session = session;
      final controller = session.controller;
      await controller.setJavaScriptMode(JavaScriptMode.unrestricted);
      await controller.setPopupPolicy(WebViewPopupWindowPolicy.deny);
      await controller.setNavigationDelegate(
        NavigationDelegate(
          onNavigationRequest: (request) =>
              Library.isWebLink(request.url) ||
                  (!request.isMainFrame && request.url == 'about:blank')
              ? NavigationDecision.navigate
              : NavigationDecision.prevent,
          onProgress: (value) {
            if (mounted) setState(() => _progress = value);
          },
          onPageStarted: (_) {
            if (!mounted) return;
            setState(() {
              _progress = 0;
              _ready = false;
            });
          },
          onPageFinished: (_) {
            if (!mounted) return;
            setState(() {
              _ready = true;
              _progress = 100;
            });
          },
          onWebResourceError: (error) {
            if (error.isForMainFrame == true) _report(error.description);
          },
        ),
      );
      if (!mounted) return;
      setState(() => _controller = controller);
      await controller.loadRequest(widget.initialUrl);
    } catch (error) {
      _report(error);
    }
  }

  Future<void> _navigate(
    Future<void> Function(WebViewController) action,
  ) async {
    final controller = _controller;
    if (controller == null) return;
    if (_error != null) setState(() => _error = null);
    try {
      await action(controller);
    } catch (error) {
      _report(error);
    }
  }

  Future<void> _compatibility() async {
    final controller = _controller;
    if (controller == null) return;
    try {
      const probe = '''
        (() => {
          const supports = type => {
            try { return !!document.createElement('canvas').getContext(type); }
            catch (_) { return false; }
          };
          const wasm = () => {
            try {
              const module = new WebAssembly.Module(new Uint8Array([
                0,97,115,109,1,0,0,0, 1,5,1,96,0,1,127, 3,2,1,0,
                7,7,1,3,114,117,110,0,0, 10,6,1,4,0,65,42,11
              ]));
              return new WebAssembly.Instance(module).exports.run() === 42;
            } catch (_) { return false; }
          };
          let gamepads = null;
          try {
            if (typeof navigator.getGamepads === 'function') {
              gamepads = Array.from(navigator.getGamepads())
                .filter(pad => pad && pad.connected).length;
            }
          } catch (_) {}
          return JSON.stringify({
            'WebAssembly': wasm(),
            'WebGL': supports('webgl'),
            'WebGL 2': supports('webgl2'),
            'Canvas 2D': supports('2d'),
            'Web Audio': !!(window.AudioContext || window.webkitAudioContext),
            'WebGPU': !!navigator.gpu,
            'SharedArrayBuffer': typeof SharedArrayBuffer !== 'undefined',
            'Gamepad API': gamepads !== null,
            'KeyboardEvent': typeof KeyboardEvent !== 'undefined',
            'PointerEvent': typeof PointerEvent !== 'undefined',
            gamepads,
          });
        })()
      ''';
      final result = await controller.runJavaScriptReturningResult(probe);
      final decoded = jsonDecode(result.toString());
      final features =
          (decoded is String ? jsonDecode(decoded) : decoded) as Map;
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          scrollable: true,
          title: Text(context.messages.browserFeatures),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final feature in features.entries.where(
                (feature) => feature.value is bool,
              ))
                Text(
                  '${feature.key}: ${feature.value == true ? context.messages.available : context.messages.unavailable}',
                ),
              if (features['gamepads'] case final int count)
                Text(context.messages.detectedGamepads(count)),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(context.messages.close),
            ),
          ],
        ),
      );
    } catch (_) {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.messages.browserProbeError)),
        );
    }
  }

  Future<void> _bluetoothSettings() async {
    try {
      await Library.android.invokeMethod<void>('bluetoothSettings');
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.messages.bluetoothSettingsError)),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    final error = _error;
    final enabled = controller != null;
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
        actions: [
          if (Platform.isAndroid)
            IconButton(
              tooltip: context.messages.bluetoothSettings,
              onPressed: _bluetoothSettings,
              icon: const Icon(Icons.bluetooth),
            ),
          IconButton(
            tooltip: context.messages.checkBrowserFeatures,
            onPressed: _ready && error == null ? _compatibility : null,
            icon: const Icon(Icons.memory),
          ),
        ],
      ),
      body: SafeArea(
        top: false,
        child: Column(
          children: [
            if (_progress < 100 && error == null)
              LinearProgressIndicator(
                value: _progress == 0 ? null : _progress / 100,
              ),
            if (error != null)
              MaterialBanner(
                content: Text(
                  context.messages.pageError(
                    localizedError(context.messages, error),
                  ),
                ),
                actions: [
                  TextButton(
                    onPressed: enabled
                        ? () => _navigate((view) => view.reload())
                        : _start,
                    child: Text(context.messages.retry),
                  ),
                ],
              ),
            Expanded(
              child: controller == null
                  ? const SizedBox.shrink()
                  : WebViewWidget(controller: controller),
            ),
          ],
        ),
      ),
    );
  }
}
