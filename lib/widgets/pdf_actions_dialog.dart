import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:pdf/pdf.dart';
import 'package:printing/printing.dart';
import 'package:share_plus/share_plus.dart';

import '../services/api_client.dart';

/// Abre una pantalla de vista previa del PDF (imprimir/compartir ya
/// integrados en el propio visor, más un botón de guardar), reutilizada por
/// los recibos de pago, el plan de pagos y los reportes de Auditoría.
/// [generarPdf] se llama una sola vez, la primera vez que el visor pide las
/// páginas; el resultado se reutiliza tanto para el visor como para el
/// botón de guardar, sin volver a generar el documento.
Future<void> showPdfActionsDialog(
  BuildContext context, {
  required String titulo,
  required Widget infoContent,
  required Future<Uint8List> Function() generarPdf,
  required String nombreArchivo,
}) {
  return Navigator.of(context).push(
    MaterialPageRoute(
      fullscreenDialog: true,
      builder: (context) => _PdfPreviewScreen(
        titulo: titulo,
        infoContent: infoContent,
        generarPdf: generarPdf,
        nombreArchivo: nombreArchivo,
      ),
    ),
  );
}

class _PdfPreviewScreen extends StatefulWidget {
  final String titulo;
  final Widget infoContent;
  final Future<Uint8List> Function() generarPdf;
  final String nombreArchivo;

  const _PdfPreviewScreen({
    required this.titulo,
    required this.infoContent,
    required this.generarPdf,
    required this.nombreArchivo,
  });

  @override
  State<_PdfPreviewScreen> createState() => _PdfPreviewScreenState();
}

class _PdfPreviewScreenState extends State<_PdfPreviewScreen> {
  // Se guarda lo último que generó el visor para que "Guardar" no tenga que
  // volver a pedirle el documento al servidor.
  Uint8List? _ultimoGenerado;
  bool _isSaving = false;
  bool _isSharing = false;

  Future<Uint8List> _build(PdfPageFormat format) async {
    final bytes = await widget.generarPdf();
    _ultimoGenerado = bytes;
    return bytes;
  }

  Future<void> _guardar() async {
    final bytes = _ultimoGenerado;
    if (bytes == null || _isSaving) return;

    setState(() => _isSaving = true);
    try {
      final ruta = await FilePicker.saveFile(
        dialogTitle: 'Guardar PDF',
        fileName: widget.nombreArchivo,
        bytes: bytes,
        mimeType: 'application/pdf',
        type: FileType.custom,
        allowedExtensions: const ['pdf'],
      );
      if (!mounted) return;
      if (ruta != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('PDF guardado correctamente.')),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e is NoConnectionException ? e.message : 'No se pudo guardar el PDF. Intenta de nuevo.'),
        ),
      );
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  /// El botón "Compartir" propio del visor (`allowSharing`) usa, en
  /// Windows, un `ShellExecute` que simplemente abre el PDF con el programa
  /// predeterminado (el navegador) — no el panel nativo de "Compartir" de
  /// Windows. Por eso aquí se desactiva ese botón y se usa `share_plus` en
  /// su lugar, que en Windows sí invoca ese panel nativo (con WhatsApp,
  /// correo, Compartir cerca, etc.). Necesita un archivo real en disco (no
  /// basta con los bytes en memoria), así que se escribe primero a un
  /// archivo temporal.
  Future<void> _compartir() async {
    final bytes = _ultimoGenerado;
    if (bytes == null || _isSharing) return;

    setState(() => _isSharing = true);
    try {
      final archivoTemporal = File('${Directory.systemTemp.path}/${widget.nombreArchivo}');
      await archivoTemporal.writeAsBytes(bytes);
      await SharePlus.instance.share(
        ShareParams(files: [XFile(archivoTemporal.path)], subject: widget.titulo),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e is NoConnectionException ? e.message : 'No se pudo compartir el PDF. Intenta de nuevo.'),
        ),
      );
    } finally {
      if (mounted) setState(() => _isSharing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      appBar: AppBar(
        backgroundColor: Colors.black,
        elevation: 0,
        title: Text(
          widget.titulo,
          style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold),
          overflow: TextOverflow.ellipsis,
        ),
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          // En Windows, el panel nativo de compartir (DataTransferManager)
          // falla seguido con "No se pudieron mostrar todas las maneras de
          // compartir contenido" porque esa API está pensada para apps
          // empaquetadas (MSIX/Store), y esta se distribuye como un .exe
          // normal. En el resto de las plataformas sí funciona bien.
          if (!Platform.isWindows)
            IconButton(
              tooltip: 'Compartir',
              icon: _isSharing
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    )
                  : const Icon(Icons.share),
              onPressed: _isSharing ? null : _compartir,
            ),
          IconButton(
            tooltip: 'Guardar PDF',
            icon: _isSaving
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                  )
                : const Icon(Icons.download),
            onPressed: _isSaving ? null : _guardar,
          ),
        ],
      ),
      body: Column(
        children: [
          Container(
            width: double.infinity,
            color: Colors.white,
            padding: const EdgeInsets.all(16),
            child: widget.infoContent,
          ),
          const Divider(height: 1),
          Expanded(
            child: PdfPreview(
              build: _build,
              pdfFileName: widget.nombreArchivo,
              canChangePageFormat: false,
              canChangeOrientation: false,
              canDebug: false,
              // El de compartir propio del visor queda apagado: en Windows
              // no abre el panel nativo de compartir (ver _compartir, que se
              // ofrece en la barra superior en su lugar). "Guardar" también
              // se ofrece ahí arriba, junto a "Compartir".
              allowSharing: false,
              loadingWidget: const Center(child: CircularProgressIndicator(color: Colors.black)),
              onError: (context, error) => Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(
                    error is NoConnectionException ? error.message : 'No se pudo generar el PDF. Intenta de nuevo.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.grey.shade800),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
