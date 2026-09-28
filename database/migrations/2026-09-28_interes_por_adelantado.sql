-- Migración: las cuotas se cobran por adelantado.
-- Antes, la cuota N vencía N periodos después de la fecha de inicio (el
-- interés de un mes se cobraba al terminar ese mes). Ahora vence N-1
-- periodos después: la cuota 1 vence el mismo día en que inicia el
-- préstamo, la cuota 2 un periodo después, etc. Los montos no cambian.
--
-- Para los préstamos que ya existen, cada cuota toma la fecha que tenía la
-- cuota anterior, y la cuota 1 toma la fecha de inicio del préstamo. Es
-- exactamente lo que genera el cálculo nuevo (LoanCalculator), siempre que
-- las fechas viejas sigan el patrón anterior (se verificó antes de correrla).
-- No toca pagos, montos ni estados.
--
-- Correr UNA sola vez: correrla de nuevo adelantaría las fechas otro periodo.
-- Uso (en el VPS):  mysql sinergyHousePrestamos < 2026-09-28_interes_por_adelantado.sql

START TRANSACTION;

CREATE TEMPORARY TABLE cuotas_nueva_fecha AS
SELECT c.cuota_id,
       COALESCE(
           LAG(c.fecha_vencimiento) OVER (PARTITION BY c.prestamo_id ORDER BY c.numero_periodo),
           p.fecha_inicio
       ) AS nueva_fecha
FROM cuotas c
JOIN prestamos p ON p.prestamo_id = c.prestamo_id;

UPDATE cuotas c
JOIN cuotas_nueva_fecha n ON n.cuota_id = c.cuota_id
SET c.fecha_vencimiento = n.nueva_fecha;

DROP TEMPORARY TABLE cuotas_nueva_fecha;

COMMIT;
