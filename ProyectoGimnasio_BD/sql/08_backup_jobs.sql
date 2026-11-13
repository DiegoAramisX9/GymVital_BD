/* =====================================================================
   Archivo : 08_backup_jobs.sql
   Responsable: Integrante 5 (Backup y recuperación)
   Objetivo: Estrategia de respaldo automatizada con SQL Server Agent.

   POLÍTICA PROPUESTA (justificación en el informe):
   +-----------+--------------------------+--------------------------------+---------------------------+
   | Tipo      | Frecuencia               | Retención                      | Justificación             |
   +-----------+--------------------------+--------------------------------+---------------------------+
   | FULL      | Domingo 02:00            | 4 semanas                      | Base de restauración;     |
   |           |                          |                                | domingo = menor actividad |
   | DIFF      | Lunes-Sábado 02:00       | 7 días                         | Acorta la cadena de       |
   |           |                          |                                | restauración (RTO)        |
   | LOG       | Cada 15 min (:03,:18...) | 7 días                         | RPO objetivo <= 15 min    |
   +-----------+--------------------------+--------------------------------+---------------------------+
   Modelo de recuperación: FULL.  RPO objetivo: 15 min.  RTO objetivo: 60 min.
   El gimnasio opera de 05:30 a 21:30: la ventana 02:00 no interfiere con reservas ni pagos.
   Los minutos :03/:18/:33/:48 evitan chocar con los jobs que arrancan en punto.
   Verificación: CHECKSUM + RESTORE VERIFYONLY en cada backup, job de monitoreo cada 30 min
   y prueba semanal de restauración con DBCC CHECKDB.
   Copia fuera del servidor: ROBOCOPY a otra unidad/recurso de red (o BACKUP TO URL en Azure).
   ===================================================================== */
USE GimnasioDB;
GO

/* ---------- 1. Procedimiento de respaldo (con bitácora y manejo de errores) ---------- */
CREATE OR ALTER PROCEDURE dbo.usp_RespaldarGimnasio
    @Tipo VARCHAR(4),                                  -- FULL | DIFF | LOG
    @Ruta NVARCHAR(260) = N'C:\SQLBackups\GimnasioDB\'
AS
BEGIN
    SET NOCOUNT ON;
    IF @Tipo NOT IN ('FULL','DIFF','LOG') THROW 50010, N'Tipo inválido: use FULL, DIFF o LOG.', 1;

    DECLARE @inicio DATETIME2(0) = SYSDATETIME(), @id INT, @archivo NVARCHAR(400),
            @sello VARCHAR(15) = CONVERT(VARCHAR(8), GETDATE(), 112) + '_' + REPLACE(CONVERT(VARCHAR(8), GETDATE(), 108), ':', '');
    SET @archivo = @Ruta + N'GimnasioDB_' + @Tipo + N'_' + @sello + CASE @Tipo WHEN 'FULL' THEN N'.bak' WHEN 'DIFF' THEN N'.dif' ELSE N'.trn' END;

    INSERT auditoria.BitacoraBackup (Tipo, Archivo, Inicio, Resultado) VALUES (@Tipo, @archivo, @inicio, 'EJECUTANDO');
    SET @id = SCOPE_IDENTITY();
    BEGIN TRY
        EXEC master.sys.xp_create_subdir @Ruta;
        IF @Tipo = 'FULL'
            BACKUP DATABASE GimnasioDB TO DISK = @archivo WITH COMPRESSION, CHECKSUM, INIT, NAME = N'GimnasioDB-FULL', STATS = 10;
        ELSE IF @Tipo = 'DIFF'
            BACKUP DATABASE GimnasioDB TO DISK = @archivo WITH DIFFERENTIAL, COMPRESSION, CHECKSUM, INIT, NAME = N'GimnasioDB-DIFF';
        ELSE
            BACKUP LOG GimnasioDB TO DISK = @archivo WITH COMPRESSION, CHECKSUM, INIT, NAME = N'GimnasioDB-LOG';

        RESTORE VERIFYONLY FROM DISK = @archivo WITH CHECKSUM;     -- el archivo es legible y consistente

        UPDATE auditoria.BitacoraBackup
           SET Resultado = 'OK', Fin = SYSDATETIME(),
               TamanoMB = (SELECT TOP 1 compressed_backup_size / 1048576.0 FROM msdb.dbo.backupset
                           WHERE database_name = N'GimnasioDB' ORDER BY backup_set_id DESC)
         WHERE BitacoraID = @id;
    END TRY
    BEGIN CATCH
        UPDATE auditoria.BitacoraBackup SET Resultado = 'ERROR', Fin = SYSDATETIME(), Mensaje = LEFT(ERROR_MESSAGE(), 2000) WHERE BitacoraID = @id;
        THROW;      -- relanza el error: el paso del Job FALLA y Agent lo registra / notifica
    END CATCH
