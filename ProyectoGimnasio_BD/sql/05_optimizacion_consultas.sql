/* =====================================================================
   Archivo : 05_optimizacion_consultas.sql
   Responsable: Integrante 4 (Optimización y consultas avanzadas)
   Objetivo: 3 consultas de negocio (+2 extra) con funciones ventana, CTE y subconsultas;
             medición ANTES/DESPUÉS de crear índices.
   FLUJO DE TRABAJO (repetirlo y guardar capturas de cada paso):
     PARTE A  -> quita los índices de optimización (estado "ANTES").
     PARTE B  -> ejecutar las consultas con "Include Actual Execution Plan" (Ctrl+M).
                 Copiar de la pestaña Messages: logical reads y elapsed time.  == ANTES ==
     PARTE C  -> crea los índices.
     PARTE B  -> volver a ejecutar las MISMAS consultas.                        == DESPUÉS ==
     PARTE D  -> evidencia de uso, tamaño y mantenimiento de índices.
   Las fechas están fijas (no GETDATE()) para que los resultados sean reproducibles y
   coincidan con el dashboard de Power BI.
   ===================================================================== */
USE GimnasioDB;
GO

/* =====================================================================
   PARTE A - Estado ANTES: sólo existen índices de PK/UNIQUE
   ===================================================================== */
DROP INDEX IF EXISTS IX_Sesion_FechaHoraInicio       ON operacion.Sesion;
DROP INDEX IF EXISTS IX_Reserva_SesionID_Estado      ON operacion.Reserva;
DROP INDEX IF EXISTS IX_Reserva_SocioID_Estado       ON operacion.Reserva;
DROP INDEX IF EXISTS IX_Pago_Estado_FechaPago        ON finanzas.Pago;
DROP INDEX IF EXISTS IX_Suscripcion_SocioID          ON finanzas.Suscripcion;
GO

/* =====================================================================
   PARTE B - CONSULTAS (se ejecutan dos veces: ANTES y DESPUÉS)
   Antes de cada medición: limpiar caché (SÓLO en entorno de desarrollo)
   ===================================================================== */
CHECKPOINT; DBCC DROPCLEANBUFFERS;
SET STATISTICS IO ON;
SET STATISTICS TIME ON;
GO

/* ---------------------------------------------------------------------
   SELECT 1 - CASO DE NEGOCIO: ¿Qué tipos de clase tienen mayor % de ocupación en mayo 2026?
   Técnicas: CTE, LEFT JOIN, filtro por rango de fechas (sargable), agregación.
   Ocupación = reservas no canceladas / cupo máximo.
   Alimenta el GRÁFICO 1 del dashboard (barras por tipo de clase).
   --------------------------------------------------------------------- */
WITH ReservasPorSesion AS (
    SELECT s.SesionID, s.TipoClaseID, s.CupoMaximo, COUNT(r.ReservaID) AS Reservas
    FROM operacion.Sesion s
    LEFT JOIN operacion.Reserva r ON r.SesionID = s.SesionID AND r.Estado <> 'Cancelada'
    WHERE s.FechaHoraInicio >= '20260501' AND s.FechaHoraInicio < '20260601'
    GROUP BY s.SesionID, s.TipoClaseID, s.CupoMaximo
)
SELECT tc.Nombre                                   AS TipoClase,
       COUNT(*)                                    AS Sesiones,
       SUM(rs.CupoMaximo)                          AS CupoTotal,
       SUM(rs.Reservas)                            AS Reservas,
       CAST(100.0 * SUM(rs.Reservas) / SUM(rs.CupoMaximo) AS DECIMAL(5,2)) AS PctOcupacion
FROM ReservasPorSesion rs
JOIN operacion.TipoClase tc ON tc.TipoClaseID = rs.TipoClaseID
GROUP BY tc.Nombre
ORDER BY PctOcupacion DESC;
GO

