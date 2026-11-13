/* =====================================================================
   Archivo : 09_demo_recuperacion.sql
   Responsable: Integrante 5 (Backup y recuperación)
   Objetivo: Demostrar paso a paso la RECUPERACIÓN POINT-IN-TIME con FULL + DIFF + LOG + TAIL-LOG,
             restaurando en una base ALTERNATIVA sin tocar la original (reto de la diapositiva 11).
   Se usa una BD de práctica (GimnasioDemoDB) para NO romper la cadena de backups de GimnasioDB.

   ESCENARIO (adaptado a nuestra política):
     FULL: domingo 02:00 | DIFF: hoy 02:00 | LOG: cada 15 min (último a las 11:18) | FALLO: 11:20
     RPO objetivo = 15 min  -> con el último LOG programado se pierden como máximo 15 min;
                               con TAIL-LOG BACKUP (si el archivo .ldf sigue accesible) la pérdida es ~0.
     RTO objetivo = 60 min  -> tiempo medido más abajo (RTO_real) + tiempo de decisión/coordinación.
   ===================================================================== */
USE master;
GO
IF DB_ID(N'GimnasioDemoDB_Restore') IS NOT NULL DROP DATABASE GimnasioDemoDB_Restore;
IF DB_ID(N'GimnasioDemoDB') IS NOT NULL BEGIN ALTER DATABASE GimnasioDemoDB SET SINGLE_USER WITH ROLLBACK IMMEDIATE; DROP DATABASE GimnasioDemoDB; END
CREATE DATABASE GimnasioDemoDB;
ALTER DATABASE GimnasioDemoDB SET RECOVERY FULL;
GO
USE GimnasioDemoDB;
GO
SELECT TOP (2000) SocioID, Nombres, Apellidos, Estado INTO dbo.SocioDemo FROM GimnasioDB.personas.Socio ORDER BY SocioID;   -- datos reales de ejemplo
CREATE TABLE dbo.EventoDemo (ID INT IDENTITY PRIMARY KEY, Evento NVARCHAR(100) NOT NULL, Fecha DATETIME2(3) NOT NULL DEFAULT SYSDATETIME());
GO

SET NOCOUNT ON;
DECLARE @r NVARCHAR(260) = N'C:\SQLBackups\GimnasioDemo\';
DECLARE @full NVARCHAR(300) = @r + N'demo_full.bak', @dif NVARCHAR(300) = @r + N'demo_diff.dif',
        @log1 NVARCHAR(300) = @r + N'demo_log1.trn',  @tail NVARCHAR(300) = @r + N'demo_tail.trn';
DECLARE @d NVARCHAR(260) = CONVERT(NVARCHAR(260), SERVERPROPERTY('InstanceDefaultDataPath')),
        @l NVARCHAR(260) = CONVERT(NVARCHAR(260), SERVERPROPERTY('InstanceDefaultLogPath'));
DECLARE @stop DATETIME, @sql NVARCHAR(MAX), @mv NVARCHAR(MAX), @t0 DATETIME2(3), @t1 DATETIME2(3);
EXEC master.sys.xp_create_subdir @r;

/* 1) Domingo 02:00 -> FULL */
INSERT dbo.EventoDemo (Evento) VALUES (N'Dato A - existía antes del FULL');
BACKUP DATABASE GimnasioDemoDB TO DISK = @full WITH INIT, CHECKSUM, COMPRESSION, NAME = N'demo-full';
/* 2) Hoy 02:00 -> DIFERENCIAL */
INSERT dbo.EventoDemo (Evento) VALUES (N'Dato B - entra después del FULL, cubierto por el DIFF');
BACKUP DATABASE GimnasioDemoDB TO DISK = @dif WITH DIFFERENTIAL, INIT, CHECKSUM, COMPRESSION, NAME = N'demo-diff';
/* 3) 11:18 -> LOG */
INSERT dbo.EventoDemo (Evento) VALUES (N'Dato C - cubierto por el LOG de las 11:18');
BACKUP LOG GimnasioDemoDB TO DISK = @log1 WITH INIT, CHECKSUM, COMPRESSION, NAME = N'demo-log1';
/* 4) 11:19 -> datos que SÓLO se recuperan con TAIL-LOG (aún no hay backup que los cubra) */
INSERT dbo.EventoDemo (Evento) VALUES (N'Dato D - sólo recuperable con tail-log');
WAITFOR DELAY '00:00:02';
SET @stop = GETDATE();                       -- <<< punto en el tiempo al que queremos volver (justo antes del error)
WAITFOR DELAY '00:00:02';

/* 5) 11:20 -> DESASTRE: borrado accidental (o fallo de disco) */
DELETE FROM dbo.EventoDemo;
DROP TABLE dbo.SocioDemo;
PRINT 'DESASTRE simulado: tabla vaciada y SocioDemo eliminada.';

