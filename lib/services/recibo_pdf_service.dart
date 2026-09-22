import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

/// Genera el PDF del recibo de pago con el mismo formato que ya usa el
/// negocio en papel: encabezado fijo del emisor, tabla de cliente/préstamo,
/// tabla de detalle del cobro y balance pendiente.
class ReciboPdfService {
  // Datos del emisor: son siempre los mismos en todos los recibos.
  static const _emisorNombre = 'Miguel A. Flores';
  static const _emisorDireccion = '8953 E Captian Dreyfus Ave Scottsdale, AZ 85260';
  static const _emisorCorreo = 'michelfloresl@hotmail.com';

  static final _colorEncabezado = PdfColor.fromHex('#1F3864');

  static Future<Uint8List> generar(Map<String, dynamic> detalle) async {
    final doc = pw.Document();
    final lineas = (detalle['lineas'] as List).cast<Map<String, dynamic>>();

    doc.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.letter,
        margin: const pw.EdgeInsets.all(28),
        build: (context) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              _buildEncabezado(detalle),
              pw.SizedBox(height: 16),
              _buildTablaCliente(detalle),
              pw.SizedBox(height: 14),
              _buildTablaDetalle(lineas),
              _buildBalancePendiente(detalle['balance_pendiente'] as double),
            ],
          );
        },
      ),
    );

    return doc.save();
  }

  static pw.Widget _buildEncabezado(Map<String, dynamic> detalle) {
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
            pw.Text(detalle['fecha_emision'] as String, style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold)),
            pw.SizedBox(height: 4),
            pw.Text('RECIBO ${detalle['codigo_recibo']}', style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold)),
          ],
        ),
      ],
    );
  }

  static pw.Widget _buildTablaCliente(Map<String, dynamic> detalle) {
    return pw.Table(
      border: pw.TableBorder.all(color: PdfColors.grey400, width: 0.5),
      columnWidths: const {0: pw.FlexColumnWidth(2), 1: pw.FlexColumnWidth(1.4), 2: pw.FlexColumnWidth(2)},
      children: [
        pw.TableRow(
          decoration: pw.BoxDecoration(color: _colorEncabezado),
          children: [
            _celdaEncabezado('CLIENTE'),
            _celdaEncabezado('DOC. DE IDENTIDAD'),
            _celdaEncabezado('DIRECCION'),
          ],
        ),
        pw.TableRow(
          children: [
            _celda(detalle['cliente_nombre'] as String, negrita: true),
            _celda(detalle['cliente_documento'] as String, negrita: true, centrado: true),
            _celda(detalle['cliente_direccion'] as String, negrita: true),
          ],
        ),
      ],
    );
  }

  static pw.Widget _buildTablaDetalle(List<Map<String, dynamic>> lineas) {
    return pw.Table(
      border: pw.TableBorder.all(color: PdfColors.grey400, width: 0.5),
      columnWidths: const {
        0: pw.FlexColumnWidth(1.3),
        1: pw.FlexColumnWidth(3.2),
        2: pw.FlexColumnWidth(0.7),
        3: pw.FlexColumnWidth(1.6),
      },
      children: [
        pw.TableRow(
          decoration: pw.BoxDecoration(color: _colorEncabezado),
          children: [
            _celdaEncabezado('FECHA'),
            _celdaEncabezado('DESCRIPCION'),
            _celdaEncabezado('CNT', centrado: true),
            _celdaEncabezado('PRECIO UNITARIO', alinearDerecha: true),
          ],
        ),
        for (final linea in lineas)
          pw.TableRow(
            children: [
              _celda((linea['fecha'] as String?) ?? ''),
              _celda(linea['descripcion'] as String),
              _celda('${linea['cantidad']}', centrado: true),
              _celda(_formatMoneda(linea['precio'] as double), alinearDerecha: true),
            ],
          ),
      ],
    );
  }

  static pw.Widget _buildBalancePendiente(double balance) {
    return pw.Table(
      border: pw.TableBorder.all(color: PdfColors.grey400, width: 0.5),
      columnWidths: const {0: pw.FlexColumnWidth(7), 1: pw.FlexColumnWidth(1.6)},
      children: [
        pw.TableRow(
          children: [
            pw.Container(
              alignment: pw.Alignment.centerRight,
              padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 5),
              decoration: pw.BoxDecoration(color: _colorEncabezado),
              child: pw.Text(
                'BALANCE PENDIENTE',
                style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold, fontStyle: pw.FontStyle.italic, color: PdfColors.white),
              ),
            ),
            pw.Container(
              alignment: pw.Alignment.centerRight,
              padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 5),
              decoration: pw.BoxDecoration(color: _colorEncabezado),
              child: pw.Text(
                _formatMoneda(balance),
                style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold, fontStyle: pw.FontStyle.italic, color: PdfColors.white),
              ),
            ),
          ],
        ),
      ],
    );
  }

  static pw.Widget _celdaEncabezado(String texto, {bool centrado = false, bool alinearDerecha = false}) {
    return pw.Container(
      padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 6),
      alignment: alinearDerecha
          ? pw.Alignment.centerRight
          : centrado
              ? pw.Alignment.center
              : pw.Alignment.centerLeft,
      child: pw.Text(
        texto,
        style: pw.TextStyle(fontSize: 9.5, fontWeight: pw.FontWeight.bold, color: PdfColors.white),
      ),
    );
  }

  static pw.Widget _celda(String texto, {bool negrita = false, bool centrado = false, bool alinearDerecha = false}) {
    return pw.Container(
      padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 5),
      alignment: alinearDerecha
          ? pw.Alignment.centerRight
          : centrado
              ? pw.Alignment.center
              : pw.Alignment.centerLeft,
      child: pw.Text(
        texto,
        style: pw.TextStyle(fontSize: 9.5, fontWeight: negrita ? pw.FontWeight.bold : pw.FontWeight.normal),
      ),
    );
  }

  /// Formato "$ 400.000,00": punto como separador de miles, coma como
  /// decimal — igual convención que ya usa el negocio en sus recibos.
  static String _formatMoneda(double valor) {
    final esNegativo = valor < 0;
    final fijo = valor.abs().toStringAsFixed(2);
    final partes = fijo.split('.');
    final parteEntera = partes[0];
    final buffer = StringBuffer();
    for (int i = 0; i < parteEntera.length; i++) {
      if (i > 0 && (parteEntera.length - i) % 3 == 0) buffer.write('.');
      buffer.write(parteEntera[i]);
    }
    return '${esNegativo ? '-' : ''}\$ ${buffer.toString()},${partes[1]}';
  }
}
