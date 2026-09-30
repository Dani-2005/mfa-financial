import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

/// Genera el PDF del "Plan de Pagos" de un préstamo puntual: encabezado con
/// los datos del préstamo (código, cliente, tipo de tasa/cálculo,
/// frecuencia, fecha, tasa de interés, si tiene cambio de tasa programado o
/// es una operación por fases) y la tabla de cuotas completa, con los
/// movimientos de capital (inyecciones/retiros) resaltados justo arriba de
/// la cuota a partir de la cual se aplican.
class PlanPagosPdfService {
  static const _emisorNombre = 'Miguel A. Flores';
  static const _emisorDireccion = '8953 E Captian Dreyfus Ave Scottsdale, AZ 85260';
  static const _emisorCorreo = 'michelfloresl@hotmail.com';

  static final _colorEncabezado = PdfColor.fromHex('#1F3864');

  static Future<Uint8List> generar({
    required Map<String, dynamic> detalle,
    required List<Map<String, dynamic>> cuotas,
    required List<Map<String, dynamic>> movimientos,
  }) async {
    final doc = pw.Document();
    final fechaGeneracion = _formatFechaHora(DateTime.now());
    final mesCambioTasa = detalle['mesCambioTasa'] as int?;
    final nuevaTasaInteres = detalle['nuevaTasaInteres'] as String?;

    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.letter,
        margin: const pw.EdgeInsets.all(28),
        header: (context) => context.pageNumber == 1
            ? pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  _buildEncabezado(detalle, fechaGeneracion),
                  pw.SizedBox(height: 14),
                ],
              )
            : pw.SizedBox(),
        build: (context) => [
          pw.Text(
            'Plan de Pagos (Cuotas)',
            style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold, color: _colorEncabezado),
          ),
          if (movimientos.isNotEmpty || mesCambioTasa != null) ...[
            pw.SizedBox(height: 2),
            pw.Text(
              'Los movimientos de capital (inyecciones/retiros) y el cambio de tasa, si los hay, '
              'aparecen resaltados justo arriba de la cuota a partir de la cual se aplican.',
              style: pw.TextStyle(fontSize: 8, fontStyle: pw.FontStyle.italic, color: PdfColors.grey700),
            ),
          ],
          pw.SizedBox(height: 6),
          _buildTablaCuotasConMovimientos(
            cuotas,
            movimientos,
            mesCambioTasa: mesCambioTasa,
            nuevaTasaInteres: nuevaTasaInteres,
          ),
          if (cuotas.any((c) => c['capitalizado'] == 'Sí')) ...[
            pw.SizedBox(height: 6),
            pw.Text(
              '* Las cuotas con Capitalizado = "Sí" salen como "Pagado" aunque el cliente no las pagó: '
              'el interés se reinvierte automáticamente en el saldo en vez de cobrarse, así que no '
              'cuenta en el total de intereses pagados de abajo.',
              style: pw.TextStyle(fontSize: 8, fontStyle: pw.FontStyle.italic, color: PdfColors.grey700),
            ),
          ],
          if (cuotas.any((c) => c['estado'] == 'Parcial')) ...[
            pw.SizedBox(height: 6),
            pw.Text(
              '* Este préstamo tiene cuotas en Pago Parcial: como no se puede separar con precisión cuánto '
              'de ese abono fue interés y cuánto capital, esas cuotas no están incluidas en los totales de '
              'intereses de abajo (ni en Pagados ni en Restantes por Cobrar).',
              style: pw.TextStyle(fontSize: 8, fontStyle: pw.FontStyle.italic, color: PdfColors.grey700),
            ),
          ],
          pw.SizedBox(height: 14),
          _buildTotalesPagados(detalle, cuotas, movimientos),
        ],
      ),
    );

    return doc.save();
  }

  /// Suma un campo numérico (interés o amortización de capital) de las
  /// cuotas en el [estado] pedido ('Pagado' o 'Pendiente') y no
  /// capitalizadas: el interés capitalizado se reinvierte en el saldo en
  /// vez de cobrarse, así que esas cuotas no representan dinero que el
  /// cliente pagó o debe pagar de verdad. Las cuotas 'Parcial' quedan
  /// fuera de ambos lados (ver el aviso que se muestra en el PDF cuando
  /// las hay): no se puede separar con precisión cuánto de ese abono fue
  /// interés y cuánto capital con los datos disponibles aquí.
  static double _sumaPorEstado(List<Map<String, dynamic>> cuotas, String clave, String estado) {
    return cuotas
        .where((c) => c['estado'] == estado && c['capitalizado'] != 'Sí')
        .fold<double>(0, (suma, c) => suma + ((c[clave] as num?)?.toDouble() ?? 0));
  }

  /// Suma los movimientos de capital tipo "Retiro": un abono a capital
  /// (pago extra que reduce el saldo directo, fuera del cronograma normal
  /// de cuotas) se guarda como uno de estos, así que no aparece en la
  /// amortización de ninguna cuota y hay que sumarlo aparte. Los de tipo
  /// "Inyección" quedan afuera a propósito: son capital que se agregó al
  /// préstamo, no capital que el cliente pagó.
  static double _totalRetirosCapital(List<Map<String, dynamic>> movimientos) {
    return movimientos
        .where((m) => m['esInyeccion'] == false)
        .fold<double>(0, (suma, m) => suma + ((m['montoNumerico'] as num?)?.toDouble() ?? 0));
  }

  /// Recuadro final con los totales de interés (Pagados y Restantes por
  /// Cobrar — ninguno de los dos incluye cuotas 'Parcial', ver el aviso que
  /// se muestra en el PDF cuando las hay), el total de capital abonado (si
  /// el préstamo ya tuvo abonos — no se muestra si todavía es $0) y,
  /// siempre, el capital restante actual del préstamo (aunque sea $0, que
  /// significa que ya está pagado).
  static pw.Widget _buildTotalesPagados(
    Map<String, dynamic> detalle,
    List<Map<String, dynamic>> cuotas,
    List<Map<String, dynamic>> movimientos,
  ) {
    final totalInteresesPagados = _sumaPorEstado(cuotas, 'interesMonto', 'Pagado');
    final totalInteresesRestantes = _sumaPorEstado(cuotas, 'interesMonto', 'Pendiente');
    final totalCapital = _sumaPorEstado(cuotas, 'amortizacionMonto', 'Pagado') + _totalRetirosCapital(movimientos);
    final saldoActual = detalle['saldoActual'] as String? ?? _formatMoney(0);

    return pw.Container(
      width: double.infinity,
      padding: const pw.EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: pw.BoxDecoration(
        color: PdfColors.grey100,
        borderRadius: pw.BorderRadius.circular(6),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          _filaTotal('TOTAL DE INTERESES PAGADOS', totalInteresesPagados),
          pw.SizedBox(height: 6),
          _filaTotal('INTERESES RESTANTES POR COBRAR', totalInteresesRestantes),
          pw.SizedBox(height: 6),
          if (totalCapital > 0) ...[
            _filaTotal('TOTAL DE CAPITAL ABONADO', totalCapital),
            pw.SizedBox(height: 6),
          ],
          _filaTotalTexto('CAPITAL RESTANTE', saldoActual),
        ],
      ),
    );
  }

  static pw.Widget _filaTotal(String etiqueta, double total) {
    return _filaTotalTexto(etiqueta, _formatMoney(total));
  }

  static pw.Widget _filaTotalTexto(String etiqueta, String montoTexto) {
    return pw.Row(
      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
      children: [
        pw.Text(
          etiqueta,
          style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold, color: _colorEncabezado),
        ),
        pw.Text(
          montoTexto,
          style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold),
        ),
      ],
    );
  }

  static String _formatMoney(double value) {
    final isNegative = value < 0;
    final parts = value.abs().toStringAsFixed(2).split('.');
    final intPart = parts[0];
    final buffer = StringBuffer();
    for (int i = 0; i < intPart.length; i++) {
      if (i > 0 && (intPart.length - i) % 3 == 0) buffer.write('.');
      buffer.write(intPart[i]);
    }
    return '${isNegative ? '-' : ''}\$${buffer.toString()},${parts[1]}';
  }

  static pw.Widget _buildEncabezado(Map<String, dynamic> detalle, String fechaGeneracion) {
    final tipoTasa = detalle['tipoTasa'] as String;
    final tipoCalculo = detalle['tipoCalculo'] as String;
    final mesCambioTasa = detalle['mesCambioTasa'] as int?;
    final nuevaTasaInteres = detalle['nuevaTasaInteres'] as String?;
    final mesCambioCapitalizacion = detalle['mesCambioCapitalizacion'] as int?;

    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(_emisorNombre, style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold)),
                pw.SizedBox(height: 4),
                pw.Text(_emisorDireccion, style: const pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold)),
                pw.Text(_emisorCorreo, style: const pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold)),
              ],
            ),
            pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.end,
              children: [
                pw.Text('Plan de Pagos', style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold)),
                pw.SizedBox(height: 4),
                pw.Text('Generado: $fechaGeneracion', style: const pw.TextStyle(fontSize: 9)),
                pw.Text('Préstamo #${detalle['codigoReferencia']}', style: const pw.TextStyle(fontSize: 9)),
                if ((detalle['nombrePrestamo'] as String?)?.isNotEmpty == true)
                  pw.Text('${detalle['nombrePrestamo']}', style: const pw.TextStyle(fontSize: 9)),
              ],
            ),
          ],
        ),
        pw.SizedBox(height: 14),
        pw.Container(
          padding: const pw.EdgeInsets.all(10),
          decoration: pw.BoxDecoration(
            color: PdfColors.grey100,
            borderRadius: pw.BorderRadius.circular(6),
          ),
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Row(
                children: [
                  _campo('Cliente', '${detalle['clienteNombre']} (${detalle['clienteDocumento']})'),
                  _campo('Tipo', '$tipoTasa · $tipoCalculo'),
                ],
              ),
              pw.SizedBox(height: 6),
              pw.Row(
                children: [
                  _campo('Frecuencia', '${detalle['frecuenciaPago']}'),
                  _campo('Fecha de Inicio', '${detalle['fechaInicio']}'),
                  _campo('Nº de Cuotas', '${detalle['numeroCuotas']}'),
                ],
              ),
              pw.SizedBox(height: 6),
              pw.Row(
                children: [
                  _campo('Tasa de Interés', '${detalle['tasaInteresMensual']}'),
                  if (tipoTasa == 'Variable' && mesCambioTasa != null)
                    _campo(
                      'Cambio de Tasa',
                      'A partir de la cuota $mesCambioTasa, nueva tasa: $nuevaTasaInteres',
                    ),
                ],
              ),
              if (mesCambioCapitalizacion != null) ...[
                pw.SizedBox(height: 6),
                pw.Text(
                  'Operación por fases: capitaliza hasta la cuota ${mesCambioCapitalizacion - 1}, '
                  'a partir de la cuota $mesCambioCapitalizacion pasa a pago líquido (renta fija).',
                  style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  static pw.Widget _campo(String etiqueta, String valor) {
    return pw.Expanded(
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(etiqueta.toUpperCase(), style: pw.TextStyle(fontSize: 7, color: PdfColors.grey700)),
          pw.Text(valor, style: const pw.TextStyle(fontSize: 9)),
        ],
      ),
    );
  }

  static const _columnasCuotas = ['Periodo', 'Fecha', 'Saldo Inicio', 'Tasa', 'Interés', 'Amortización', 'Capitalizado', 'Saldo Fin', 'Estado'];
  static const _clavesCuotas = ['periodo', 'fecha', 'saldoInicio', 'tasa', 'interes', 'amortizacion', 'capitalizado', 'saldoFin', 'estado'];
  // Columnas numéricas: van alineadas a la derecha (título incluido) para que
  // las cifras queden en columna. Fecha, Capitalizado y Estado son texto.
  static const _clavesNumericas = {'periodo', 'saldoInicio', 'tasa', 'interes', 'amortizacion', 'saldoFin'};

  /// Construye la tabla de cuotas insertando, justo arriba de la cuota a
  /// partir de la cual se aplica cada movimiento de capital (o el cambio de
  /// tasa, si lo hay), una fila resaltada que lo indica. Como esa fila no
  /// tiene un valor por columna, la tabla se parte en dos tablas seguidas
  /// (una que termina antes del aviso y otra que retoma después) con una
  /// franja de ancho completo en medio, para que se vea como una fila más
  /// dentro de la misma tabla en vez de un bloque aparte.
  static pw.Widget _buildTablaCuotasConMovimientos(
    List<Map<String, dynamic>> cuotas,
    List<Map<String, dynamic>> movimientos, {
    int? mesCambioTasa,
    String? nuevaTasaInteres,
  }) {
    final pendientes = List<Map<String, dynamic>>.from(movimientos);
    final widgets = <pw.Widget>[];
    var segmento = <Map<String, dynamic>>[];
    var esPrimerSegmento = true;

    void cerrarSegmento() {
      if (segmento.isEmpty) return;
      widgets.add(_buildTablaCuotas(segmento, incluirEncabezado: esPrimerSegmento));
      esPrimerSegmento = false;
      segmento = [];
    }

    for (final cuota in cuotas) {
      final periodoCuota = int.tryParse('${cuota['periodo']}');
      final aplicanAqui = pendientes.where((m) => int.tryParse('${m['periodo']}') == periodoCuota).toList();
      final hayCambioTasa = mesCambioTasa != null && periodoCuota == mesCambioTasa;
      if (aplicanAqui.isNotEmpty || hayCambioTasa) {
        cerrarSegmento();
        if (hayCambioTasa) {
          widgets.add(_filaCambioTasa(nuevaTasaInteres));
        }
        for (final mov in aplicanAqui) {
          widgets.add(_filaMovimiento(mov));
          pendientes.remove(mov);
        }
      }
      segmento.add(cuota);
    }
    cerrarSegmento();
    // Movimientos cuyo período no calzó con ninguna cuota (no debería pasar
    // en la práctica, pero así no se pierden silenciosamente).
    for (final mov in pendientes) {
      widgets.add(_filaMovimiento(mov));
    }

    return pw.Column(children: widgets);
  }

  static pw.Widget _buildTablaCuotas(List<Map<String, dynamic>> cuotas, {bool incluirEncabezado = true}) {
    return pw.Table(
      border: pw.TableBorder.all(color: PdfColors.grey400, width: 0.5),
      // Anchos según el contenido (mismo orden que _columnasCuotas): con
      // columnas iguales los saldos grandes se partían en dos líneas y
      // "AMORTIZACIÓN"/"CAPITALIZADO" se cortaban a mitad de palabra.
      columnWidths: const {
        0: pw.FlexColumnWidth(0.9), // Periodo
        1: pw.FlexColumnWidth(1.0), // Fecha
        2: pw.FlexColumnWidth(1.3), // Saldo Inicio
        3: pw.FlexColumnWidth(0.6), // Tasa
        4: pw.FlexColumnWidth(1.1), // Interés
        5: pw.FlexColumnWidth(1.35), // Amortización
        6: pw.FlexColumnWidth(1.3), // Capitalizado
        7: pw.FlexColumnWidth(1.3), // Saldo Fin
        8: pw.FlexColumnWidth(0.95), // Estado
      },
      children: [
        if (incluirEncabezado)
          pw.TableRow(
            decoration: pw.BoxDecoration(color: _colorEncabezado),
            children: [
              for (var i = 0; i < _columnasCuotas.length; i++)
                _celdaEncabezado(_columnasCuotas[i], alinearDerecha: _clavesNumericas.contains(_clavesCuotas[i])),
            ],
          ),
        for (final cuota in cuotas)
          pw.TableRow(
            children: _clavesCuotas
                .map((clave) => _celda('${cuota[clave] ?? ''}', alinearDerecha: _clavesNumericas.contains(clave)))
                .toList(),
          ),
      ],
    );
  }

  static pw.Widget _filaMovimiento(Map<String, dynamic> mov) {
    final esInyeccion = mov['esInyeccion'] as bool? ?? true;
    return pw.Container(
      width: double.infinity,
      decoration: pw.BoxDecoration(
        color: esInyeccion ? PdfColors.green50 : PdfColors.red50,
        border: pw.Border.all(color: PdfColors.grey400, width: 0.5),
      ),
      padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 5),
      child: pw.Text(
        '${esInyeccion ? '(+)' : '(-)'} ${mov['tipo']} de capital: ${mov['monto']}  ·  ${mov['fecha']}  '
        '(aplica a partir de esta cuota)',
        style: pw.TextStyle(
          fontSize: 8,
          fontWeight: pw.FontWeight.bold,
          color: esInyeccion ? PdfColors.green900 : PdfColors.red900,
        ),
      ),
    );
  }

  static pw.Widget _filaCambioTasa(String? nuevaTasaInteres) {
    return pw.Container(
      width: double.infinity,
      decoration: pw.BoxDecoration(
        color: PdfColors.blue50,
        border: pw.Border.all(color: PdfColors.grey400, width: 0.5),
      ),
      padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 5),
      child: pw.Text(
        'Cambio de tasa: nueva tasa $nuevaTasaInteres (aplica a partir de esta cuota)',
        style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold, color: PdfColors.blue900),
      ),
    );
  }

  static pw.Widget _celdaEncabezado(String texto, {bool alinearDerecha = false}) {
    return pw.Container(
      padding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 6),
      alignment: alinearDerecha ? pw.Alignment.centerRight : pw.Alignment.centerLeft,
      child: pw.Text(
        texto.toUpperCase(),
        // Si el título ocupa dos líneas, cada línea también va a la derecha.
        textAlign: alinearDerecha ? pw.TextAlign.right : pw.TextAlign.left,
        style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold, color: PdfColors.white),
      ),
    );
  }

  static pw.Widget _celda(String texto, {bool alinearDerecha = false}) {
    return pw.Container(
      padding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 4),
      alignment: alinearDerecha ? pw.Alignment.centerRight : pw.Alignment.centerLeft,
      child: pw.Text(
        texto,
        textAlign: alinearDerecha ? pw.TextAlign.right : pw.TextAlign.left,
        style: const pw.TextStyle(fontSize: 8),
      ),
    );
  }

  static String _formatFechaHora(DateTime date) {
    String dos(int n) => n.toString().padLeft(2, '0');
    return '${dos(date.day)}/${dos(date.month)}/${date.year} ${dos(date.hour)}:${dos(date.minute)}';
  }
}
