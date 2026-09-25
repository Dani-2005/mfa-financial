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
              'el interés se reinvierte automáticamente en el saldo en vez de cobrarse.',
              style: pw.TextStyle(fontSize: 8, fontStyle: pw.FontStyle.italic, color: PdfColors.grey700),
            ),
          ],
        ],
      ),
    );

    return doc.save();
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
      columnWidths: {for (int i = 0; i < _columnasCuotas.length; i++) i: const pw.FlexColumnWidth(1)},
      children: [
        if (incluirEncabezado)
          pw.TableRow(
            decoration: pw.BoxDecoration(color: _colorEncabezado),
            children: _columnasCuotas.map(_celdaEncabezado).toList(),
          ),
        for (final cuota in cuotas)
          pw.TableRow(
            children: _clavesCuotas.map((clave) => _celda('${cuota[clave] ?? ''}')).toList(),
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

  static pw.Widget _celdaEncabezado(String texto) {
    return pw.Container(
      padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 6),
      child: pw.Text(
        texto.toUpperCase(),
        style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold, color: PdfColors.white),
      ),
    );
  }

  static pw.Widget _celda(String texto) {
    return pw.Container(
      padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 4),
      child: pw.Text(texto, style: const pw.TextStyle(fontSize: 8)),
    );
  }

  static String _formatFechaHora(DateTime date) {
    String dos(int n) => n.toString().padLeft(2, '0');
    return '${dos(date.day)}/${dos(date.month)}/${date.year} ${dos(date.hour)}:${dos(date.minute)}';
  }
}
