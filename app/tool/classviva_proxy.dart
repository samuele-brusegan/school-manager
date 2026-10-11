import 'dart:async';
import 'dart:io';

const _upstreamHost = 'web.spaggiari.eu';
const _upstreamUserAgent = 'CVVS/std/4.1.7 Android/10';
final _allowedOrigin = RegExp(r'^https?://(localhost|127\.0\.0\.1)(:\d+)?$');
const _allowedHeaders = 'content-type, z-dev-apikey, z-auth-token';

Future<void> main() async {
  final port =
      int.tryParse(Platform.environment['CLASSVIVA_PROXY_PORT'] ?? '') ?? 8787;
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, port);
  final upstreamClient = HttpClient()
    ..connectionTimeout = const Duration(seconds: 15);
  server.listen((request) => unawaited(_handle(request, upstreamClient)));
  stdout.writeln(
    'ClasseViva local proxy listening at http://${server.address.address}:${server.port}',
  );
}

Future<void> _handle(HttpRequest request, HttpClient client) async {
  final origin = request.headers.value('origin');
  if (origin == null || !_allowedOrigin.hasMatch(origin)) {
    request.response
      ..statusCode = HttpStatus.forbidden
      ..headers.contentType = ContentType.text
      ..write(
          'Local development proxy accepts localhost browser origins only.');
    await request.response.close();
    return;
  }

  final response = request.response
    ..headers.set(HttpHeaders.accessControlAllowOriginHeader, origin)
    ..headers.set(HttpHeaders.varyHeader, 'Origin')
    ..headers.set(
      HttpHeaders.accessControlAllowMethodsHeader,
      'GET, POST, OPTIONS',
    )
    ..headers.set(HttpHeaders.accessControlAllowHeadersHeader, _allowedHeaders)
    ..headers.set(HttpHeaders.accessControlMaxAgeHeader, '600');

  if (request.method == 'OPTIONS') {
    response.statusCode = HttpStatus.noContent;
    stdout.writeln('[ClasseViva proxy] OPTIONS -> 204 (preflight)');
    await response.close();
    return;
  }

  if ((request.method != 'GET' && request.method != 'POST') ||
      !request.uri.path.startsWith('/rest/')) {
    response
      ..statusCode = HttpStatus.notFound
      ..headers.contentType = ContentType.text
      ..write('Only ClasseViva REST requests are supported.');
    await response.close();
    return;
  }

  var responseStarted = false;
  try {
    final upstreamUri = Uri(
      scheme: 'https',
      host: _upstreamHost,
      path: request.uri.path,
      query: request.uri.hasQuery ? request.uri.query : null,
    );
    final upstreamRequest = await client.openUrl(request.method, upstreamUri);
    final contentType = request.headers.value(HttpHeaders.contentTypeHeader);
    if (contentType != null) {
      upstreamRequest.headers.set(HttpHeaders.contentTypeHeader, contentType);
    }
    for (final name in ['Z-Dev-ApiKey', 'Z-Auth-Token']) {
      final value = request.headers.value(name);
      if (value != null) upstreamRequest.headers.set(name, value);
    }
    upstreamRequest.headers
        .set(HttpHeaders.userAgentHeader, _upstreamUserAgent);
    await upstreamRequest.addStream(request);

    final upstreamResponse = await upstreamRequest.close();
    stdout.writeln(
      '[ClasseViva proxy] ${request.method} ${_safePath(request.uri.path)} '
      '-> ${upstreamResponse.statusCode} from upstream '
      '(${upstreamResponse.contentLength} bytes)',
    );
    response
      ..statusCode = upstreamResponse.statusCode
      ..headers.set(HttpHeaders.cacheControlHeader, 'no-store');
    responseStarted = true;
    final upstreamContentType =
        upstreamResponse.headers.value(HttpHeaders.contentTypeHeader);
    if (upstreamContentType != null) {
      response.headers.set(HttpHeaders.contentTypeHeader, upstreamContentType);
    }
    await response.addStream(upstreamResponse);
    await response.close();
  } on Object {
    if (!responseStarted) {
      response
        ..statusCode = HttpStatus.badGateway
        ..headers.contentType = ContentType.text
        ..write('ClasseViva upstream request failed.');
    }
    await response.close();
  }
}

String _safePath(String path) {
  if (path == '/rest/v1/auth/login') return path;
  if (path.startsWith('/rest/v1/students/')) return '/rest/v1/students/:id/...';
  return '/rest/...';
}
