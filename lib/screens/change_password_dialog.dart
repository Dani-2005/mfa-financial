import 'dart:async';

import 'package:flutter/material.dart';

import '../services/auth_service.dart';

/// Muestra el diálogo de "Cambiar mi Contraseña" para el usuario logueado.
void showChangePasswordDialog(BuildContext context) {
  showDialog(
    context: context,
    builder: (dialogContext) => const _ChangePasswordDialog(),
  );
}

class _ChangePasswordDialog extends StatefulWidget {
  const _ChangePasswordDialog();

  @override
  State<_ChangePasswordDialog> createState() => _ChangePasswordDialogState();
}

class _ChangePasswordDialogState extends State<_ChangePasswordDialog> {
  final _formKey = GlobalKey<FormState>();
  final TextEditingController _actualController = TextEditingController();
  final TextEditingController _nuevaController = TextEditingController();
  final TextEditingController _confirmarController = TextEditingController();

  bool _obscureActual = true;
  bool _obscureNueva = true;
  bool _isSaving = false;
  String? _errorMessage;
  Timer? _errorTimer;

  @override
  void dispose() {
    _errorTimer?.cancel();
    _actualController.dispose();
    _nuevaController.dispose();
    _confirmarController.dispose();
    super.dispose();
  }

  void _showError(String message) {
    _errorTimer?.cancel();
    setState(() => _errorMessage = message);
    _errorTimer = Timer(const Duration(seconds: 5), () {
      if (mounted) setState(() => _errorMessage = null);
    });
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    _errorTimer?.cancel();
    setState(() {
      _isSaving = true;
      _errorMessage = null;
    });

    try {
      await AuthService.instance.changePassword(
        actual: _actualController.text,
        nueva: _nuevaController.text,
      );
      if (!mounted) return;
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Contraseña actualizada con éxito')),
      );
    } on ArgumentError catch (e) {
      setState(() => _isSaving = false);
      _showError('${e.message}');
    } catch (_) {
      setState(() => _isSaving = false);
      _showError('No se pudo actualizar la contraseña. Intenta de nuevo.');
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Cambiar mi Contraseña', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
      content: SizedBox(
        width: 420,
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AnimatedSize(
                duration: const Duration(milliseconds: 250),
                curve: Curves.easeInOut,
                alignment: Alignment.topCenter,
                child: _errorMessage == null
                    ? const SizedBox(width: double.infinity)
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          TweenAnimationBuilder<double>(
                            key: ValueKey(_errorMessage),
                            duration: const Duration(milliseconds: 200),
                            tween: Tween(begin: 0, end: 1),
                            builder: (_, opacity, child) => Opacity(opacity: opacity, child: child),
                            child: Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: Colors.red.shade50,
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(color: Colors.red.shade200),
                              ),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Icon(Icons.error_outline, size: 18, color: Colors.red.shade700),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      _errorMessage!,
                                      style: TextStyle(fontSize: 12, color: Colors.red.shade700, fontWeight: FontWeight.w600),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(height: 12),
                        ],
                      ),
              ),
              TextFormField(
                controller: _actualController,
                obscureText: _obscureActual,
                decoration: InputDecoration(
                  labelText: 'Contraseña Actual',
                  prefixIcon: const Icon(Icons.lock_outline, color: Colors.black),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                  suffixIcon: IconButton(
                    icon: Icon(_obscureActual ? Icons.visibility_outlined : Icons.visibility_off_outlined, size: 20),
                    onPressed: () => setState(() => _obscureActual = !_obscureActual),
                  ),
                ),
                validator: (value) => (value == null || value.isEmpty) ? 'Ingresa tu contraseña actual' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _nuevaController,
                obscureText: _obscureNueva,
                decoration: InputDecoration(
                  labelText: 'Nueva Contraseña',
                  prefixIcon: const Icon(Icons.lock_reset, color: Colors.black),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                  helperText: 'Mínimo 8 caracteres, combinando letras y números.',
                  helperMaxLines: 2,
                  suffixIcon: IconButton(
                    icon: Icon(_obscureNueva ? Icons.visibility_outlined : Icons.visibility_off_outlined, size: 20),
                    onPressed: () => setState(() => _obscureNueva = !_obscureNueva),
                  ),
                ),
                validator: (value) {
                  if (value == null || value.isEmpty) return 'Ingresa la nueva contraseña';
                  if (value.length < 8) return 'Debe tener al menos 8 caracteres';
                  if (!RegExp(r'[A-Za-z]').hasMatch(value) || !RegExp(r'[0-9]').hasMatch(value)) {
                    return 'Debe combinar letras y números';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _confirmarController,
                obscureText: _obscureNueva,
                decoration: InputDecoration(
                  labelText: 'Confirmar Nueva Contraseña',
                  prefixIcon: const Icon(Icons.check_circle_outline, color: Colors.black),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                ),
                validator: (value) => value != _nuevaController.text ? 'Las contraseñas no coinciden' : null,
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isSaving ? null : () => Navigator.pop(context),
          child: Text('Cancelar', style: TextStyle(color: Colors.grey.shade800)),
        ),
        ElevatedButton(
          style: ElevatedButton.styleFrom(backgroundColor: Colors.black),
          onPressed: _isSaving ? null : _submit,
          child: _isSaving
              ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : const Text('Guardar', style: TextStyle(color: Colors.white)),
        ),
      ],
    );
  }
}
