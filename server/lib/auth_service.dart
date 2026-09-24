import 'dart:convert';
import 'dart:math';

import 'package:bcrypt/bcrypt.dart';
import 'package:crypto/crypto.dart';

import 'auditoria_service.dart';
import 'database_service.dart';
import 'models.dart';

const String mensajeCredencialesInvalidas = 'Usuario o contraseña incorrectos.';

class LoginResult {
  final AuthUser user;
  final String token;
  final DateTime expiraEn;
  const LoginResult({required this.user, required this.token, required this.expiraEn});
}

/// Resultado de renovar sesión por biometría: además de la sesión nueva,
/// incluye el token de "recordar" rotado — el cliente DEBE guardarlo,
/// reemplazando el anterior, o el desbloqueo biométrico dejará de
/// funcionar después de este mismo uso (el hash anterior ya no es válido).
class RenovarBiometriaResult {
  final LoginResult sesion;
  final String nuevoRecordarToken;
  const RenovarBiometriaResult({required this.sesion, required this.nuevoRecordarToken});
}

/// Puerto al servidor de `lib/services/auth_service.dart` de la app. La
/// lógica de negocio (bcrypt, bloqueo por intentos fallidos, una sola
/// sesión activa por cuenta, "recordar dispositivo") es la misma; lo único
/// que cambia es que aquí no hay `flutter_secure_storage` ni un
/// `Session.current` global — el token/usuarioId llegan como parámetros
/// explícitos en cada llamada (los manda el cliente en cada petición HTTP),
/// y lo que antes se guardaba localmente ahora se devuelve al cliente para
/// que él lo guarde.
class AuthService {
  static const int maxIntentosFallidos = 5;
  static const Duration duracionBloqueo = Duration(minutes: 15);
  static const Duration duracionSesion = Duration(minutes: 30);
  static const Duration duracionRecordarDispositivo = Duration(days: 30);

  final AuditoriaService _auditoria = AuditoriaService();

  String _generarToken() {
    final random = Random.secure();
    final bytes = List<int>.generate(32, (_) => random.nextInt(256));
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }

  String _hashToken(String token) => sha256.convert(utf8.encode(token)).toString();

