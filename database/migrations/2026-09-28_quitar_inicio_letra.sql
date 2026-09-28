-- Migración: la letra de cambio solo guarda su fecha de vencimiento.
-- Quita prestamos.fecha_inicio_letra (agregada en
-- 2026-09-28_letra_de_cambio.sql), que ya no se usa. Al momento de crear
-- esta migración ningún préstamo tenía esa fecha cargada.
--
-- Ejecutar DESPUÉS de desplegar el servidor que ya no la usa.
-- Uso (en el VPS):  mysql sinergyHousePrestamos < 2026-09-28_quitar_inicio_letra.sql

ALTER TABLE prestamos DROP COLUMN fecha_inicio_letra;
