-- ============================================================
-- Script DDL para Creación de la Base de Datos sinergyHousePrestamos
-- Actualizado en base a lo que consumen las pantallas en lib/screens
-- ============================================================

CREATE DATABASE IF NOT EXISTS sinergyHousePrestamos;
USE sinergyHousePrestamos;

-- ------------------------------------------------------------
-- Tabla: usuarios
-- Solo dos cuentas de tipo ADMINISTRADOR, creadas manualmente
-- (no hay registro público). password_hash siempre es bcrypt,
-- nunca texto plano. intentos_fallidos/bloqueado_hasta implementan
-- el bloqueo temporal tras varios intentos fallidos de login.
-- ------------------------------------------------------------
CREATE TABLE usuarios (
    usuario_id INT AUTO_INCREMENT PRIMARY KEY,
    nombre_usuario VARCHAR(50) UNIQUE NOT NULL,
    nombre_completo VARCHAR(150) NOT NULL,
    password_hash VARCHAR(255) NOT NULL,
    rol ENUM('ADMINISTRADOR') NOT NULL DEFAULT 'ADMINISTRADOR',
    intentos_fallidos INT NOT NULL DEFAULT 0,
    bloqueado_hasta DATETIME NULL,
    ultimo_login DATETIME NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    activo BOOLEAN DEFAULT TRUE
);

-- ------------------------------------------------------------
-- Tabla: sesiones
-- Una sola fila por usuario (usuario_id es la PK): al iniciar sesión se
-- reemplaza (UPSERT) el token de cualquier sesión anterior del mismo
-- usuario, lo que la invalida de inmediato en cualquier otro dispositivo
-- donde estuviera abierta (solo una sesión activa por cuenta). Nunca se
-- guarda el token real, solo su hash SHA-256; el token en sí vive
-- únicamente cifrado en el dispositivo (flutter_secure_storage).
-- expira_en implementa el cierre de sesión por 30 min de inactividad:
-- cada verificación de actividad la desliza hacia adelante, y si ya pasó
-- la sesión se considera terminada.
-- ------------------------------------------------------------
CREATE TABLE sesiones (
    usuario_id INT PRIMARY KEY,
    token_hash CHAR(64) NOT NULL,
    creado_en DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    expira_en DATETIME NOT NULL,
    FOREIGN KEY (usuario_id) REFERENCES usuarios(usuario_id) ON DELETE CASCADE
);