  Future<LoginResult> login({required String nombreUsuario, required String password}) async {
    final usuario = nombreUsuario.trim().toLowerCase();
    if (usuario.isEmpty || password.isEmpty) {
      throw ArgumentError('Ingresa tu usuario y contraseña.');
    }

    final result = await DatabaseService.instance.query(
      'SELECT usuario_id, nombre_usuario, nombre_completo, password_hash, intentos_fallidos, '
      'bloqueado_hasta, activo FROM usuarios WHERE nombre_usuario = :usuario',
      {'usuario': usuario},
    );

    if (result.rows.isEmpty) {
      BCrypt.hashpw(password, BCrypt.gensalt(logRounds: 12));
      throw ArgumentError(mensajeCredencialesInvalidas);
    }

    final f = result.rows.first.typedAssoc();
    final usuarioId = f['usuario_id'] as int;
    final activo = f['activo'] as bool;
    final bloqueadoHasta = f['bloqueado_hasta'] as DateTime?;
    final intentosFallidos = f['intentos_fallidos'] as int;
    final hash = f['password_hash'] as String;

    if (!activo) {
      throw ArgumentError(mensajeCredencialesInvalidas);
    }

    if (bloqueadoHasta != null && bloqueadoHasta.isAfter(DateTime.now())) {
      // Mismo mensaje genérico que credenciales inválidas: uno específico de
      // "cuenta bloqueada" le confirmaría a quien intenta adivinar cuentas
      // que ese nombre de usuario existe. Se hace además una verificación
      // bcrypt de relleno (se descarta el resultado) para que el tiempo de
      // respuesta no delate tampoco que la cuenta está bloqueada.
      BCrypt.checkpw(password, hash);
      throw ArgumentError(mensajeCredencialesInvalidas);
    }

    if (!BCrypt.checkpw(password, hash)) {
      final nuevosIntentos = intentosFallidos + 1;
      final seBloquea = nuevosIntentos >= maxIntentosFallidos;

      await DatabaseService.instance.query(
        'UPDATE usuarios SET intentos_fallidos = :intentos, bloqueado_hasta = :bloqueo WHERE usuario_id = :id',
        {
          'intentos': seBloquea ? 0 : nuevosIntentos,
          'bloqueo': seBloquea ? _formatDateTime(DateTime.now().add(duracionBloqueo)) : null,
          'id': usuarioId,
        },
      );
      await _auditoria.log(
        usuarioResponsable: 'Sistema',
        tablaAfectada: 'usuarios',
        registroId: usuario,
        accion: 'UPDATE',
        datosNuevos: {
          'evento': seBloquea ? 'cuenta bloqueada por intentos fallidos' : 'intento de login fallido',
          'intentos_fallidos': seBloquea ? 0 : nuevosIntentos,
        },
      );

      // Mismo mensaje genérico tanto si esta falla recién bloqueó la cuenta
      // como si no: no revelar por texto que la cuenta existe y se bloqueó.
      throw ArgumentError(mensajeCredencialesInvalidas);
    }

    // Sesión única por cuenta: si ya hay una sesión activa (no expirada) en
    // otro dispositivo, se rechaza este login SIN tocarla — la sesión
    // existente sigue viva y con su mismo token. Solo si esa sesión ya
    // expiró se permite continuar y reemplazarla más abajo.
    final sesionActual = await DatabaseService.instance.query(
      'SELECT expira_en FROM sesiones WHERE usuario_id = :id',
      {'id': usuarioId},
    );
    if (sesionActual.rows.isNotEmpty) {
      final expiraActual = sesionActual.rows.first.typedAssoc()['expira_en'] as DateTime;
      if (expiraActual.isAfter(DateTime.now())) {
        throw ArgumentError(
          'Ya hay una sesión activa en otro dispositivo. Cierra esa sesión antes de iniciar una nueva.',
        );
      }
    }

    await DatabaseService.instance.query(
      'UPDATE usuarios SET intentos_fallidos = 0, bloqueado_hasta = NULL, ultimo_login = NOW() '
      'WHERE usuario_id = :id',
      {'id': usuarioId},
    );

    final token = _generarToken();
    final tokenHash = _hashToken(token);
    final expiraEn = DateTime.now().add(duracionSesion);
    await DatabaseService.instance.query(
      'INSERT INTO sesiones (usuario_id, token_hash, expira_en) VALUES (:id, :hash, :exp) '
      'ON DUPLICATE KEY UPDATE token_hash = :hash, expira_en = :exp, creado_en = CURRENT_TIMESTAMP',
      {'id': usuarioId, 'hash': tokenHash, 'exp': _formatDateTime(expiraEn)},
    );

    final user = AuthUser(
      usuarioId: usuarioId,
      nombreUsuario: f['nombre_usuario'] as String,
      nombreCompleto: f['nombre_completo'] as String,
    );

    await _auditoria.log(
      usuarioResponsable: user.nombreCompleto,
      tablaAfectada: 'usuarios',
      registroId: usuario,
      accion: 'UPDATE',
      datosNuevos: {'evento': 'login exitoso'},
    );

    return LoginResult(user: user, token: token, expiraEn: expiraEn);
  }

  /// Valida el token de sesión que manda el cliente en cada petición
  /// autenticada; si sigue siendo válido, lo desliza otros 30 minutos (el
  /// mismo comportamiento que `restoreSession`/`refrescarActividad` tenían
  /// en la app). Devuelve `null` si no es válido por cualquier motivo
  /// (expiró, la reemplazó otro dispositivo, o la cuenta ya no está activa)
  /// sin distinguir cuál, igual que antes.
  Future<AuthUser?> validarYDeslizarSesion({required int usuarioId, required String token}) async {
    final hash = _hashToken(token);
    final result = await DatabaseService.instance.query(
      'SELECT s.token_hash, s.expira_en, u.usuario_id, u.nombre_usuario, u.nombre_completo, u.activo '
      'FROM sesiones s JOIN usuarios u ON u.usuario_id = s.usuario_id '
      'WHERE s.usuario_id = :id',
      {'id': usuarioId},
    );
    if (result.rows.isEmpty) return null;

    final f = result.rows.first.typedAssoc();
    final tokenHashServidor = f['token_hash'] as String;
    final expiraEnServidor = f['expira_en'] as DateTime;
    final activo = f['activo'] as bool;
    final ahora = DateTime.now();

    if (!activo || tokenHashServidor != hash || ahora.isAfter(expiraEnServidor)) {
      return null;
    }

    final nuevaExpiracion = ahora.add(duracionSesion);
    await DatabaseService.instance.query(
      'UPDATE sesiones SET expira_en = :exp WHERE usuario_id = :id AND token_hash = :hash',
      {'exp': _formatDateTime(nuevaExpiracion), 'id': usuarioId, 'hash': hash},
    );

    return AuthUser(
      usuarioId: f['usuario_id'] as int,
      nombreUsuario: f['nombre_usuario'] as String,
      nombreCompleto: f['nombre_completo'] as String,
    );
  }