END
GO

/* ---------- 2. Retención: borra respaldos viejos (xp_delete_file es no documentada pero muy usada) ---------- */
CREATE OR ALTER PROCEDURE dbo.usp_LimpiarRespaldos @Ruta NVARCHAR(260) = N'C:\SQLBackups\GimnasioDB\'
AS
BEGIN
    DECLARE @fFull DATETIME = DATEADD(DAY, -28, GETDATE()), @fDiff DATETIME = DATEADD(DAY, -7, GETDATE()), @fLog DATETIME = DATEADD(DAY, -7, GETDATE());
    EXEC master.sys.xp_delete_file 0, @Ruta, N'bak', @fFull, 0;
    EXEC master.sys.xp_delete_file 0, @Ruta, N'dif', @fDiff, 0;
    EXEC master.sys.xp_delete_file 0, @Ruta, N'trn', @fLog,  0;
END
GO

/* ---------- 3. Monitoreo: detecta "el job corrió pero NO hay respaldo bueno" ----------
   No confía en el estado del job: consulta la evidencia real en msdb.dbo.backupset. */
CREATE OR ALTER PROCEDURE dbo.usp_VerificarRespaldos
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @ultFull DATETIME, @ultBase DATETIME, @ultLog DATETIME, @err NVARCHAR(1000) = N'';
    SELECT @ultFull = MAX(CASE WHEN type = 'D' THEN backup_finish_date END),
           @ultBase = MAX(CASE WHEN type IN ('D','I') THEN backup_finish_date END),
           @ultLog  = MAX(CASE WHEN type = 'L' THEN backup_finish_date END)
    FROM msdb.dbo.backupset WHERE database_name = N'GimnasioDB' AND is_copy_only = 0;

    IF @ultLog  IS NULL OR @ultLog  < DATEADD(MINUTE, -45, GETDATE()) SET @err += N'Sin respaldo de LOG en los últimos 45 min. ';
    IF @ultBase IS NULL OR @ultBase < DATEADD(HOUR,   -26, GETDATE()) SET @err += N'Sin FULL/DIFF en las últimas 26 h. ';
    IF @ultFull IS NULL OR @ultFull < DATEADD(DAY,     -8, GETDATE()) SET @err += N'Sin FULL en los últimos 8 días. ';
    IF EXISTS (SELECT 1 FROM auditoria.BitacoraBackup WHERE Resultado = 'ERROR' AND Inicio > DATEADD(HOUR, -24, GETDATE()))
        SET @err += N'Hay respaldos con ERROR en las últimas 24 h (ver auditoria.BitacoraBackup). ';
    IF @err <> N'' THROW 50001, @err, 1;      -- hace fallar el job de monitoreo -> alerta al operador
    SELECT 'OK' AS Estado, @ultFull AS UltimoFull, @ultBase AS UltimoFullODiff, @ultLog AS UltimoLog;
END
GO

