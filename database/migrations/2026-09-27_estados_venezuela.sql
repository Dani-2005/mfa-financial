-- Migración: estado de Venezuela donde se ubica cada préstamo.
-- Crea el catálogo `estados` (23 estados + Distrito Capital) y le agrega a
-- `prestamos` la columna estado_id, que apunta a ese catálogo.
--
-- OJO: `prestamos.estado` (Activo, Pagado, Mora...) es el estado del
-- préstamo, no tiene nada que ver con esto; por eso la columna nueva se
-- llama estado_id y la tabla `estados` solo guarda la ubicación geográfica.
--
-- estado_id queda NULL en los préstamos que ya existen: la app los muestra
-- bajo "Sin estado" hasta que alguien los edite y les asigne uno. Los
-- préstamos nuevos lo exigen desde el formulario.
--
-- Uso (en el VPS):  mysql sinergyHousePrestamos < 2026-09-27_estados_venezuela.sql

CREATE TABLE estados (
    estado_id INT AUTO_INCREMENT PRIMARY KEY,
    nombre VARCHAR(50) UNIQUE NOT NULL
);

INSERT INTO estados (nombre) VALUES
    ('Amazonas'), ('Anzoátegui'), ('Apure'), ('Aragua'), ('Barinas'),
    ('Bolívar'), ('Carabobo'), ('Cojedes'), ('Delta Amacuro'), ('Distrito Capital'),
    ('Falcón'), ('Guárico'), ('Lara'), ('Mérida'), ('Miranda'),
    ('Monagas'), ('Nueva Esparta'), ('Portuguesa'), ('Sucre'), ('Táchira'),
    ('Trujillo'), ('La Guaira'), ('Yaracuy'), ('Zulia');

ALTER TABLE prestamos
    ADD COLUMN estado_id INT NULL AFTER cliente_id,
    ADD CONSTRAINT fk_prestamos_estado FOREIGN KEY (estado_id) REFERENCES estados(estado_id),
    ADD INDEX idx_prestamos_estado_id (estado_id);
