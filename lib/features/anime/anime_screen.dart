import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';
import 'package:webview_flutter/webview_flutter.dart';
import '../../design/yoma_tokens.dart';
import '../../services/myanimelist_service.dart';

class AnimeScreen extends StatefulWidget {
  final bool active;
  final bool syncMal;
  final Uri? initialUrl;
  const AnimeScreen({
    super.key,
    required this.active,
    this.syncMal = true,
    this.initialUrl,
  });
  @override
  State<AnimeScreen> createState() => AnimeScreenState();
}

class AnimeScreenState extends State<AnimeScreen> with WidgetsBindingObserver {
  static const _native = MethodChannel('app.yoma/anime');
  bool _nativeReady = false;
  int? _nativeId;
  String? _nativeScript;
  static final site = Uri.parse('https://hk-br035.gt.tc/seasonav1/');
  WebViewController? _controller;
  String? _error;
  int _progress = 0;
  bool _syncing = false;
  bool _hasSynced = false;
  String? _syncedToken;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    MyAnimeListService.shared.client.sessionChanges.addListener(
      _sessionChanged,
    );
    if (!Platform.isAndroid && !Platform.isIOS) return;
    final controller = WebViewController();
    _controller = controller;
    unawaited(_initialize(controller));
  }

  Future<void> _initialize(WebViewController controller) async {
    try {
      await controller.setJavaScriptMode(JavaScriptMode.unrestricted);
      await controller.setBackgroundColor(YomaColors.background);
      await controller.setNavigationDelegate(
        NavigationDelegate(
          onPageFinished: (url) async {
            final uri = Uri.tryParse(url);
            if (_nativeReady &&
                uri != null &&
                uri.scheme == 'https' &&
                uri.host == site.host &&
                uri.path.startsWith(site.path)) {
              await controller.runJavaScript(_nativeScript!);
            }
          },
          onProgress: (value) {
            if (mounted) setState(() => _progress = value);
          },
          onPageStarted: (_) {
            if (mounted) setState(() => _error = null);
          },
          onWebResourceError: (error) {
            if (mounted && error.isForMainFrame == true) {
              setState(
                () => _error =
                    'No se pudo conectar con YomaTV. Revisa tu conexión y vuelve a intentar.',
              );
            }
          },
          onHttpError: (error) {
            if (mounted &&
                error.request?.uri.path == '/seasonav1/yoma-session.php' &&
                error.response?.statusCode != 409) {
              setState(
                () => _error =
                    'No se pudo compartir MAL. El servidor necesita yoma-session.php. Puedes abrir el catálogo con Reintentar.',
              );
            }
          },
          onNavigationRequest: (request) {
            final uri = Uri.tryParse(request.url);
            if (!request.isMainFrame) return NavigationDecision.navigate;
            if (uri != null &&
                uri.scheme == 'https' &&
                uri.userInfo.isEmpty &&
                uri.port == 443 &&
                (uri.host == site.host ||
                    uri.host == 'myanimelist.net' ||
                    uri.host == 'www.myanimelist.net')) {
              return NavigationDecision.navigate;
            }
            return NavigationDecision.prevent;
          },
        ),
      );
      if (Platform.isAndroid) {
        final android = controller.platform as AndroidWebViewController;
        _nativeId = android.webViewIdentifier;
        _nativeReady =
            await _native.invokeMethod<bool>('attach', _nativeId) ?? false;
        if (_nativeReady) {
          _nativeScript = await _native.invokeMethod<String>('script');
        }
      }
      await controller.loadRequest(widget.initialUrl ?? site);
      if (widget.syncMal) await _syncSession();
    } catch (e) {
      if (mounted) {
        setState(() => _error = 'No se pudo iniciar el navegador: $e');
      }
    }
  }

  void _sessionChanged() => unawaited(_syncSession());

  Future<void> _syncSession() async {
    if (!widget.syncMal || _syncing || _controller == null) return;
    _syncing = true;
    try {
      final auth = await MyAnimeListService.shared.client.credentials.load();
      final token = auth?['connected'] == true
          ? (auth?['device_token'] as String?)
          : null;
      if (_hasSynced && token == _syncedToken) return;
      // A native credential is sent only to the fixed HTTPS endpoint, never JS,
      // localStorage, query parameters, third-party frames or a redirect chain.
      if (token != null) {
        await _controller!.loadRequest(
          site.resolve('yoma-session.php'),
          headers: {'X-YomaShi-Token': token},
        );
      } else {
        await WebViewCookieManager().clearCookies();
        await _controller!.loadRequest(site);
      }
      _syncedToken = token;
      _hasSynced = true;
    } catch (e) {
      if (mounted) {
        setState(() => _error = 'No se pudo compartir la cuenta MAL: $e');
      }
    } finally {
      _syncing = false;
    }
  }

  @override
  void didUpdateWidget(covariant AnimeScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.active && !oldWidget.active) unawaited(_syncSession());
    if (widget.active && !oldWidget.active && _nativeReady) {
      unawaited(
        _controller?.runJavaScript(
              "window.dispatchEvent(new Event('season-native-resume'))",
            ) ??
            Future.value(),
      );
    }
    if (!widget.active && oldWidget.active) {
      unawaited(
        _controller?.runJavaScript(
              "window.dispatchEvent(new Event('season-native-suspend')); document.querySelectorAll('video,audio').forEach(v=>v.pause())",
            ) ??
            Future.value(),
      );
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && widget.active && _nativeReady) {
      unawaited(
        _controller?.runJavaScript(
              "window.dispatchEvent(new Event('season-native-resume'))",
            ) ??
            Future.value(),
      );
    }
  }

  Future<void> _downloads() async {
    try {
      await _native.invokeMethod<void>('downloads');
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(e.toString())));
      }
    }
  }

  Future<bool> goBack() async {
    final controller = _controller;
    if (controller != null && await controller.canGoBack()) {
      await controller.goBack();
      return true;
    }
    return false;
  }

  @override
  void dispose() {
    MyAnimeListService.shared.client.sessionChanges.removeListener(
      _sessionChanged,
    );
    WidgetsBinding.instance.removeObserver(this);
    if (_nativeId != null) {
      unawaited(_native.invokeMethod<void>('detach', _nativeId));
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('YomaTV'),
      leading: IconButton(
        onPressed: goBack,
        tooltip: 'Atrás en YomaTV',
        icon: const Icon(Icons.arrow_back),
      ),
      actions: [
        if (Platform.isAndroid)
          IconButton(
            tooltip: 'Descargas de anime',
            onPressed: _downloads,
            icon: const Icon(Icons.download_outlined),
          ),
        IconButton(
          tooltip: 'Compartir cuenta MAL',
          onPressed: _syncSession,
          icon: const Icon(Icons.account_circle_outlined),
        ),
        IconButton(
          tooltip: 'Recargar',
          onPressed: () => _controller?.reload(),
          icon: const Icon(Icons.refresh),
        ),
      ],
    ),
    body: _controller == null
        ? const Center(
            child: Text('YomaTV está disponible en la aplicación Android.'),
          )
        : Stack(
            children: [
              WebViewWidget(controller: _controller!),
              if (_progress < 100)
                LinearProgressIndicator(value: _progress / 100),
              if (_error != null)
                ColoredBox(
                  color: Theme.of(context).colorScheme.surface,
                  child: Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.cloud_off_outlined, size: 48),
                          const SizedBox(height: 16),
                          Text(_error!, textAlign: TextAlign.center),
                          const SizedBox(height: 16),
                          FilledButton(
                            onPressed: () {
                              setState(() => _error = null);
                              _controller!.loadRequest(site);
                            },
                            child: const Text('Reintentar'),
                          ),
                          const SizedBox(height: 12),
                          const Text(
                            'Tu biblioteca de manga sigue disponible.',
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          ),
  );
}
