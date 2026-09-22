import 'package:flutter/material.dart';

/// Una opción seleccionable de [CustomDropdown].
class CustomDropdownItem<T> {
  final T value;
  final String label;
  final IconData? icon;

  const CustomDropdownItem({required this.value, required this.label, this.icon});
}

/// Dropdown con menú propio (no usa el `DropdownButton` de Material):
/// se posiciona con [CompositedTransformTarget]/[CompositedTransformFollower]
/// vía un [LayerLink], se pinta en un [OverlayEntry] con una animación de
/// escala/opacidad de 300ms, y se cierra tocando un scrim negro que se
/// desvanece detrás del menú.
class CustomDropdown<T> extends FormField<T> {
  CustomDropdown({
    super.key,
    required List<CustomDropdownItem<T>> items,
    super.initialValue,
    required InputDecoration decoration,
    ValueChanged<T?>? onChanged,
    super.validator,
    super.enabled,
  }) : super(
          builder: (field) {
            return _CustomDropdownField<T>(
              items: items,
              value: field.value,
              decoration: decoration.copyWith(errorText: field.errorText),
              enabled: enabled,
              onChanged: enabled
                  ? (value) {
                      field.didChange(value);
                      onChanged?.call(value);
                    }
                  : null,
            );
          },
        );
}

class _CustomDropdownField<T> extends StatefulWidget {
  final List<CustomDropdownItem<T>> items;
  final T? value;
  final InputDecoration decoration;
  final bool enabled;
  final ValueChanged<T?>? onChanged;

  const _CustomDropdownField({
    super.key,
    required this.items,
    required this.value,
    required this.decoration,
    required this.enabled,
    required this.onChanged,
  });

  @override
  State<_CustomDropdownField<T>> createState() => _CustomDropdownFieldState<T>();
}

