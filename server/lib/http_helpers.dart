import 'dart:convert';

import 'package:shelf/shelf.dart';

Response jsonResponse(Object data, {int status = 200}) => Response(
      status,
      body: jsonEncode(data),
      headers: {'Content-Type': 'application/json'},
    );

Response errorResponse(String message, {int status = 400}) => jsonResponse({'error': message}, status: status);

Future<Map<String, dynamic>> bodyJson(Request request) async {
  final raw = await request.readAsString();
  if (raw.isEmpty) return {};
  return jsonDecode(raw) as Map<String, dynamic>;
}

/// `row.typedAssoc()` (mysql_client_plus) puede traer valores que
/// `jsonEncode` no sabe convertir por sí solo, como `DateTime` para columnas
/// TIMESTAMP/DATETIME. Esto normaliza esos valores a algo serializable antes
/// de mandar una fila de la base de datos como respuesta HTTP.
Map<String, dynamic> jsonSafeRow(Map<String, dynamic> row) {
  return row.map((key, value) {
    if (value is DateTime) return MapEntry(key, value.toIso8601String());
    return MapEntry(key, value);
  });
}
