import 'package:local_auth/local_auth.dart';

/// Envoltorio delgado sobre `local_auth`: usa Windows Hello en Windows,
/// Touch ID en macOS, Face ID/Touch ID en iOS, y huella/rostro (vía
/// BiometricPrompt) en Android — una sola API para las cuatro plataformas.
///
/// Esto solo confirma "el dueño del dispositivo está presente ahora"; no
/// crea ni valida por sí solo ninguna sesión. Quien lo use decide qué
/// hacer con ese resultado (ver `AuthService.renovarSesionConBiometria`).
class BiometricService {
  BiometricService._();
  static final BiometricService instance = BiometricService._();

  final LocalAuthentication _auth = LocalAuthentication();

  /// true si el dispositivo tiene hardware biométrico enrolado y disponible.
  Future<bool> isAvailable() async {
    try {
      final soportado = await _auth.isDeviceSupported();
      final puedeVerificar = await _auth.canCheckBiometrics;
      return soportado && puedeVerificar;
    } catch (_) {
      return false;
    }
  }

  /// true si el tipo de biometría principal enrolada en este dispositivo es
  /// reconocimiento facial (Face ID en iOS, o rostro vía BiometricPrompt en
  /// Android); false si es huella digital (o no se pudo determinar, que es
  /// el caso más común y seguro por defecto).
  Future<bool> esFaceId() async {
    try {
      final tipos = await _auth.getAvailableBiometrics();
      return tipos.contains(BiometricType.face);
    } catch (_) {
      return false;
    }
  }

  /// Pide la verificación biométrica con [reason] como mensaje al usuario.
  /// Devuelve true solo si el sistema operativo confirmó la identidad; en
  /// cualquier error (sensor no disponible, cancelado, excepción de
  /// plataforma) devuelve false en vez de propagar la excepción, para que
  /// quien lo llame simplemente pueda caer de vuelta al login normal.
  Future<bool> authenticate(String reason) async {
    try {
      return await _auth.authenticate(
        localizedReason: reason,
        biometricOnly: false,
      );
    } catch (_) {
      return false;
    }
  }
}
