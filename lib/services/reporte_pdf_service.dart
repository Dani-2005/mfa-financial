import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

/// Genera el PDF de los reportes personalizados de Auditoría: mismo
/// encabezado del emisor y el mismo estilo de tabla (header navy) que ya
/// usan los recibos de pago, pero en formato tabular con los campos que el
/// usuario haya seleccionado.
class ReportePdfService {
  static const _emisorNombre = 'Miguel A. Flores';
  static const _emisorDireccion = '8953 E Captian Dreyfus Ave Scottsdale, AZ 85260';
  static const _emisorCorreo = 'michelfloresl@hotmail.com';

  static final _colorEncabezado = PdfColor.fromHex('#1F3864');

  static Future<Uint8List> generar({
    required String modulo,
    required List<String> columnas,
    required List<Map<String, dynamic>> filas,
    String? filtroCliente,
    String? filtroTipoAccion,
    String? filtroRangoFechas,
  }) async {
    final doc = pw.Document();
    final fechaGeneracion = _formatFechaHora(DateTime.now());

    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.letter.landscape,
        margin: const pw.EdgeInsets.all(28),
        header: (context) => context.pageNumber == 1
            ? pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  _buildEncabezado(modulo, fechaGeneracion, filtroCliente, filtroTipoAccion, filtroRangoFechas),
                  pw.SizedBox(height: 14),
                ],
              )
            : pw.SizedBox(),
        build: (context) => [
          _buildTabla(columnas, filas),
          pw.SizedBox(height: 10),
          pw.Align(
            alignment: pw.Alignment.centerRight,
            child: pw.Text(
              'Total de registros: ${filas.length}',
              style: pw.TextStyle(fontSize: 9, fontStyle: pw.FontStyle.italic, color: PdfColors.grey700),
            ),
          ),
        ],
      ),
    );

    return doc.save();
  }

  static pw.Widget _buildEncabezado(
    String modulo,
    String fechaGeneracion,
    String? filtroCliente,
    String? filtroTipoAccion,
    String? filtroRangoFechas,
  ) {
    return pw.Row(
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
            pw.Text('Reporte de $modulo', style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold)),
            pw.SizedBox(height: 4),
            pw.Text('Generado: $fechaGeneracion', style: const pw.TextStyle(fontSize: 9)),
            if (filtroCliente != null) ...[
              pw.SizedBox(height: 2),
              pw.Text('Cliente: $filtroCliente', style: const pw.TextStyle(fontSize: 9)),
            ],
            if (filtroTipoAccion != null) ...[
              pw.SizedBox(height: 2),
              pw.Text('Tipo de Evento: $filtroTipoAccion', style: const pw.TextStyle(fontSize: 9)),
            ],
            if (filtroRangoFechas != null) ...[
              pw.SizedBox(height: 2),
              pw.Text(filtroRangoFechas, style: const pw.TextStyle(fontSize: 9)),
            ],
          ],
        ),
      ],
    );
  }

  static pw.Widget _buildTabla(List<String> columnas, List<Map<String, dynamic>> filas) {
    return pw.Table(
      border: pw.TableBorder.all(color: PdfColors.grey400, width: 0.5),
      columnWidths: {for (int i = 0; i < columnas.length; i++) i: const pw.FlexColumnWidth(1)},
      children: [
        pw.TableRow(
          decoration: pw.BoxDecoration(color: _colorEncabezado),
          children: columnas.map(_celdaEncabezado).toList(),
        ),
        for (final fila in filas)
          pw.TableRow(
            children: columnas.map((col) => _celda('${fila[col] ?? ''}')).toList(),
          ),
      ],
    );
  }

  static pw.Widget _celdaEncabezado(String texto) {
    return pw.Container(
      padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 6),
      child: pw.Text(
        texto.toUpperCase(),
        style: pw.TextStyle(fontSize: 8.5, fontWeight: pw.FontWeight.bold, color: PdfColors.white),
      ),
    );
  }

  static pw.Widget _celda(String texto) {
    return pw.Container(
      padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 4),
      child: pw.Text(texto, style: const pw.TextStyle(fontSize: 8.5)),
    );
  }

  static String _formatFechaHora(DateTime date) {
    String dos(int n) => n.toString().padLeft(2, '0');
    return '${dos(date.day)}/${dos(date.month)}/${date.year} ${dos(date.hour)}:${dos(date.minute)}';
  }
}
