/// Usuario administrador autenticado actualmente en la app.
class AuthUser {
  final int usuarioId;
  final String nombreUsuario;
  final String nombreCompleto;

  const AuthUser({
    required this.usuarioId,
    required this.nombreUsuario,
    required this.nombreCompleto,
  });
}

/// Punto único y global de acceso al usuario logueado. Se mantiene separado
/// de [AuthService] (que sí depende de la base de datos y de auditoría)
/// para que servicios como `AuditoriaService` puedan leer quién está
/// logueado sin generar una dependencia circular entre ambos.
class Session {
  Session._();

  static AuthUser? current;
}
