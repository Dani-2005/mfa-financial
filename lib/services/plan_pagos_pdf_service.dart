import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

/// Genera el PDF del "Plan de Pagos" de un préstamo puntual: encabezado con
/// los datos del préstamo (código, cliente, tipo de tasa/cálculo,
/// frecuencia, fecha, tasa de interés, si tiene cambio de tasa programado o
/// es una operación por fases), la tabla de cuotas completa, y los
/// movimientos de capital (inyecciones/retiros) si los hay.
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
          pw.SizedBox(height: 6),
          _buildTablaCuotas(cuotas),
          if (cuotas.any((c) => c['capitalizado'] == 'Sí')) ...[
            pw.SizedBox(height: 6),
            pw.Text(
              '* Las cuotas con Capitalizado = "Sí" salen como "Pagado" aunque el cliente no las pagó: '
              'el interés se reinvierte automáticamente en el saldo en vez de cobrarse.',
              style: pw.TextStyle(fontSize: 8, fontStyle: pw.FontStyle.italic, color: PdfColors.grey700),
            ),
          ],
          if (movimientos.isNotEmpty) ...[
            pw.SizedBox(height: 18),
            pw.Text(
              'Movimientos de Capital',
              style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold, color: _colorEncabezado),
            ),
            pw.SizedBox(height: 6),
            _buildTablaMovimientos(movimientos),
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

  static pw.Widget _buildTablaCuotas(List<Map<String, dynamic>> cuotas) {
    return pw.Table(
      border: pw.TableBorder.all(color: PdfColors.grey400, width: 0.5),
      columnWidths: {for (int i = 0; i < _columnasCuotas.length; i++) i: const pw.FlexColumnWidth(1)},
      children: [
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

  static const _columnasMovimientos = ['Tipo', 'Periodo', 'Monto', 'Fecha'];
  static const _clavesMovimientos = ['tipo', 'periodo', 'monto', 'fecha'];

  static pw.Widget _buildTablaMovimientos(List<Map<String, dynamic>> movimientos) {
    return pw.Table(
      border: pw.TableBorder.all(color: PdfColors.grey400, width: 0.5),
      columnWidths: {for (int i = 0; i < _columnasMovimientos.length; i++) i: const pw.FlexColumnWidth(1)},
      children: [
        pw.TableRow(
          decoration: pw.BoxDecoration(color: _colorEncabezado),
          children: _columnasMovimientos.map(_celdaEncabezado).toList(),
        ),
        for (final mov in movimientos)
          pw.TableRow(
            children: _clavesMovimientos.map((clave) => _celda('${mov[clave] ?? ''}')).toList(),
          ),
      ],
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
