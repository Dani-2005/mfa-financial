import 'dart:io';

import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart';
import 'package:shelf_router/shelf_router.dart';

import 'package:maf_api_server/auditoria_routes.dart';
import 'package:maf_api_server/auth_routes.dart';
import 'package:maf_api_server/cliente_routes.dart';
import 'package:maf_api_server/dashboard_routes.dart';
import 'package:maf_api_server/database_service.dart';
import 'package:maf_api_server/graficas_routes.dart';
import 'package:maf_api_server/pago_routes.dart';
import 'package:maf_api_server/prestamo_routes.dart';
import 'package:maf_api_server/reporte_routes.dart';

Future<void> main() async {
  final app = Router();

  app.get('/health', (Request request) async {
    final ok = await DatabaseService.instance.testConnection();
    return Response.ok(
      '{"status":"${ok ? 'ok' : 'db_error'}"}',
      headers: {'Content-Type': 'application/json'},
    );
  });

  app.mount('/api/auth/', buildAuthRouter().call);
  app.mount('/api/clientes/', buildClienteRouter().call);
  app.mount('/api/auditoria/', buildAuditoriaRouter().call);
  app.mount('/api/prestamos/', buildPrestamoRouter().call);
  app.mount('/api/pagos/', buildPagoRouter().call);
  app.mount('/api/dashboard/', buildDashboardRouter().call);
  app.mount('/api/graficas/', buildGraficasRouter().call);
  app.mount('/api/reportes/', buildReporteRouter().call);

  final handler = const Pipeline().addMiddleware(logRequests()).addHandler(app.call);

  final port = int.tryParse(Platform.environment['PORT'] ?? '8080') ?? 8080;
  final server = await serve(handler, InternetAddress.anyIPv4, port);
  print('Servidor MAF API corriendo en el puerto ${server.port}');
}