/* ---------- 4. Prueba semanal de restauración (evidencia real de RTO e integridad) ---------- */
CREATE OR ALTER PROCEDURE dbo.usp_ProbarRestauracion
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @archivo NVARCHAR(500), @sql NVARCHAR(MAX), @ini DATETIME2(0) = SYSDATETIME(),
            @d NVARCHAR(260) = CONVERT(NVARCHAR(260), SERVERPROPERTY('InstanceDefaultDataPath')),
            @l NVARCHAR(260) = CONVERT(NVARCHAR(260), SERVERPROPERTY('InstanceDefaultLogPath'));
    SELECT TOP 1 @archivo = mf.physical_device_name
    FROM msdb.dbo.backupset bs JOIN msdb.dbo.backupmediafamily mf ON mf.media_set_id = bs.media_set_id
    WHERE bs.database_name = N'GimnasioDB' AND bs.type = 'D' AND bs.is_copy_only = 0 ORDER BY bs.backup_finish_date DESC;
    IF @archivo IS NULL THROW 50020, N'No existe respaldo FULL para probar.', 1;
    BEGIN TRY
        IF DB_ID(N'GimnasioDB_Verif') IS NOT NULL DROP DATABASE GimnasioDB_Verif;
        SET @sql = N'RESTORE DATABASE GimnasioDB_Verif FROM DISK = N''' + @archivo + N''' WITH CHECKSUM, REPLACE, RECOVERY,
            MOVE N''GimnasioDB_Primary'' TO N''' + @d + N'GimnasioDB_Verif.mdf'', MOVE N''GimnasioDB_Datos'' TO N''' + @d + N'GimnasioDB_Verif_Datos.ndf'',
            MOVE N''GimnasioDB_Indices'' TO N''' + @d + N'GimnasioDB_Verif_Indices.ndf'', MOVE N''GimnasioDB_Log'' TO N''' + @l + N'GimnasioDB_Verif.ldf'';';
        EXEC (@sql);
        DBCC CHECKDB (GimnasioDB_Verif) WITH NO_INFOMSGS;
        DROP DATABASE GimnasioDB_Verif;
        INSERT auditoria.BitacoraBackup (Tipo, Archivo, Inicio, Fin, Resultado, Mensaje)
        VALUES ('PRUEBA', @archivo, @ini, SYSDATETIME(), 'OK', CONCAT('Restauración + CHECKDB correctos en ', DATEDIFF(SECOND, @ini, SYSDATETIME()), ' s'));
    END TRY
    BEGIN CATCH
        INSERT auditoria.BitacoraBackup (Tipo, Archivo, Inicio, Fin, Resultado, Mensaje) VALUES ('PRUEBA', @archivo, @ini, SYSDATETIME(), 'ERROR', LEFT(ERROR_MESSAGE(), 2000));
        THROW;
    END CATCH
END
GO

/* =====================================================================
   5. SQL SERVER AGENT: operador, jobs, horarios y alertas
   (el servicio SQL Server Agent debe estar iniciado y en inicio automático)
   ===================================================================== */
USE msdb;
GO
/* Operador: requiere Database Mail configurado para que el correo salga realmente.
   Mientras tanto, @notify_level_eventlog = 2 deja el fallo en el Visor de eventos de Windows. */
IF NOT EXISTS (SELECT 1 FROM dbo.sysoperators WHERE name = N'DBA_Gimnasio')
    EXEC dbo.sp_add_operator @name = N'DBA_Gimnasio', @enabled = 1, @email_address = N'dba@gymvital.example';   -- <<< CAMBIAR
GO

/* Procedimiento local para no repetir código al crear cada job */
CREATE OR ALTER PROCEDURE dbo.usp_CrearJobGimnasio
    @Job SYSNAME, @Descripcion NVARCHAR(300), @Paso1 NVARCHAR(100), @Comando1 NVARCHAR(MAX),
    @Paso2 NVARCHAR(100) = NULL, @Comando2 NVARCHAR(MAX) = NULL, @Subsistema1 NVARCHAR(20) = N'TSQL',
    @FreqTipo INT, @FreqIntervalo INT, @SubdiaTipo INT = 1, @SubdiaIntervalo INT = 0, @HoraInicio INT, @HoraFin INT = 235959
AS
BEGIN
    DECLARE @bd SYSNAME = CASE WHEN @Subsistema1 = N'TSQL' THEN N'GimnasioDB' END;   -- los pasos CmdExec no usan base de datos
    IF EXISTS (SELECT 1 FROM dbo.sysjobs WHERE name = @Job) EXEC dbo.sp_delete_job @job_name = @Job, @delete_unused_schedule = 1;
    EXEC dbo.sp_add_job @job_name = @Job, @description = @Descripcion, @enabled = 1,
         @notify_level_eventlog = 2, @notify_level_email = 2, @notify_email_operator_name = N'DBA_Gimnasio';   -- 2 = al FALLAR
    EXEC dbo.sp_add_jobstep @job_name = @Job, @step_id = 1, @step_name = @Paso1, @subsystem = @Subsistema1, @database_name = @bd,
         @command = @Comando1, @retry_attempts = 1, @retry_interval = 2,
         @on_success_action = CASE WHEN @Paso2 IS NULL THEN 1 ELSE 3 END, @on_fail_action = 2;
    IF @Paso2 IS NOT NULL
        EXEC dbo.sp_add_jobstep @job_name = @Job, @step_id = 2, @step_name = @Paso2, @subsystem = N'TSQL', @database_name = N'GimnasioDB',
             @command = @Comando2, @on_success_action = 1, @on_fail_action = 2;
    EXEC dbo.sp_add_jobschedule @job_name = @Job, @name = CONCAT(@Job, N'_Horario'), @enabled = 1,
         @freq_type = @FreqTipo, @freq_interval = @FreqIntervalo, @freq_recurrence_factor = 1,
         @freq_subday_type = @SubdiaTipo, @freq_subday_interval = @SubdiaIntervalo,
         @active_start_time = @HoraInicio, @active_end_time = @HoraFin;
    EXEC dbo.sp_add_jobserver @job_name = @Job, @server_name = N'(local)';