  Future<void> logout({required int usuarioId, required String token, required String nombreUsuario}) async {
    await DatabaseService.instance.query(
      'DELETE FROM sesiones WHERE usuario_id = :id AND token_hash = :hash',
      {'id': usuarioId, 'hash': _hashToken(token)},
    );
    await _auditoria.log(
      usuarioResponsable: nombreUsuario,
      tablaAfectada: 'usuarios',
      registroId: nombreUsuario,
      accion: 'UPDATE',
      datosNuevos: {'evento': 'logout'},
    );
  }

  /// Activa el "recordar dispositivo" para la cuenta ya autenticada por
  /// [user]: genera y devuelve un token nuevo de larga duración para que el
  /// cliente lo guarde localmente (cifrado, vía `flutter_secure_storage`,
  /// igual que antes) y lo use luego en [renovarSesionConBiometria].
  Future<({String token, DateTime expiraEn})> habilitarRecordarDispositivo(AuthUser user) async {
    final token = _generarToken();
    final tokenHash = _hashToken(token);
    final expiraEn = DateTime.now().add(duracionRecordarDispositivo);

    await DatabaseService.instance.query(
      'INSERT INTO recordar_dispositivo (usuario_id, token_hash, expira_en) VALUES (:id, :hash, :exp) '
      'ON DUPLICATE KEY UPDATE token_hash = :hash, expira_en = :exp, creado_en = CURRENT_TIMESTAMP',
      {'id': user.usuarioId, 'hash': tokenHash, 'exp': _formatDateTime(expiraEn)},
    );

    await _auditoria.log(
      usuarioResponsable: user.nombreCompleto,
      tablaAfectada: 'usuarios',
      registroId: user.nombreUsuario,
      accion: 'UPDATE',
      datosNuevos: {'evento': 'desbloqueo biométrico activado en un dispositivo'},
    );

    return (token: token, expiraEn: expiraEn);
  }

  Future<void> olvidarDispositivo({required int usuarioId, required String token}) async {
    await DatabaseService.instance.query(
      'DELETE FROM recordar_dispositivo WHERE usuario_id = :id AND token_hash = :hash',
      {'id': usuarioId, 'hash': _hashToken(token)},
    );
  }

