import 'dart:async';
import 'dart:io';
import '../utils/app_failure.dart';
import 'diagnostics.dart';

/// Cada operación conserva sus propios plazos y señal de cancelación.
class SourceHttpClient {
  static final Object _cancelKey = Object();
  static CancellationToken? get currentCancellation =>
      Zone.current[_cancelKey] as CancellationToken?;
  static Future<T> withCancellation<T>(
    CancellationToken token,
    Future<T> Function() work,
  ) => runZoned(work, zoneValues: {_cancelKey: token});
  final HttpClient _client;
  final Duration bodyTimeout;
  final int maxBodyBytes;
  SourceHttpClient({
    HttpClient? client,
    this.bodyTimeout = const Duration(minutes: 3),
    this.maxBodyBytes = 16 * 1024 * 1024,
  }) : _client = client ?? HttpClient() {
    _client.connectionTimeout = const Duration(seconds: 25);
    _client.maxConnectionsPerHost = 6;
  }
  set idleTimeout(Duration value) => _client.idleTimeout = value;
  set connectionTimeout(Duration? value) => _client.connectionTimeout = value;
  set autoUncompress(bool value) => _client.autoUncompress = value;
  Future<HttpClientRequest> getUrl(Uri uri) => _open(uri, false);
  Future<HttpClientRequest> postUrl(Uri uri) => _open(uri, true);
  Future<HttpClientRequest> _open(Uri uri, bool post) async {
    final token = currentCancellation;
    token?.check();
    try {
      final pending = post ? _client.postUrl(uri) : _client.getUrl(uri);
      var expired = false;
      unawaited(
        pending.then((request) {
          if (expired || token?.isCancelled == true) request.abort();
        }, onError: (Object _) {}),
      );
      final request = await pending.timeout(
        const Duration(seconds: 25),
        onTimeout: () {
          expired = true;
          throw const AppFailure(
            FailureKind.timeout,
            'La conexión agotó el tiempo de espera.',
          );
        },
      );
      if (token?.isCancelled == true) {
        request.abort();
        token!.check();
      }
      return _BoundedRequest(request, uri, bodyTimeout, maxBodyBytes, token);
    } catch (error) {
      throw AppFailure.from(error);
    }
  }

  void close({bool force = false}) => _client.close(force: force);
}

class _BoundedRequest implements HttpClientRequest {
  final HttpClientRequest _request;
  @override
  final Uri uri;
  final Duration bodyTimeout;
  final int maxBodyBytes;
  final CancellationToken? token;
  void Function()? _removeAbort;
  _BoundedRequest(
    this._request,
    this.uri,
    this.bodyTimeout,
    this.maxBodyBytes,
    this.token,
  ) {
    _removeAbort = token?.onCancel(
      () => _request.abort(
        const AppFailure(FailureKind.cancelled, 'Solicitud cancelada.'),
      ),
    );
  }
  @override
  HttpHeaders get headers => _request.headers;
  @override
  set followRedirects(bool value) => _request.followRedirects = value;
  @override
  bool get followRedirects => _request.followRedirects;
  @override
  set maxRedirects(int value) => _request.maxRedirects = value;
  @override
  int get maxRedirects => _request.maxRedirects;
  @override
  void add(List<int> data) => _request.add(data);
  @override
  void abort([Object? exception, StackTrace? stackTrace]) {
    _removeAbort?.call();
    _request.abort(exception, stackTrace);
  }

  @override
  Future<HttpClientResponse> close() async {
    try {
      final response = await _request.close().timeout(
        const Duration(seconds: 40),
        onTimeout: () {
          _request.abort();
          throw const AppFailure(
            FailureKind.timeout,
            'El servidor no respondió.',
          );
        },
      );
      token?.check();
      if (response.statusCode >= 400) {
        final raw = response.headers.value('retry-after');
        final seconds = int.tryParse(raw ?? '');
        DateTime? date;
        try {
          if (raw != null && seconds == null) date = HttpDate.parse(raw);
        } catch (_) {}
        await response.listen((_) {}).cancel();
        throw AppFailure(
          FailureKind.http,
          'HTTP ${response.statusCode}: ${uri.host}',
          statusCode: response.statusCode,
          retryAfter: seconds != null
              ? Duration(seconds: seconds)
              : date?.difference(DateTime.now()),
        );
      }
      return _BoundedResponse(
        response,
        bodyTimeout,
        maxBodyBytes,
        () => _removeAbort?.call(),
      );
    } catch (error) {
      _removeAbort?.call();
      unawaited(Diagnostics.record('http:${uri.host}', error));
      throw AppFailure.from(error);
    }
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _BoundedResponse extends StreamView<List<int>>
    implements HttpClientResponse {
  final HttpClientResponse _response;
  _BoundedResponse(
    this._response,
    Duration timeout,
    int maxBytes,
    void Function() cleanup,
  ) : super(_bounded(_response, timeout, maxBytes, cleanup));
  static Stream<List<int>> _bounded(
    HttpClientResponse response,
    Duration timeout,
    int maxBytes,
    void Function() cleanup,
  ) {
    return Stream<List<int>>.multi((controller) {
      late StreamSubscription<List<int>> subscription;
      final timer = Timer(timeout, () {
        controller.addError(
          const AppFailure(
            FailureKind.timeout,
            'La transferencia superó el tiempo máximo.',
          ),
        );
        unawaited(subscription.cancel());
        cleanup();
        controller.close();
      });
      var bytes = 0;
      subscription = response
          .timeout(const Duration(seconds: 30))
          .listen(
            (chunk) {
              bytes += chunk.length;
              if (bytes > maxBytes) {
                controller.addError(
                  const AppFailure(
                    FailureKind.parsing,
                    'La respuesta supera el tamaño permitido.',
                  ),
                );
                timer.cancel();
                cleanup();
                unawaited(subscription.cancel());
                controller.close();
              } else {
                controller.add(chunk);
              }
            },
            onError: controller.addError,
            onDone: () {
              timer.cancel();
              cleanup();
              controller.close();
            },
          );
      controller.onCancel = () async {
        timer.cancel();
        cleanup();
        await subscription.cancel();
      };
      controller.onPause = subscription.pause;
      controller.onResume = subscription.resume;
    });
  }

  @override
  int get statusCode => _response.statusCode;
  @override
  HttpHeaders get headers => _response.headers;
  @override
  int get contentLength => _response.contentLength;
  @override
  HttpClientResponseCompressionState get compressionState =>
      _response.compressionState;
  @override
  List<RedirectInfo> get redirects => _response.redirects;
  @override
  bool get isRedirect => _response.isRedirect;
  @override
  String get reasonPhrase => _response.reasonPhrase;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