/* 6) TAIL-LOG BACKUP: captura lo ocurrido desde el último LOG hasta el fallo.
      NO_TRUNCATE permite hacerlo aunque la BD esté dañada (mientras el .ldf sea legible). */
BACKUP LOG GimnasioDemoDB TO DISK = @tail WITH NO_TRUNCATE, INIT, CHECKSUM, NAME = N'demo-tail';

/* 7) RESTAURAR EN BASE ALTERNATIVA (la original no se toca) */
SET @t0 = SYSDATETIME();
SET @mv = N'MOVE N''GimnasioDemoDB'' TO N''' + @d + N'GimnasioDemoDB_Restore.mdf'', MOVE N''GimnasioDemoDB_log'' TO N''' + @l + N'GimnasioDemoDB_Restore.ldf''';
SET @sql = N'RESTORE DATABASE GimnasioDemoDB_Restore FROM DISK = N''' + @full + N''' WITH ' + @mv + N', NORECOVERY, REPLACE, CHECKSUM;'; EXEC (@sql);
SET @sql = N'RESTORE DATABASE GimnasioDemoDB_Restore FROM DISK = N''' + @dif  + N''' WITH NORECOVERY, CHECKSUM;';  EXEC (@sql);
SET @sql = N'RESTORE LOG GimnasioDemoDB_Restore FROM DISK = N''' + @log1 + N''' WITH NORECOVERY, CHECKSUM;';       EXEC (@sql);
SET @sql = N'RESTORE LOG GimnasioDemoDB_Restore FROM DISK = N''' + @tail + N''' WITH STOPAT = ''' + CONVERT(NVARCHAR(30), @stop, 126) + N''', RECOVERY, CHECKSUM;'; EXEC (@sql);
SET @t1 = SYSDATETIME();

/* 8) EVIDENCIA */
SELECT 'Original (tras el desastre)' AS Base, COUNT(*) AS Filas FROM GimnasioDemoDB.dbo.EventoDemo
UNION ALL SELECT 'Restaurada hasta ' + CONVERT(VARCHAR(23), @stop, 121), COUNT(*) FROM GimnasioDemoDB_Restore.dbo.EventoDemo;
SELECT * FROM GimnasioDemoDB_Restore.dbo.EventoDemo ORDER BY ID;               -- deben verse A, B, C y D
SELECT COUNT(*) AS SocioDemo_Recuperados FROM GimnasioDemoDB_Restore.dbo.SocioDemo;  -- la tabla "borrada" volvió
SELECT DATEDIFF(MILLISECOND, @t0, @t1) / 1000.0 AS RTO_real_segundos;
GO

/* =====================================================================
   9) PARA LA BD REAL: construir la cadena de restauración desde el historial de msdb
   (qué FULL, qué DIFF y qué LOGs se necesitan para llegar a una hora determinada)
   ===================================================================== */
DECLARE @puntoRecuperacion DATETIME = '20260630 11:20';      -- <<< hora del fallo / punto deseado
;WITH Ultimo_Full AS (
    SELECT TOP 1 backup_set_id, backup_finish_date, database_backup_lsn FROM msdb.dbo.backupset
    WHERE database_name = N'GimnasioDB' AND type = 'D' AND is_copy_only = 0 AND backup_finish_date <= @puntoRecuperacion ORDER BY backup_finish_date DESC),
Ultimo_Diff AS (
    SELECT TOP 1 bs.backup_set_id, bs.backup_finish_date FROM msdb.dbo.backupset bs CROSS JOIN Ultimo_Full f
    WHERE bs.database_name = N'GimnasioDB' AND bs.type = 'I' AND bs.backup_finish_date > f.backup_finish_date AND bs.backup_finish_date <= @puntoRecuperacion
    ORDER BY bs.backup_finish_date DESC)
SELECT Paso = ROW_NUMBER() OVER (ORDER BY bs.backup_finish_date), CASE bs.type WHEN 'D' THEN 'RESTORE FULL' WHEN 'I' THEN 'RESTORE DIFF' ELSE 'RESTORE LOG' END AS Operacion,
       bs.backup_finish_date AS Fin, mf.physical_device_name AS Archivo
FROM msdb.dbo.backupset bs
JOIN msdb.dbo.backupmediafamily mf ON mf.media_set_id = bs.media_set_id
WHERE bs.database_name = N'GimnasioDB'
  AND ( bs.backup_set_id IN (SELECT backup_set_id FROM Ultimo_Full)
     OR bs.backup_set_id IN (SELECT backup_set_id FROM Ultimo_Diff)
     OR (bs.type = 'L' AND bs.backup_finish_date > COALESCE((SELECT backup_finish_date FROM Ultimo_Diff), (SELECT backup_finish_date FROM Ultimo_Full))) )
ORDER BY bs.backup_finish_date;
GO

/* Limpieza de la demo (opcional)
USE master; DROP DATABASE IF EXISTS GimnasioDemoDB_Restore; DROP DATABASE IF EXISTS GimnasioDemoDB;
*/