  /// Usa la credencial de "recordar" (ya confirmada por biometría del lado
  /// del sistema operativo en el cliente) para emitir una sesión nueva y
  /// legítima, exactamente igual que `renovarSesionConBiometria` en la app.
  /// Devuelve `null` si la credencial ya no es válida por cualquier motivo.
  Future<RenovarBiometriaResult?> renovarSesionConBiometria({required int usuarioId, required String recordarToken}) async {
    final hashRecordado = _hashToken(recordarToken);
    final result = await DatabaseService.instance.query(
      'SELECT r.token_hash, r.expira_en, u.usuario_id, u.nombre_usuario, u.nombre_completo, '
      'u.activo, u.bloqueado_hasta '
      'FROM recordar_dispositivo r JOIN usuarios u ON u.usuario_id = r.usuario_id '
      'WHERE r.usuario_id = :id',
      {'id': usuarioId},
    );
    if (result.rows.isEmpty) return null;

    final f = result.rows.first.typedAssoc();
    final ahora = DateTime.now();
    final activo = f['activo'] as bool;
    final bloqueadoHasta = f['bloqueado_hasta'] as DateTime?;
    final expiraEn = f['expira_en'] as DateTime;
    final valido = f['token_hash'] == hashRecordado &&
        activo &&
        (bloqueadoHasta == null || bloqueadoHasta.isBefore(ahora)) &&
        expiraEn.isAfter(ahora);

    if (!valido) return null;

    final nuevoToken = _generarToken();
    final nuevoHash = _hashToken(nuevoToken);
    final nuevaExpiracionRecordar = ahora.add(duracionRecordarDispositivo);
    await DatabaseService.instance.query(
      'UPDATE recordar_dispositivo SET token_hash = :hash, expira_en = :exp WHERE usuario_id = :id',
      {'hash': nuevoHash, 'exp': _formatDateTime(nuevaExpiracionRecordar), 'id': usuarioId},
    );

    final sesionToken = _generarToken();
    final sesionHash = _hashToken(sesionToken);
    final sesionExpiraEn = ahora.add(duracionSesion);
    await DatabaseService.instance.query(
      'INSERT INTO sesiones (usuario_id, token_hash, expira_en) VALUES (:id, :hash, :exp) '
      'ON DUPLICATE KEY UPDATE token_hash = :hash, expira_en = :exp, creado_en = CURRENT_TIMESTAMP',
      {'id': usuarioId, 'hash': sesionHash, 'exp': _formatDateTime(sesionExpiraEn)},
    );

    final user = AuthUser(
      usuarioId: f['usuario_id'] as int,
      nombreUsuario: f['nombre_usuario'] as String,
      nombreCompleto: f['nombre_completo'] as String,
    );

    await _auditoria.log(
      usuarioResponsable: user.nombreCompleto,
      tablaAfectada: 'usuarios',
      registroId: user.nombreUsuario,
      accion: 'UPDATE',
      datosNuevos: {'evento': 'login exitoso mediante biometría'},
    );

    return RenovarBiometriaResult(
      sesion: LoginResult(user: user, token: sesionToken, expiraEn: sesionExpiraEn),
      nuevoRecordarToken: nuevoToken,
    );
  }

  Future<void> changePassword({required AuthUser user, required String actual, required String nueva}) async {
    if (nueva.length < 8) {
      throw ArgumentError('La nueva contraseña debe tener al menos 8 caracteres.');
    }
    if (!RegExp(r'[A-Za-z]').hasMatch(nueva) || !RegExp(r'[0-9]').hasMatch(nueva)) {
      throw ArgumentError('La nueva contraseña debe combinar letras y números.');
    }

    final result = await DatabaseService.instance.query(
      'SELECT password_hash FROM usuarios WHERE usuario_id = :id',
      {'id': user.usuarioId},
    );
    final hashActual = result.rows.first.typedAssoc()['password_hash'] as String;

    if (!BCrypt.checkpw(actual, hashActual)) {
      throw ArgumentError('La contraseña actual no es correcta.');
    }
    if (BCrypt.checkpw(nueva, hashActual)) {
      throw ArgumentError('La nueva contraseña debe ser diferente a la actual.');
    }

    final nuevoHash = BCrypt.hashpw(nueva, BCrypt.gensalt(logRounds: 12));
    await DatabaseService.instance.query(
      'UPDATE usuarios SET password_hash = :hash WHERE usuario_id = :id',
      {'hash': nuevoHash, 'id': user.usuarioId},
    );

    await DatabaseService.instance.query(
      'DELETE FROM recordar_dispositivo WHERE usuario_id = :id',
      {'id': user.usuarioId},
    );

    await _auditoria.log(
      usuarioResponsable: user.nombreCompleto,
      tablaAfectada: 'usuarios',
      registroId: user.nombreUsuario,
      accion: 'UPDATE',
      datosNuevos: {'evento': 'contraseña actualizada por el propio usuario'},
    );
  }

  String _formatDateTime(DateTime dt) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${dt.year}-${two(dt.month)}-${two(dt.day)} ${two(dt.hour)}:${two(dt.minute)}:${two(dt.second)}';
  }
}
