/* =====================================================================
   Archivo : 07_dimensionamiento.sql
   Responsable: Integrante 5 (Backup, recuperación y almacenamiento)
   Objetivo: Dimensionamiento y gestión del almacenamiento: medir el tamaño actual,
             proyectar crecimiento a 12 y 36 meses y estimar espacio de backups.
   Ejecutar DESPUÉS de cargar los datos (03) y crear los índices (05).
   ===================================================================== */
USE GimnasioDB;
GO
SET NOCOUNT ON;

/* ---------- 1. Tamaño actual por tabla (filas, datos, índices, bytes por fila) ---------- */
IF OBJECT_ID('tempdb..#Uso') IS NOT NULL DROP TABLE #Uso;
SELECT SCHEMA_NAME(t.schema_id) + '.' + t.name AS Tabla,
       SUM(CASE WHEN ps.index_id IN (0,1) THEN ps.row_count END)                         AS Filas,
       SUM(CASE WHEN ps.index_id IN (0,1) THEN ps.used_page_count END) * 8 / 1024.0      AS DatosMB,
       SUM(CASE WHEN ps.index_id > 1      THEN ps.used_page_count END) * 8 / 1024.0      AS IndicesMB,
       SUM(ps.used_page_count) * 8 / 1024.0                                              AS TotalMB
INTO #Uso
FROM sys.tables t
JOIN sys.dm_db_partition_stats ps ON ps.object_id = t.object_id
WHERE SCHEMA_NAME(t.schema_id) IN ('personas','operacion','finanzas')
GROUP BY t.schema_id, t.name;

SELECT Tabla, Filas, CAST(DatosMB AS DECIMAL(10,2)) AS DatosMB, CAST(ISNULL(IndicesMB,0) AS DECIMAL(10,2)) AS IndicesMB,
       CAST(TotalMB AS DECIMAL(10,2)) AS TotalMB, CAST(DatosMB * 1048576 / NULLIF(Filas,0) AS DECIMAL(10,1)) AS BytesPorFila
FROM #Uso ORDER BY TotalMB DESC;

/* ---------- 2. Proyección de crecimiento ----------
   Supuestos (editar y justificar en el informe):
   - Los datos actuales representan @MesesHistoricos meses de operación.
   - La actividad crecerá @FactorCrecimiento veces respecto al ritmo histórico (apertura de nuevos socios).
   - Se agrega @Holgura de seguridad (30 %) para índices nuevos, fragmentación y picos.                    */
DECLARE @MesesHistoricos INT = 24, @FactorCrecimiento DECIMAL(4,2) = 1.20, @Holgura DECIMAL(4,2) = 1.30;
DECLARE @ActualMB DECIMAL(12,2) = (SELECT SUM(TotalMB) FROM #Uso);
DECLARE @MensualMB DECIMAL(12,2) = @ActualMB / @MesesHistoricos * @FactorCrecimiento;

SELECT Horizonte, CAST(ActualMB + MensualMB * Meses AS DECIMAL(12,1))                AS DatosMasIndicesMB,
       CAST((ActualMB + MensualMB * Meses) * @Holgura AS DECIMAL(12,1))              AS ConHolguraMB,
       CAST((ActualMB + MensualMB * Meses) * @Holgura * 0.25 AS DECIMAL(12,1))       AS LogRecomendadoMB   -- regla práctica: 25 % de los datos
FROM (VALUES ('Hoy', 0), ('+12 meses', 12), ('+36 meses', 36)) h(Horizonte, Meses)
CROSS JOIN (SELECT @ActualMB AS ActualMB, @MensualMB AS MensualMB) x;

/* ---------- 3. Estimación del espacio de BACKUPS en disco ----------
   Política (ver 08): 4 FULL (semanales) + 6 DIFF + 7 días de LOG cada 15 min.
   Ratio de compresión medido en msdb tras el primer FULL; si no existe, se asume 0.35.             */
DECLARE @ratio DECIMAL(5,3) = ISNULL((SELECT TOP 1 CAST(compressed_backup_size * 1.0 / NULLIF(backup_size,0) AS DECIMAL(5,3))
                                       FROM msdb.dbo.backupset WHERE database_name = N'GimnasioDB' AND type = 'D' ORDER BY backup_finish_date DESC), 0.35);
SELECT @ratio AS RatioCompresion,
       CAST(@ActualMB * @ratio AS DECIMAL(10,1))                         AS UnFullMB,
       CAST(@ActualMB * @ratio * 4 AS DECIMAL(10,1))                     AS CuatroFullsMB,
       CAST(@ActualMB * @ratio * 0.15 * 6 AS DECIMAL(10,1))              AS SeisDiferencialesMB,   -- ~15 % del FULL por diferencial
       CAST(@ActualMB * 0.01 * 7 AS DECIMAL(10,1))                       AS LogsSieteDiasMB,       -- ~1 % diario (estimado, medir con BitacoraBackup)
       CAST(@ActualMB * @ratio * 4 + @ActualMB * @ratio * 0.15 * 6 + @ActualMB * 0.07 AS DECIMAL(10,1)) AS TotalBackupsMB;

/* ---------- 4. Estado actual de los archivos (espacio libre y autocrecimiento) ---------- */
SELECT f.name AS Archivo, ISNULL(fg.name, 'LOG') AS Filegroup, f.size * 8 / 1024 AS TamanoMB,
       FILEPROPERTY(f.name, 'SpaceUsed') * 8 / 1024 AS UsadoMB,
       (f.size - FILEPROPERTY(f.name, 'SpaceUsed')) * 8 / 1024 AS LibreMB,
       CASE WHEN f.is_percent_growth = 1 THEN CONCAT(f.growth, ' %') ELSE CONCAT(f.growth * 8 / 1024, ' MB') END AS Crecimiento,
       CASE f.max_size WHEN -1 THEN 'Sin límite' WHEN 0 THEN 'Sin crecimiento' ELSE CONCAT(f.max_size * 8 / 1024, ' MB') END AS MaximoPermitido
FROM sys.database_files f LEFT JOIN sys.filegroups fg ON fg.data_space_id = f.data_space_id;

DBCC SQLPERF (LOGSPACE);   -- % de uso del log de todas las BD

/* ---------- 5. ¿Está habilitada la inicialización instantánea de archivos (IFI)? ---------- */
SELECT servicename, instant_file_initialization_enabled FROM sys.dm_server_services;
GO

/* ---------- 6. Recomendaciones de gestión del almacenamiento (incluir en el informe) ----------
   1) Pre-dimensionar los archivos al tamaño proyectado a 12 meses: evita autogrowth en horario pico.
   2) Autogrowth en MB fijos (128 MB datos, 64 MB índices/log), nunca en %.
   3) Monitorear LibreMB: alertar cuando quede < 20 % libre en cualquier archivo.
   4) Separar físicamente (discos distintos) FG_DATOS, FG_INDICES, el LOG y la carpeta de BACKUPS.
   5) Datos históricos (> 24 meses): evaluar particionamiento por fecha o archivado a una BD de histórico.
   ---------------------------------------------------------------------------------------- */