END
GO

-- FULL: domingo 02:00  (freq_type 8 = semanal; interval 1 = domingo)                 + limpieza de retención
EXEC dbo.usp_CrearJobGimnasio @Job = N'GimnasioDB_Backup_Full', @Descripcion = N'Respaldo completo semanal',
     @Paso1 = N'Respaldo FULL', @Comando1 = N'EXEC dbo.usp_RespaldarGimnasio @Tipo = ''FULL'';',
     @Paso2 = N'Limpieza de retencion', @Comando2 = N'EXEC dbo.usp_LimpiarRespaldos;',
     @FreqTipo = 8, @FreqIntervalo = 1, @HoraInicio = 20000;

-- DIFERENCIAL: lunes a sábado 02:00 (interval 126 = 2+4+8+16+32+64 = Lun..Sáb)
EXEC dbo.usp_CrearJobGimnasio @Job = N'GimnasioDB_Backup_Diff', @Descripcion = N'Respaldo diferencial diario',
     @Paso1 = N'Respaldo DIFF', @Comando1 = N'EXEC dbo.usp_RespaldarGimnasio @Tipo = ''DIFF'';',
     @FreqTipo = 8, @FreqIntervalo = 126, @HoraInicio = 20000;

-- LOG: cada 15 min a partir de 00:03  (freq_type 4 = diario; subday 4 = minutos)
EXEC dbo.usp_CrearJobGimnasio @Job = N'GimnasioDB_Backup_Log', @Descripcion = N'Respaldo del log de transacciones cada 15 min',
     @Paso1 = N'Respaldo LOG', @Comando1 = N'EXEC dbo.usp_RespaldarGimnasio @Tipo = ''LOG'';',
     @FreqTipo = 4, @FreqIntervalo = 1, @SubdiaTipo = 4, @SubdiaIntervalo = 15, @HoraInicio = 300;

-- MONITOREO: cada 30 min verifica evidencia real de respaldos (falla -> alerta)
EXEC dbo.usp_CrearJobGimnasio @Job = N'GimnasioDB_Monitor_Backups', @Descripcion = N'Verifica que existan respaldos recientes y válidos',
     @Paso1 = N'Verificar respaldos', @Comando1 = N'EXEC dbo.usp_VerificarRespaldos;',
     @FreqTipo = 4, @FreqIntervalo = 1, @SubdiaTipo = 4, @SubdiaIntervalo = 30, @HoraInicio = 1000;

-- COPIA FUERA DEL SERVIDOR: cada 30 min. Paso CmdExec (corre con la cuenta de Agent: darle permiso a la carpeta destino).
-- ROBOCOPY devuelve 0-7 = éxito y >= 8 = error; la condición convierte 0-7 en código de salida 0 para Agent.
EXEC dbo.usp_CrearJobGimnasio @Job = N'GimnasioDB_Copia_Externa', @Descripcion = N'Copia de respaldos a unidad/recurso externo',
     @Paso1 = N'Robocopy', @Subsistema1 = N'CmdExec',
     @Comando1 = N'robocopy "C:\SQLBackups\GimnasioDB" "D:\CopiaExterna\GimnasioDB" /E /XO /R:2 /W:5 & IF %ERRORLEVEL% LSS 8 EXIT /B 0',
     @FreqTipo = 4, @FreqIntervalo = 1, @SubdiaTipo = 4, @SubdiaIntervalo = 30, @HoraInicio = 800;
/* Alternativa en la nube: BACKUP DATABASE GimnasioDB TO URL = 'https://<cuenta>.blob.core.windows.net/<contenedor>/GimnasioDB.bak' WITH CREDENTIAL = '...' */

