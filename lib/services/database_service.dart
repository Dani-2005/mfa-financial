import 'package:mysql_client_plus/mysql_client_plus.dart';
import '../config/db_config.dart';

class DatabaseService {
  DatabaseService._()
      : _pool = MySQLConnectionPool(
          host: DbConfig.host,
          port: DbConfig.port,
          userName: DbConfig.user,
          password: DbConfig.password,
          databaseName: DbConfig.database,
          maxConnections: 5,
        );

  static final DatabaseService instance = DatabaseService._();

  final MySQLConnectionPool _pool;

  Future<IResultSet> query(String sql, [Map<String, dynamic>? params]) {
    return _pool.execute(sql, params);
  }

  Future<bool> testConnection() async {
    try {
      await query('SELECT 1');
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<void> close() => _pool.close();
}
