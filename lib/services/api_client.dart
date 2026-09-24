import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart' show rootBundle;

/// Respuesta ya decodificada de una llamada al servidor API.
class ApiResponse {
  final int statusCode;
  final Map<String, dynamic> data;
  const ApiResponse(this.statusCode, this.data);

  bool get ok => statusCode >= 200 && statusCode < 300;
}

/// Se lanza en vez de la excepción de red original (`SocketException`,
/// `TimeoutException`, etc.) cuando una llamada al servidor no pudo ni
/// siquiera conectar: no hay internet, el VPS no responde, o la conexión se
/// cortó a mitad de la petición. Trae un mensaje ya listo para mostrar en la
/// UI, distinto del genérico "no se pudo cargar/guardar" que se usa cuando
/// el servidor sí respondió pero con un error.
class NoConnectionException implements Exception {
  final String message;
  const NoConnectionException([this.message = 'Sin conexión a internet. Verifica tu red e intenta de nuevo.']);

  @override
  String toString() => message;
}

/// Cliente HTTP hacia el servidor MAF API en el VPS, con el certificado TLS
/// anclado ("certificate pinning"): en vez de confiar en las autoridades
/// certificadoras normales del sistema (el servidor usa un certificado
/// autofirmado, no uno de una autoridad real), esta app solo confía en el
/// certificado exacto empaquetado en `assets/maf_api_cert.pem`. Cualquier
/// otro certificado — incluso uno válido de otra autoridad — se rechaza,
/// lo que en la práctica es más resistente a ataques de intermediario que
/// el modelo de confianza normal.
class ApiClient {
  ApiClient._();
  static final ApiClient instance = ApiClient._();

  static const String baseUrl = 'https://2.25.242.253';

  HttpClient? _client;

  Future<HttpClient> _getClient() async {
    final existing = _client;
    if (existing != null) return existing;

    final certData = await rootBundle.load('assets/maf_api_cert.pem');
    final context = SecurityContext(withTrustedRoots: false);
    context.setTrustedCertificatesBytes(certData.buffer.asUint8List());

    final client = HttpClient(context: context);
    // La validación normal ya solo confía en el certificado anclado arriba;
    // este callback solo se invoca si esa validación falla, así que
    // siempre se rechaza (nunca se acepta un certificado no anclado).
    client.badCertificateCallback = (cert, host, port) => false;
    client.connectionTimeout = const Duration(seconds: 15);
    _client = client;
    return client;
  }

  Future<ApiResponse> get(String path, {Map<String, String>? headers}) => _conManejoDeConexion(() async {
        final client = await _getClient();
        final request = await client.getUrl(Uri.parse('$baseUrl$path'));
        headers?.forEach(request.headers.set);
        final response = await request.close();
        return _parse(response);
      });

  Future<ApiResponse> post(String path, {Map<String, String>? headers, Map<String, dynamic>? body}) =>
      _conManejoDeConexion(() async {
        final client = await _getClient();
        final request = await client.postUrl(Uri.parse('$baseUrl$path'));
        request.headers.set('Content-Type', 'application/json; charset=utf-8');
        headers?.forEach(request.headers.set);
        // request.write() codificaría el texto con Latin-1 por defecto (el
        // charset por defecto de HttpClientRequest cuando no se fija encoding
        // explícito), lo cual rompe cualquier acento/ñ al decodificarse como
        // UTF-8 del lado del servidor. Se codifica a bytes UTF-8 a mano.
        request.add(utf8.encode(jsonEncode(body ?? {})));
        final response = await request.close();
        return _parse(response);
      });

  Future<ApiResponse> put(String path, {Map<String, String>? headers, Map<String, dynamic>? body}) =>
      _conManejoDeConexion(() async {
        final client = await _getClient();
        final request = await client.putUrl(Uri.parse('$baseUrl$path'));
        request.headers.set('Content-Type', 'application/json; charset=utf-8');
        headers?.forEach(request.headers.set);
        request.add(utf8.encode(jsonEncode(body ?? {})));
        final response = await request.close();
        return _parse(response);
      });

  /// Convierte cualquier falla de red real (sin internet, VPS caído, TLS
  /// interrumpido, timeout) en [NoConnectionException], para distinguirla de
  /// un error de negocio donde el servidor sí respondió. Se atrapa CUALQUIER
  /// excepción aquí (no solo `SocketException`/`TimeoutException`) a
  /// propósito: según el sistema operativo y el tipo exacto de corte de red,
  /// `dart:io` puede lanzar otros tipos (`TlsException`, `OSError`, etc.) —
  /// lo único que corre dentro de [accion] es la conexión HTTP en sí, así
  /// que cualquier excepción que llegue hasta aquí es, en la práctica,
  /// siempre un problema de conectividad.
  Future<ApiResponse> _conManejoDeConexion(Future<ApiResponse> Function() accion) async {
    try {
      return await accion();
    } catch (_) {
      throw const NoConnectionException();
    }
  }

  Future<ApiResponse> _parse(HttpClientResponse response) async {
    final raw = await response.transform(utf8.decoder).join();
    Map<String, dynamic> data = const {};
    if (raw.isNotEmpty) {
      try {
        data = jsonDecode(raw) as Map<String, dynamic>;
      } catch (_) {
        data = const {};
      }
    }
    return ApiResponse(response.statusCode, data);
  }
}