class _CustomDropdownFieldState<T> extends State<_CustomDropdownField<T>> with SingleTickerProviderStateMixin {
  final LayerLink _layerLink = LayerLink();
  final GlobalKey _fieldKey = GlobalKey();
  OverlayEntry? _scrimEntry;
  OverlayEntry? _menuEntry;
  late final AnimationController _animController;
  late final Animation<double> _scaleAnim;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(vsync: this, duration: const Duration(milliseconds: 300));
    _scaleAnim = CurvedAnimation(parent: _animController, curve: Curves.easeOutCubic).drive(Tween(begin: 0.92, end: 1.0));
  }

  @override
  void dispose() {
    _removeOverlayEntries();
    _animController.dispose();
    super.dispose();
  }

  void _toggleMenu() {
    if (!widget.enabled) return;
    if (_menuEntry != null) {
      _closeMenu();
    } else {
      _openMenu();
    }
  }

  void _openMenu() {
    final overlay = Overlay.of(context);
    final renderBox = _fieldKey.currentContext!.findRenderObject() as RenderBox;
    final fieldSize = renderBox.size;
    const menuOffset = 6.0;
    const bottomMargin = 16.0;

    // El menú se abre hacia abajo del campo; su alto máximo se ajusta al
    // espacio real disponible hasta el borde inferior de la pantalla (sin
    // contar la franja de los botones/gestos del sistema), sin ningún
    // mínimo forzado — si el espacio es poco, el menú simplemente sale más
    // chico y se ven las demás opciones haciendo scroll dentro de él.
    final fieldTopLeft = renderBox.localToGlobal(Offset.zero);
    final screenHeight = MediaQuery.sizeOf(context).height;
    // Ojo: dentro del `body` de un Scaffold con bottomNavigationBar (como el
    // de esta app en móvil), Flutter pone en 0 el padding inferior del
    // MediaQuery que ve ese body, porque asume que la barra ya lo absorbe.
    // Por eso se lee desde el contexto del Overlay (que vive por encima del
    // Scaffold, insertado por el Navigator) y no desde el del campo — así sí
    // se obtiene la altura real de los botones/gestos del sistema.
    final safeBottomInset = MediaQuery.paddingOf(overlay.context).bottom;
    final spaceBelow = screenHeight - fieldTopLeft.dy - fieldSize.height - menuOffset - bottomMargin - safeBottomInset;
    final menuMaxHeight = spaceBelow.clamp(0.0, 280.0);

    _scrimEntry = OverlayEntry(
      builder: (_) => GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _closeMenu,
        child: AnimatedBuilder(
          animation: _animController,
          builder: (_, child) => Container(color: Colors.black.withValues(alpha: 0.6 * _animController.value)),
        ),
      ),
    );

    _menuEntry = OverlayEntry(
      builder: (_) => Positioned(
        width: fieldSize.width,
        child: CompositedTransformFollower(
          link: _layerLink,
          showWhenUnlinked: false,
          offset: Offset(0, fieldSize.height + menuOffset),
          child: Align(
            alignment: Alignment.topLeft,
            child: AnimatedBuilder(
              animation: _animController,
              builder: (_, child) => Opacity(
                opacity: _animController.value,
                child: Transform.scale(
                  scale: _scaleAnim.value,
                  alignment: Alignment.topCenter,
                  child: child,
                ),
              ),
              child: Material(
                color: Colors.transparent,
                child: Container(
                  constraints: BoxConstraints(maxHeight: menuMaxHeight),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.black.withValues(alpha: 0)),
                    boxShadow: [
                      BoxShadow(color: Colors.black.withValues(alpha: 0.15), blurRadius: 20, offset: const Offset(0, 8)),
                    ],
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: widget.items.map((item) {
                          final selected = item.value == widget.value;
                          return InkWell(
                            onTap: () {
                              widget.onChanged?.call(item.value);
                              _closeMenu();
                            },
                            child: Container(
                              width: double.infinity,
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                              color: selected ? Colors.grey.shade100 : Colors.transparent,
                              child: Row(
                                children: [
                                  if (item.icon != null) ...[
                                    Icon(item.icon, size: 18, color: Colors.black87),
                                    const SizedBox(width: 10),
                                  ],
                                  Expanded(
                                    child: Text(
                                      item.label,
                                      maxLines: 1,
                                      style: TextStyle(
                                        fontSize: 13,
                                        color: Colors.black87,
                                        fontWeight: selected ? FontWeight.bold : FontWeight.normal,
                                      ),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  if (selected) const Icon(Icons.check, size: 16, color: Colors.black),
                                ],
                              ),
                            ),
                          );
                        }).toList(),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );

    overlay.insert(_scrimEntry!);
    overlay.insert(_menuEntry!);
    _animController.forward(from: 0);
    setState(() {});
  }

  Future<void> _closeMenu() async {
    await _animController.reverse();
    _removeOverlayEntries();
    if (mounted) setState(() {});
  }

  void _removeOverlayEntries() {
    _scrimEntry?.remove();
    _menuEntry?.remove();
    _scrimEntry = null;
    _menuEntry = null;
  }

  @override
  Widget build(BuildContext context) {
    final matches = widget.items.where((i) => i.value == widget.value);
    final label = matches.isEmpty ? null : matches.first.label;
    final selectedIcon = matches.isEmpty ? null : matches.first.icon;

    return CompositedTransformTarget(
      link: _layerLink,
      child: InkWell(
        key: _fieldKey,
        borderRadius: BorderRadius.circular(12),
        onTap: _toggleMenu,
        child: InputDecorator(
          decoration: widget.decoration,
          isEmpty: label == null,
          child: Row(
            children: [
              if (selectedIcon != null) ...[
                Icon(selectedIcon, size: 16, color: Colors.black87),
                const SizedBox(width: 8),
              ],
              Expanded(
                child: Text(
                  label ?? '',
                  maxLines: 1,
                  style: TextStyle(fontSize: 13, color: widget.enabled ? Colors.black87 : Colors.grey.shade600),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              AnimatedRotation(
                turns: _menuEntry != null ? 0.5 : 0,
                duration: const Duration(milliseconds: 300),
                child: Icon(
                  Icons.keyboard_arrow_down,
                  color: widget.enabled ? Colors.grey.shade800 : Colors.grey.shade500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