-- ------------------------------------------------------------
-- Tabla: recordar_dispositivo
-- Credencial de más larga duración (deslizante, ~30 días) para el
-- desbloqueo con huella/Face ID: cuando la sesión activa de `sesiones`
-- expira o se cierra, si existe una fila vigente aquí para el usuario, la
-- app puede pedir solo la biometría (en vez de usuario/contraseña) y, si
-- el sistema operativo la confirma, generar una sesión nueva. Igual que
-- `sesiones`, nunca guarda la contraseña ni el token real, solo su hash;
-- una sola fila por usuario (mismo criterio de "un solo dispositivo
-- recordado" que la sesión única).
-- ------------------------------------------------------------
CREATE TABLE recordar_dispositivo (
    usuario_id INT PRIMARY KEY,
    token_hash CHAR(64) NOT NULL,
    creado_en DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    expira_en DATETIME NOT NULL,
    FOREIGN KEY (usuario_id) REFERENCES usuarios(usuario_id) ON DELETE CASCADE
);

-- ------------------------------------------------------------
-- Tabla: clientes
-- ------------------------------------------------------------
CREATE TABLE clientes (
    cliente_id INT AUTO_INCREMENT PRIMARY KEY,
    documento_identidad VARCHAR(20) UNIQUE NOT NULL,
    tipo_cliente ENUM('NATURAL', 'JURIDICO') NOT NULL,
    nombre_cliente VARCHAR(150) NOT NULL,
    representante VARCHAR(150) NOT NULL,
    correo VARCHAR(100) NULL,
    telefono VARCHAR(20) NULL,
    direccion TEXT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    activo BOOLEAN DEFAULT TRUE,
    INDEX idx_clientes_nombre (nombre_cliente)
);

-- ------------------------------------------------------------
-- Tabla: prestamos
-- ------------------------------------------------------------
-- El tipo de préstamo se descompone en dos ejes independientes
-- en vez de un catálogo de 4 nombres ambiguos:
--   - tipo_tasa: si la tasa de interés puede cambiar a mitad de contrato.
--   - tipo_calculo: si el interés se paga cada periodo (Simple) o se
--     capitaliza sumándose al saldo (Compuesto).
CREATE TABLE prestamos (
    prestamo_id INT AUTO_INCREMENT PRIMARY KEY,
    codigo_referencia VARCHAR(50) UNIQUE NOT NULL,
    cliente_id INT NOT NULL,
    tipo_tasa ENUM('Fija', 'Variable') NOT NULL DEFAULT 'Fija',
    tipo_calculo ENUM('Simple', 'Compuesto') NOT NULL DEFAULT 'Simple',
    capital_inicial DECIMAL(15,2) NOT NULL,
    balance_actual DECIMAL(15,2) NOT NULL,
    -- Tasas expresadas en puntos porcentuales (ej: 12.5000 = 12.5%),
    -- igual a como se capturan en el formulario "Tasa de Interés (%)".
    tasa_interes_mensual DECIMAL(7,4) NOT NULL,
    -- Solo aplican (y son obligatorios) cuando tipo_tasa = 'Variable'.
    mes_cambio_tasa INT NULL,
    nueva_tasa_interes DECIMAL(7,4) NULL,
    -- Operación estructurada por fases (opcional): a partir de esta cuota,
    -- el interés deja de capitalizarse y pasa a ser pago líquido exigible.
    -- Solo puede usarse si tipo_calculo = 'Compuesto'.
    mes_cambio_capitalizacion INT NULL,
    frecuencia_pago ENUM('Diario', 'Semanal', 'Quincenal', 'Mensual', 'Anual') DEFAULT 'Mensual',
    -- Plazo fijo del préstamo: cuántos periodos (cuotas) tiene en total.
    numero_cuotas INT NOT NULL,
    fecha_inicio DATE NOT NULL,
    estado ENUM('Acumulacion', 'Renta_Fija', 'Activo', 'Pagado', 'Mora', 'Anulado') DEFAULT 'Activo',
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    activo BOOLEAN DEFAULT TRUE,
    FOREIGN KEY (cliente_id) REFERENCES clientes(cliente_id),
    INDEX idx_prestamos_estado (estado),
    CHECK (capital_inicial > 0),
    CHECK (balance_actual >= 0),
    CHECK (numero_cuotas > 0),
    CHECK (
        (tipo_tasa = 'Fija' AND mes_cambio_tasa IS NULL AND nueva_tasa_interes IS NULL)
        OR
        (tipo_tasa = 'Variable' AND mes_cambio_tasa IS NOT NULL AND nueva_tasa_interes IS NOT NULL)
    ),
    CHECK (
        mes_cambio_capitalizacion IS NULL
        OR (tipo_calculo = 'Compuesto' AND mes_cambio_capitalizacion >= 1 AND mes_cambio_capitalizacion <= numero_cuotas)
    )
);

-- ------------------------------------------------------------
-- Tabla: transacciones_capital
-- ------------------------------------------------------------
CREATE TABLE transacciones_capital (
    transaccionCapital_id INT AUTO_INCREMENT PRIMARY KEY,
    prestamo_id INT NOT NULL,
    fecha_transaccion DATE NOT NULL,
    tipo ENUM('Inyeccion', 'Retiro') NOT NULL,
    -- Número de cuota a partir de la cual aplica el movimiento (para
    -- movimientos planificados desde la creación del préstamo).
    periodo_aplicacion INT NULL,
    monto DECIMAL(15,2) NOT NULL,
    descripcion TEXT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    activo BOOLEAN DEFAULT TRUE,
    FOREIGN KEY (prestamo_id) REFERENCES prestamos(prestamo_id),
    CHECK (monto > 0)
);

-- ------------------------------------------------------------
-- Tabla: cuotas
-- ------------------------------------------------------------
CREATE TABLE cuotas (
    cuota_id INT AUTO_INCREMENT PRIMARY KEY,
    prestamo_id INT NOT NULL,
    numero_periodo INT NOT NULL,
    fecha_vencimiento DATE NOT NULL,
    saldo_inicio_periodo DECIMAL(15,2) NOT NULL,
    tasa_aplicada DECIMAL(7,4) NOT NULL,
    monto_interes_generado DECIMAL(15,2) NOT NULL,
    monto_capital_amortizado DECIMAL(15,2) DEFAULT 0.00,
    interes_capitalizado BOOLEAN DEFAULT FALSE,
    saldo_fin_periodo DECIMAL(15,2) NOT NULL,
    monto_pagado_acumulado DECIMAL(15,2) NOT NULL DEFAULT 0.00,
    estado ENUM('Pendiente', 'Parcial', 'Pagado', 'Vencido') DEFAULT 'Pendiente',
    FOREIGN KEY (prestamo_id) REFERENCES prestamos(prestamo_id),
    UNIQUE KEY uq_cuota_periodo (prestamo_id, numero_periodo),
    INDEX idx_cuotas_vencimiento (fecha_vencimiento, estado)
);

-- ------------------------------------------------------------
-- Tabla: recibos_pagos
-- ------------------------------------------------------------
-- cuota_id es NULL para Abono_Capital y Liquidacion_Total: esos movimientos
-- pagan contra el préstamo directamente, no contra una cuota puntual.
-- Pago_Parcial paga contra una cuota puntual sin cerrarla del todo (deja el
-- estado de esa cuota en 'Parcial' hasta que se complete con otro Pago_Parcial
-- o con un Cuota_Ordinaria por el resto).
CREATE TABLE recibos_pagos (
    reciboPago_id INT AUTO_INCREMENT PRIMARY KEY,
    codigo_recibo VARCHAR(20) UNIQUE NOT NULL,
    cuota_id INT NULL,
    prestamo_id INT NOT NULL,
    tipo_movimiento ENUM('Cuota_Ordinaria', 'Abono_Capital', 'Liquidacion_Total', 'Pago_Parcial') NOT NULL DEFAULT 'Cuota_Ordinaria',
    fecha_emision DATE NOT NULL,
    monto_total_pagado DECIMAL(15,2) NOT NULL,
    descripcion_concepto TEXT NOT NULL,
    metodo_pago VARCHAR(50) NULL,
    referencia VARCHAR(50) NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    activo BOOLEAN DEFAULT TRUE,
    FOREIGN KEY (cuota_id) REFERENCES cuotas(cuota_id),
    FOREIGN KEY (prestamo_id) REFERENCES prestamos(prestamo_id),
    INDEX idx_recibos_fecha (fecha_emision),
    CHECK (monto_total_pagado > 0),
    CONSTRAINT chk_recibos_cuota_tipo CHECK (
        (tipo_movimiento IN ('Cuota_Ordinaria', 'Pago_Parcial') AND cuota_id IS NOT NULL) OR
        (tipo_movimiento IN ('Abono_Capital', 'Liquidacion_Total') AND cuota_id IS NULL)
    )
);

-- ------------------------------------------------------------
-- Tabla: auditoria_sistema
-- ------------------------------------------------------------
CREATE TABLE auditoria_sistema (
    auditoriaSistema_id INT AUTO_INCREMENT PRIMARY KEY,
    tabla_afectada VARCHAR(50) NOT NULL,
    registro_id VARCHAR(50) NOT NULL,
    accion ENUM('INSERT', 'UPDATE', 'DELETE', 'DESACTIVAR') NOT NULL,
    datos_anteriores JSON NULL,
    datos_nuevos JSON NULL,
    fecha_accion TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    usuario_responsable VARCHAR(50) NULL,
    INDEX idx_auditoria_tabla (tabla_afectada),
    INDEX idx_auditoria_fecha (fecha_accion)
);

-- ------------------------------------------------------------
-- Vista: vista_salud_prestamos
-- Deriva el estado "AL DÍA / PENDIENTE / EN MORA" que muestra
-- loans_screen.dart, a partir de las cuotas reales en vez de
-- depender de un campo estático desincronizable en 'prestamos'.
-- ------------------------------------------------------------
CREATE OR REPLACE VIEW vista_salud_prestamos AS
SELECT
    p.prestamo_id,
    p.codigo_referencia,
    CASE
        WHEN EXISTS (
            SELECT 1 FROM cuotas c
            WHERE c.prestamo_id = p.prestamo_id
              AND c.estado = 'Pendiente'
              AND c.fecha_vencimiento < CURRENT_DATE()
        ) THEN 'EN MORA'
        WHEN EXISTS (
            SELECT 1 FROM cuotas c
            WHERE c.prestamo_id = p.prestamo_id
              AND c.estado = 'Pendiente'
              AND c.fecha_vencimiento <= DATE_ADD(CURRENT_DATE(), INTERVAL 7 DAY)
        ) THEN 'PENDIENTE'
        ELSE 'AL DÍA'
    END AS salud_pago,
    (
        SELECT MIN(c.fecha_vencimiento) FROM cuotas c
        WHERE c.prestamo_id = p.prestamo_id AND c.estado = 'Pendiente'
    ) AS proxima_cuota_vencimiento
FROM prestamos p
WHERE p.activo = TRUE;