/* ---------------------------------------------------------------------
   SELECT 2 - AGREGACIÓN / RELACIONES: Ingresos mensuales por plan de membresía (ene-jun 2026)
   Técnicas: 3 tablas, filtro por Estado + rango de fechas, GROUP BY por mes y plan.
   Alimenta el GRÁFICO 2 (columnas apiladas: ingresos por mes y plan).
   --------------------------------------------------------------------- */
SELECT DATEFROMPARTS(YEAR(p.FechaPago), MONTH(p.FechaPago), 1) AS Mes,
       pl.Nombre                                  AS PlanNombre,
       COUNT(*)                                   AS NumPagos,
       SUM(p.Monto)                               AS Ingresos,
       CAST(AVG(p.Monto) AS DECIMAL(10,2))        AS TicketPromedio
FROM finanzas.Pago p
JOIN finanzas.Suscripcion   su ON su.SuscripcionID = p.SuscripcionID
JOIN finanzas.PlanMembresia pl ON pl.PlanID        = su.PlanID
WHERE p.Estado = 'Pagado' AND p.FechaPago >= '20260101' AND p.FechaPago < '20260701'
GROUP BY DATEFROMPARTS(YEAR(p.FechaPago), MONTH(p.FechaPago), 1), pl.Nombre
ORDER BY Mes, PlanNombre;
GO

/* ---------------------------------------------------------------------
   SELECT 3 - MAYOR COMPLEJIDAD: Ranking mensual de entrenadores por asistencia, con variación
   contra el mes anterior, acumulado del semestre y promedio móvil de 3 meses.
   Técnicas: 2 CTE encadenados + FUNCIONES VENTANA: RANK(), LAG(), SUM() OVER (ROWS ...), AVG() OVER.
   Alimenta el GRÁFICO 3 (líneas: asistencia por entrenador Top 5).
   --------------------------------------------------------------------- */
WITH AsistenciaMensual AS (
    SELECT e.EntrenadorID,
           e.Nombres + N' ' + e.Apellidos                                   AS Entrenador,
           DATEFROMPARTS(YEAR(s.FechaHoraInicio), MONTH(s.FechaHoraInicio), 1) AS Mes,
           COUNT(*)                                                         AS Asistencias
    FROM operacion.Reserva r
    JOIN operacion.Sesion     s ON s.SesionID     = r.SesionID
    JOIN personas.Entrenador  e ON e.EntrenadorID = s.EntrenadorID
    WHERE r.Estado = 'Asistio' AND s.FechaHoraInicio >= '20260101' AND s.FechaHoraInicio < '20260701'
    GROUP BY e.EntrenadorID, e.Nombres, e.Apellidos, DATEFROMPARTS(YEAR(s.FechaHoraInicio), MONTH(s.FechaHoraInicio), 1)
),
Ventanas AS (
    SELECT *,
           RANK() OVER (PARTITION BY Mes ORDER BY Asistencias DESC)                          AS PosicionMes,
           LAG(Asistencias) OVER (PARTITION BY EntrenadorID ORDER BY Mes)                    AS AsistenciasMesAnterior,
           SUM(Asistencias) OVER (PARTITION BY EntrenadorID ORDER BY Mes
                                  ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW)          AS AcumuladoSemestre,
           CAST(AVG(Asistencias * 1.0) OVER (PARTITION BY EntrenadorID ORDER BY Mes
                                  ROWS BETWEEN 2 PRECEDING AND CURRENT ROW) AS DECIMAL(8,1)) AS PromedioMovil3M
    FROM AsistenciaMensual
)
SELECT Mes, PosicionMes, Entrenador, Asistencias, AsistenciasMesAnterior,
       CAST(100.0 * (Asistencias - AsistenciasMesAnterior) / NULLIF(AsistenciasMesAnterior, 0) AS DECIMAL(6,1)) AS VariacionPct,
       AcumuladoSemestre, PromedioMovil3M
