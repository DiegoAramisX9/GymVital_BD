/* =====================================================================
   Archivo : 06_vistas_powerbi.sql
   Responsable: Integrante 2 (Dashboard Power BI) - usa las consultas del Integrante 4
   Objetivo: Capa semántica de sólo lectura para Power BI.
             Cada vista es el SELECT 1/2/3 de 05_optimizacion_consultas.sql SIN el filtro
             de fechas (granularidad mensual), de modo que el dashboard pueda filtrar por mes.
   TRAZABILIDAD:  Gráfico 1 <- vw_OcupacionClases   (SELECT 1)
                  Gráfico 2 <- vw_IngresosPorPlan    (SELECT 2)
                  Gráfico 3 <- vw_RankingEntrenadores (SELECT 3)
   ===================================================================== */
USE GimnasioDB;
GO
CREATE OR ALTER VIEW reportes.vw_OcupacionClases AS
WITH ReservasPorSesion AS (
    SELECT s.SesionID, s.TipoClaseID, s.CupoMaximo,
           DATEFROMPARTS(YEAR(s.FechaHoraInicio), MONTH(s.FechaHoraInicio), 1) AS Mes,
           COUNT(r.ReservaID) AS Reservas
    FROM operacion.Sesion s
    LEFT JOIN operacion.Reserva r ON r.SesionID = s.SesionID AND r.Estado <> 'Cancelada'
    GROUP BY s.SesionID, s.TipoClaseID, s.CupoMaximo, DATEFROMPARTS(YEAR(s.FechaHoraInicio), MONTH(s.FechaHoraInicio), 1)
)
SELECT rs.Mes, tc.Nombre AS TipoClase, COUNT(*) AS Sesiones, SUM(rs.CupoMaximo) AS CupoTotal, SUM(rs.Reservas) AS Reservas,
       CAST(100.0 * SUM(rs.Reservas) / SUM(rs.CupoMaximo) AS DECIMAL(5,2)) AS PctOcupacion
FROM ReservasPorSesion rs
JOIN operacion.TipoClase tc ON tc.TipoClaseID = rs.TipoClaseID
GROUP BY rs.Mes, tc.Nombre;
GO

CREATE OR ALTER VIEW reportes.vw_IngresosPorPlan AS
SELECT DATEFROMPARTS(YEAR(p.FechaPago), MONTH(p.FechaPago), 1) AS Mes, pl.Nombre AS PlanNombre,
       COUNT(*) AS NumPagos, SUM(p.Monto) AS Ingresos, CAST(AVG(p.Monto) AS DECIMAL(10,2)) AS TicketPromedio
FROM finanzas.Pago p
JOIN finanzas.Suscripcion   su ON su.SuscripcionID = p.SuscripcionID
JOIN finanzas.PlanMembresia pl ON pl.PlanID = su.PlanID
WHERE p.Estado = 'Pagado'
GROUP BY DATEFROMPARTS(YEAR(p.FechaPago), MONTH(p.FechaPago), 1), pl.Nombre;
GO

CREATE OR ALTER VIEW reportes.vw_RankingEntrenadores AS
WITH AsistenciaMensual AS (
    SELECT e.EntrenadorID, e.Nombres + N' ' + e.Apellidos AS Entrenador,
           DATEFROMPARTS(YEAR(s.FechaHoraInicio), MONTH(s.FechaHoraInicio), 1) AS Mes, COUNT(*) AS Asistencias
    FROM operacion.Reserva r
    JOIN operacion.Sesion s ON s.SesionID = r.SesionID
    JOIN personas.Entrenador e ON e.EntrenadorID = s.EntrenadorID
    WHERE r.Estado = 'Asistio'
    GROUP BY e.EntrenadorID, e.Nombres, e.Apellidos, DATEFROMPARTS(YEAR(s.FechaHoraInicio), MONTH(s.FechaHoraInicio), 1)
)
SELECT Mes, Entrenador, Asistencias,
       RANK() OVER (PARTITION BY Mes ORDER BY Asistencias DESC) AS PosicionMes,
       LAG(Asistencias) OVER (PARTITION BY EntrenadorID ORDER BY Mes) AS AsistenciasMesAnterior,
       CAST(AVG(Asistencias * 1.0) OVER (PARTITION BY EntrenadorID ORDER BY Mes ROWS BETWEEN 2 PRECEDING AND CURRENT ROW) AS DECIMAL(8,1)) AS PromedioMovil3M
FROM AsistenciaMensual;
GO

/* ---------- VALIDACIÓN "¿Coinciden los resultados?" (mostrar en la defensa) ----------
   Las vistas, filtradas al mismo periodo, deben dar EXACTAMENTE lo mismo que los SELECT 1 y 2. */
SELECT 'SELECT1 vs vista (mayo 2026)' AS Prueba,
       (SELECT SUM(Reservas) FROM reportes.vw_OcupacionClases WHERE Mes = '20260501') AS ValorVista,
       (SELECT COUNT(*) FROM operacion.Reserva r JOIN operacion.Sesion s ON s.SesionID = r.SesionID
         WHERE r.Estado <> 'Cancelada' AND s.FechaHoraInicio >= '20260501' AND s.FechaHoraInicio < '20260601') AS ValorBase
UNION ALL
SELECT 'SELECT2 vs vista (ene-jun 2026)',
       (SELECT SUM(Ingresos) FROM reportes.vw_IngresosPorPlan WHERE Mes >= '20260101' AND Mes < '20260701'),
       (SELECT SUM(Monto) FROM finanzas.Pago WHERE Estado = 'Pagado' AND FechaPago >= '20260101' AND FechaPago < '20260701');
GO
