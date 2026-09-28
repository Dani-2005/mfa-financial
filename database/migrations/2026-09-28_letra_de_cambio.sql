-- Migración: fechas de la letra de cambio de cada préstamo.
-- Agrega a `prestamos` la fecha en que inicia la letra y la fecha en que
-- vence. Son opcionales (NULL en los préstamos que ya existen y en los que
-- no tengan letra); si se indica una, se indican las dos (lo valida el
-- servidor). La tarjeta del préstamo muestra "La letra vence el DD/MM/AAAA".
--
-- Uso (en el VPS):  mysql sinergyHousePrestamos < 2026-09-28_letra_de_cambio.sql

ALTER TABLE prestamos
    ADD COLUMN fecha_inicio_letra DATE NULL AFTER fecha_inicio,
    ADD COLUMN fecha_vencimiento_letra DATE NULL AFTER fecha_inicio_letra;
