import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:printing/printing.dart';

/// Diálogo "¿Qué acción desea realizar con este PDF?" con Imprimir/Descargar,
/// reutilizado por los recibos de pago y los reportes de Auditoría. Genera
/// el PDF de forma perezosa (solo cuando el usuario elige una acción) para
/// no bloquear la apertura del diálogo mientras arma el documento.
Future<void> showPdfActionsDialog(
  BuildContext context, {
  required String titulo,
  required Widget infoContent,
  required Future<Uint8List> Function() generarPdf,
  required String nombreArchivo,
}) {
  return showDialog(
    context: context,
    builder: (context) {
      final bool isMobile = MediaQuery.sizeOf(context).width < 500;
      bool isProcessing = false;

      return StatefulBuilder(
        builder: (context, setModalState) {
          Future<void> imprimir() async {
            setModalState(() => isProcessing = true);
            try {
              final bytes = await generarPdf();
              await Printing.layoutPdf(onLayout: (_) async => bytes);
              if (!context.mounted) return;
              Navigator.pop(context);
            } catch (_) {
              setModalState(() => isProcessing = false);
              if (!context.mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('No se pudo generar el PDF. Intenta de nuevo.')),
              );
            }
          }

          Future<void> guardar() async {
            setModalState(() => isProcessing = true);
            try {
              final bytes = await generarPdf();
              final ruta = await FilePicker.saveFile(
                dialogTitle: 'Guardar PDF',
                fileName: nombreArchivo,
                bytes: bytes,
                mimeType: 'application/pdf',
                type: FileType.custom,
                allowedExtensions: const ['pdf'],
              );
              if (ruta == null) {
                // El usuario canceló el diálogo de guardado.
                setModalState(() => isProcessing = false);
                return;
              }
              if (!context.mounted) return;
              Navigator.pop(context);
            } catch (_) {
              setModalState(() => isProcessing = false);
              if (!context.mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('No se pudo guardar el PDF. Intenta de nuevo.')),
              );
            }
          }

          final cancelBtn = TextButton(
            onPressed: isProcessing ? null : () => Navigator.pop(context),
            child: Text('Cancelar', style: TextStyle(color: Colors.grey.shade800)),
          );

          final printBtn = OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
              foregroundColor: Colors.black,
              padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            icon: const Icon(Icons.print, size: 16),
            label: const Text('Imprimir'),
            onPressed: isProcessing ? null : imprimir,
          );

          final downloadBtn = ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.black,
              padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            icon: isProcessing
                ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Icon(Icons.download, size: 16, color: Colors.white),
            label: const Text('Descargar PDF', style: TextStyle(color: Colors.white)),
            onPressed: isProcessing ? null : guardar,
          );

          return AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            title: Row(
              children: [
                const Icon(Icons.picture_as_pdf, color: Colors.redAccent),
                const SizedBox(width: 8),
                Expanded(child: Text(titulo, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15))),
              ],
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                infoContent,
                const SizedBox(height: 16),
                const Text('¿Qué acción desea realizar con este PDF?', style: TextStyle(fontSize: 12)),
              ],
            ),
            actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            actions: [
              isMobile
                  ? Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        downloadBtn,
                        const SizedBox(height: 10),
                        printBtn,
                        const SizedBox(height: 4),
                        Center(child: cancelBtn),
                      ],
                    )
                  : Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        cancelBtn,
                        const SizedBox(width: 8),
                        printBtn,
                        const SizedBox(width: 8),
                        downloadBtn,
                      ],
                    ),
            ],
          );
        },
      );
    },
  );
}