-- PRUEBA DE RESTAURACIÓN: domingo 04:00 (después del FULL de las 02:00)
EXEC dbo.usp_CrearJobGimnasio @Job = N'GimnasioDB_Prueba_Restauracion', @Descripcion = N'Restaura el último FULL en GimnasioDB_Verif y ejecuta DBCC CHECKDB',
     @Paso1 = N'Restaurar y verificar', @Comando1 = N'EXEC dbo.usp_ProbarRestauracion;',
     @FreqTipo = 8, @FreqIntervalo = 1, @HoraInicio = 40000;
GO
DROP PROCEDURE dbo.usp_CrearJobGimnasio;
GO

/* ---------- Alertas por errores de E/S / corrupción (823, 824, 825) ---------- */
DECLARE @n INT, @nombre SYSNAME;
DECLARE @errores TABLE (Num INT);
INSERT @errores VALUES (823), (824), (825);
DECLARE c CURSOR LOCAL FAST_FORWARD FOR SELECT Num FROM @errores;
OPEN c; FETCH NEXT FROM c INTO @n;
WHILE @@FETCH_STATUS = 0
BEGIN
    SET @nombre = CONCAT(N'GimnasioDB - Error ', @n, N' (corrupcion / E/S)');
    IF EXISTS (SELECT 1 FROM dbo.sysalerts WHERE name = @nombre) EXEC dbo.sp_delete_alert @name = @nombre;
    EXEC dbo.sp_add_alert @name = @nombre, @message_id = @n, @severity = 0, @enabled = 1, @delay_between_responses = 300,
         @include_event_description_in = 1, @database_name = N'GimnasioDB';
    EXEC dbo.sp_add_notification @alert_name = @nombre, @operator_name = N'DBA_Gimnasio', @notification_method = 1;  -- 1 = correo
    FETCH NEXT FROM c INTO @n;
END
CLOSE c; DEALLOCATE c;
GO

/* ---------- Primer ciclo manual (para tener la base de la cadena y evidencias) ---------- */
USE GimnasioDB;
GO
EXEC dbo.usp_RespaldarGimnasio @Tipo = 'FULL';
EXEC dbo.usp_RespaldarGimnasio @Tipo = 'LOG';
EXEC dbo.usp_VerificarRespaldos;
GO

/* ---------- EVIDENCIA PARA EL INFORME / DEFENSA ---------- */
-- A) Jobs configurados, horarios y estado del último resultado
SELECT j.name AS Job, j.enabled AS Habilitado, s.name AS Horario,
       CASE jh.run_status WHEN 1 THEN 'Correcto' WHEN 0 THEN 'FALLIDO' WHEN 2 THEN 'Reintento' WHEN 3 THEN 'Cancelado' ELSE 'Sin ejecutar' END AS UltimoResultado,
       jh.run_date AS Fecha, jh.run_time AS Hora, jh.message AS Mensaje
FROM msdb.dbo.sysjobs j
LEFT JOIN msdb.dbo.sysjobschedules js ON js.job_id = j.job_id
LEFT JOIN msdb.dbo.sysschedules s ON s.schedule_id = js.schedule_id
OUTER APPLY (SELECT TOP 1 * FROM msdb.dbo.sysjobhistory h WHERE h.job_id = j.job_id AND h.step_id = 0 ORDER BY h.instance_id DESC) jh
WHERE j.name LIKE 'GimnasioDB_%';

-- B) Historial de respaldos reales (de msdb)
SELECT TOP 30 bs.backup_finish_date AS Fin, CASE bs.type WHEN 'D' THEN 'FULL' WHEN 'I' THEN 'DIFF' WHEN 'L' THEN 'LOG' END AS Tipo,
       CAST(bs.compressed_backup_size / 1048576.0 AS DECIMAL(10,2)) AS ComprimidoMB, bs.recovery_model AS Modelo, mf.physical_device_name AS Archivo
FROM msdb.dbo.backupset bs JOIN msdb.dbo.backupmediafamily mf ON mf.media_set_id = bs.media_set_id
WHERE bs.database_name = N'GimnasioDB' ORDER BY bs.backup_finish_date DESC;

-- C) Bitácora propia
SELECT TOP 30 * FROM auditoria.BitacoraBackup ORDER BY BitacoraID DESC;
GO