FROM Ventanas
WHERE PosicionMes <= 5
ORDER BY Mes, PosicionMes;
GO

/* ---------------------------------------------------------------------
   SELECT 4 (EXTRA) - Segmentación de socios por gasto (NTILE) en el primer semestre 2026
   --------------------------------------------------------------------- */
WITH Gasto AS (
    SELECT so.SocioID, so.Nombres + N' ' + so.Apellidos AS Socio, SUM(p.Monto) AS TotalPagado, COUNT(*) AS Pagos
    FROM personas.Socio so
    JOIN finanzas.Suscripcion su ON su.SocioID = so.SocioID
    JOIN finanzas.Pago p         ON p.SuscripcionID = su.SuscripcionID
    WHERE p.Estado = 'Pagado' AND p.FechaPago >= '20260101' AND p.FechaPago < '20260701'
    GROUP BY so.SocioID, so.Nombres, so.Apellidos
)
SELECT TOP (100) SocioID, Socio, Pagos, TotalPagado,
       NTILE(4) OVER (ORDER BY TotalPagado DESC)        AS Cuartil,
       DENSE_RANK() OVER (ORDER BY TotalPagado DESC)    AS PosicionDenso
FROM Gasto
ORDER BY TotalPagado DESC, SocioID;
GO

/* ---------------------------------------------------------------------
   SELECT 5 (EXTRA) - Socios con suscripción vigente SIN asistencias desde el 01/05/2026
   (riesgo de abandono). Técnica: NOT EXISTS + EXISTS (subconsultas correlacionadas).
   --------------------------------------------------------------------- */
SELECT so.SocioID, so.Nombres, so.Apellidos
FROM personas.Socio so
WHERE EXISTS (SELECT 1 FROM finanzas.Suscripcion su WHERE su.SocioID = so.SocioID AND su.Estado = 'Vigente')
  AND NOT EXISTS (SELECT 1
                  FROM operacion.Reserva r
                  JOIN operacion.Sesion  s ON s.SesionID = r.SesionID
                  WHERE r.SocioID = so.SocioID AND r.Estado = 'Asistio' AND s.FechaHoraInicio >= '20260501')
ORDER BY so.SocioID;
GO
SET STATISTICS IO OFF;
SET STATISTICS TIME OFF;
GO

/* =====================================================================
   PARTE C - ÍNDICES (se crean en FG_INDICES, separados de los datos)
   Cada índice indica qué consulta apoya y por qué tiene esa forma.
   ===================================================================== */
-- SELECT 1 y 3: rango de fechas sobre Sesion; INCLUDE evita "key lookups" (cubre las columnas usadas).
CREATE NONCLUSTERED INDEX IX_Sesion_FechaHoraInicio
    ON operacion.Sesion (FechaHoraInicio) INCLUDE (TipoClaseID, EntrenadorID, CupoMaximo) ON FG_INDICES;

-- SELECT 1 y 3: unir sesión -> reservas filtrando por Estado; SocioID incluido para cubrir la consulta.
CREATE NONCLUSTERED INDEX IX_Reserva_SesionID_Estado
    ON operacion.Reserva (SesionID, Estado) INCLUDE (SocioID) ON FG_INDICES;

-- SELECT 5: reservas por socio y estado (también soporta la FK Reserva -> Socio).
CREATE NONCLUSTERED INDEX IX_Reserva_SocioID_Estado
    ON operacion.Reserva (SocioID, Estado) INCLUDE (SesionID) ON FG_INDICES;

-- SELECT 2 y 4: igualdad en Estado + rango en FechaPago -> SEEK en ambas columnas; cubre Monto y SuscripcionID.
CREATE NONCLUSTERED INDEX IX_Pago_Estado_FechaPago
    ON finanzas.Pago (Estado, FechaPago) INCLUDE (SuscripcionID, Monto) ON FG_INDICES;

