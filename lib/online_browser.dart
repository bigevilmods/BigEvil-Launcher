import 'dart:async';
import 'dart:convert';

import 'package:material_ui/material_ui.dart';
import 'package:webview_all/webview_all.dart';

import 'library.dart';

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
  late final _address = TextEditingController(
    text: widget.initialUrl.toString(),
  );
  WebViewController? _controller;
  WebViewSession? _session;
  int _progress = 0;
  String? _error;
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    _start();
  }

  @override
  void dispose() {
    unawaited(_closeSession());
    _address.dispose();
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
    if (mounted) setState(() => _error = error.toString());
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
        throw StateError(
          'O navegador do sistema está indisponível. Verifique a instalação do motor WebView.',
        );
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
          onPageStarted: (url) {
            if (!mounted) return;
            _address.text = url;
            setState(() {
              _progress = 0;
              _ready = false;
            });
          },
          onPageFinished: (url) {
            if (!mounted) return;
            _address.text = url;
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
      await _go(widget.initialUrl.toString());
    } catch (error) {
      _report(error);
    }
  }

  Future<void> _go(String text) async {
    final url = Library.webUri(text.trim());
    if (url == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Informe um endereço HTTP ou HTTPS válido.'),
        ),
      );
      return;
    }
    await _navigate((controller) => controller.loadRequest(url));
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
          return JSON.stringify({
            'WebAssembly': wasm(),
            'WebGL': supports('webgl'),
            'WebGL 2': supports('webgl2'),
            'Canvas 2D': supports('2d'),
            'Web Audio': !!(window.AudioContext || window.webkitAudioContext),
            'WebGPU': !!navigator.gpu,
            'SharedArrayBuffer': typeof SharedArrayBuffer !== 'undefined',
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
          title: const Text('Recursos nesta página'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final feature in features.entries)
                Text(
                  '${feature.key}: ${feature.value == true ? 'Disponível' : 'Indisponível'}',
                ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Fechar'),
            ),
          ],
        ),
      );
    } catch (_) {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Falha ao verificar os recursos desta página.'),
          ),
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
          IconButton(
            tooltip: 'Verificar WebAssembly, WebGL e outros recursos',
            onPressed: _ready && error == null ? _compatibility : null,
            icon: const Icon(Icons.memory),
          ),
        ],
      ),
      body: SafeArea(
        top: false,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 4, 8, 8),
              child: Row(
                children: [
                  IconButton(
                    tooltip: 'Voltar no navegador',
                    onPressed: enabled
                        ? () => _navigate((view) async {
                            if (await view.canGoBack()) await view.goBack();
                          })
                        : null,
                    icon: const Icon(Icons.chevron_left),
                  ),
                  IconButton(
                    tooltip: 'Avançar no navegador',
                    onPressed: enabled
                        ? () => _navigate((view) async {
                            if (await view.canGoForward())
                              await view.goForward();
                          })
                        : null,
                    icon: const Icon(Icons.chevron_right),
                  ),
                  IconButton(
                    tooltip: 'Recarregar página',
                    onPressed: enabled
                        ? () => _navigate((view) => view.reload())
                        : null,
                    icon: const Icon(Icons.refresh),
                  ),
                  Expanded(
                    child: TextField(
                      controller: _address,
                      enabled: enabled,
                      keyboardType: TextInputType.url,
                      textInputAction: TextInputAction.go,
                      onSubmitted: _go,
                      decoration: const InputDecoration(
                        isDense: true,
                        hintText: 'Endereço',
                      ),
                    ),
                  ),
                ],
              ),
            ),
            if (_progress < 100 && error == null)
              LinearProgressIndicator(
                value: _progress == 0 ? null : _progress / 100,
              ),
            if (error != null)
              MaterialBanner(
                content: Text('Falha ao carregar a página. $error'),
                actions: [
                  TextButton(
                    onPressed: enabled ? () => _go(_address.text) : _start,
                    child: const Text('Tentar novamente'),
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