-- SELECT 4 y 5: socio -> suscripciones (soporta la FK Suscripcion -> Socio).
CREATE NONCLUSTERED INDEX IX_Suscripcion_SocioID
    ON finanzas.Suscripcion (SocioID) INCLUDE (PlanID, Estado) ON FG_INDICES;
GO
UPDATE STATISTICS operacion.Sesion WITH FULLSCAN;
UPDATE STATISTICS operacion.Reserva WITH FULLSCAN;
UPDATE STATISTICS finanzas.Pago WITH FULLSCAN;
GO
/* >>> AHORA: volver a la PARTE B y ejecutar de nuevo las consultas (== DESPUÉS ==). <<< */

/* =====================================================================
   PARTE D - EVIDENCIA Y MANTENIMIENTO DE ÍNDICES
   ===================================================================== */
-- D.1 Tamaño de cada índice
SELECT OBJECT_SCHEMA_NAME(i.object_id) + '.' + OBJECT_NAME(i.object_id) AS Tabla, i.name AS Indice, i.type_desc AS Tipo,
       SUM(ps.used_page_count) * 8 / 1024.0 AS UsadoMB, SUM(ps.row_count) AS Filas
FROM sys.indexes i
JOIN sys.dm_db_partition_stats ps ON ps.object_id = i.object_id AND ps.index_id = i.index_id
WHERE OBJECTPROPERTY(i.object_id, 'IsUserTable') = 1 AND OBJECT_SCHEMA_NAME(i.object_id) IN ('personas','operacion','finanzas')
GROUP BY i.object_id, i.name, i.type_desc
ORDER BY UsadoMB DESC;

-- D.2 Uso real de los índices (lecturas vs. escrituras)
SELECT OBJECT_NAME(us.object_id) AS Tabla, i.name AS Indice, us.user_seeks, us.user_scans, us.user_lookups, us.user_updates
FROM sys.dm_db_index_usage_stats us
JOIN sys.indexes i ON i.object_id = us.object_id AND i.index_id = us.index_id
WHERE us.database_id = DB_ID() AND i.name LIKE 'IX_%';

-- D.3 Fragmentación (política: <10% nada; 10-30% REORGANIZE; >30% REBUILD)
SELECT OBJECT_SCHEMA_NAME(ips.object_id) + '.' + OBJECT_NAME(ips.object_id) AS Tabla, i.name AS Indice,
       ips.avg_fragmentation_in_percent AS FragPct, ips.page_count,
       CASE WHEN ips.avg_fragmentation_in_percent > 30 THEN 'REBUILD'
            WHEN ips.avg_fragmentation_in_percent > 10 THEN 'REORGANIZE' ELSE 'OK' END AS Accion
FROM sys.dm_db_index_physical_stats(DB_ID(), NULL, NULL, NULL, 'LIMITED') ips
JOIN sys.indexes i ON i.object_id = ips.object_id AND i.index_id = ips.index_id
WHERE ips.page_count > 100 AND i.name IS NOT NULL
ORDER BY ips.avg_fragmentation_in_percent DESC;

-- D.4 Consultas más costosas registradas por Query Store (habilitado en 01_crear_bd.sql)
SELECT TOP 10 q.query_id, LEFT(qt.query_sql_text, 100) AS Consulta, SUM(rs.count_executions) AS Ejecuciones,
       AVG(rs.avg_logical_io_reads) AS LecturasLogicasProm, AVG(rs.avg_duration) / 1000.0 AS DuracionProm_ms
FROM sys.query_store_query q
JOIN sys.query_store_query_text qt ON qt.query_text_id = q.query_text_id
JOIN sys.query_store_plan p ON p.query_id = q.query_id
JOIN sys.query_store_runtime_stats rs ON rs.plan_id = p.plan_id
GROUP BY q.query_id, LEFT(qt.query_sql_text, 100)
ORDER BY AVG(rs.avg_logical_io_reads) DESC;
GO
