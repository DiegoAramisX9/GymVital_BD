/* =====================================================================
   Archivo : 04b_pruebas_seguridad.sql
   Responsable: Integrante 3 (Seguridad)
   Objetivo: DEMOSTRACIÓN DE ACCESO DENEGADO (diapositiva 4 de la defensa).
   Ejecutar DESPUÉS de 06_vistas_powerbi.sql.  Cada prueba cambia de contexto con
   EXECUTE AS USER, captura el error y vuelve con REVERT. Las pruebas permitidas
   se envuelven en una transacción con ROLLBACK para NO modificar datos.
   ===================================================================== */
USE GimnasioDB;
GO
SET NOCOUNT ON;

/* Procedimiento auxiliar de prueba: ejecuta una sentencia como otro usuario y reporta el resultado */
CREATE OR ALTER PROCEDURE dbo.usp_ProbarComo @Usuario SYSNAME, @Sentencia NVARCHAR(MAX), @Esperado VARCHAR(10)
AS
BEGIN
    DECLARE @sql NVARCHAR(MAX) = N'EXECUTE AS USER = ''' + @Usuario + N'''; BEGIN TRAN; ' + @Sentencia + N'; ROLLBACK; REVERT;';
    DECLARE @res VARCHAR(10) = 'PERMITIDO', @msg NVARCHAR(500) = N'';
    BEGIN TRY
        EXEC (@sql);
    END TRY
    BEGIN CATCH
        SET @res = 'DENEGADO'; SET @msg = ERROR_MESSAGE();
        IF XACT_STATE() <> 0 ROLLBACK;
        REVERT;
    END CATCH
    SELECT @Usuario AS Usuario, LEFT(@Sentencia, 70) AS Sentencia, @Esperado AS Esperado, @res AS Obtenido,
           IIF(@Esperado = @res, 'OK', 'FALLO') AS Veredicto, @msg AS MensajeDeError;
END
GO

/* ---------- Pruebas que DEBEN FALLAR (acceso denegado) ---------- */
EXEC dbo.usp_ProbarComo 'usr_entrenador', N'DELETE FROM operacion.Reserva WHERE ReservaID = 100', 'DENEGADO';
EXEC dbo.usp_ProbarComo 'usr_entrenador', N'SELECT TOP 1 * FROM finanzas.Pago', 'DENEGADO';
EXEC dbo.usp_ProbarComo 'usr_entrenador', N'SELECT Email FROM personas.Socio', 'DENEGADO';          -- columna no autorizada
EXEC dbo.usp_ProbarComo 'usr_recepcion',  N'DELETE FROM personas.Socio WHERE SocioID = 1', 'DENEGADO';
EXEC dbo.usp_ProbarComo 'usr_recepcion',  N'UPDATE finanzas.Pago SET Monto = 1 WHERE PagoID = 1', 'DENEGADO';
EXEC dbo.usp_ProbarComo 'usr_finanzas',   N'SELECT TOP 1 * FROM operacion.Reserva', 'DENEGADO';
EXEC dbo.usp_ProbarComo 'usr_finanzas',   N'DELETE FROM finanzas.Pago WHERE PagoID = 1', 'DENEGADO';
EXEC dbo.usp_ProbarComo 'usr_reportes',   N'SELECT TOP 1 * FROM personas.Socio', 'DENEGADO';
EXEC dbo.usp_ProbarComo 'usr_reportes',   N'UPDATE reportes.vw_OcupacionClases SET Sesiones = 0', 'DENEGADO';
EXEC dbo.usp_ProbarComo 'usr_reportes',   N'DROP TABLE operacion.Reserva', 'DENEGADO';

/* ---------- Pruebas que DEBEN FUNCIONAR (permisos legítimos) ---------- */
EXEC dbo.usp_ProbarComo 'usr_entrenador', N'UPDATE operacion.Reserva SET Estado = ''Asistio'' WHERE ReservaID = 100', 'PERMITIDO';
EXEC dbo.usp_ProbarComo 'usr_entrenador', N'SELECT TOP 5 SocioID, Nombres, Apellidos FROM personas.Socio', 'PERMITIDO';
EXEC dbo.usp_ProbarComo 'usr_recepcion',  N'UPDATE personas.Socio SET Telefono = ''7000-0000'' WHERE SocioID = 1', 'PERMITIDO';
EXEC dbo.usp_ProbarComo 'usr_finanzas',   N'UPDATE finanzas.Pago SET Estado = ''Pagado'' WHERE PagoID = 1', 'PERMITIDO';
EXEC dbo.usp_ProbarComo 'usr_reportes',   N'SELECT TOP 5 * FROM reportes.vw_OcupacionClases', 'PERMITIDO';   -- encadenamiento de propiedad
GO

/* ---------- Enmascaramiento dinámico: mismo SELECT, distinta vista según el rol ---------- */
EXECUTE AS USER = 'usr_recepcion'; SELECT TOP 3 SocioID, Email, Telefono, 'recepcion (UNMASK)' AS Quien FROM personas.Socio; REVERT;
EXECUTE AS USER = 'usr_finanzas';  SELECT TOP 3 SocioID, Email, Telefono, 'finanzas (enmascarado)' AS Quien FROM personas.Socio; REVERT;

/* ---------- Permisos efectivos de un usuario (para explicar en la defensa) ---------- */
EXECUTE AS USER = 'usr_entrenador';
SELECT entity_name, subentity_name, permission_name FROM sys.fn_my_permissions('personas.Socio', 'OBJECT') ORDER BY subentity_name, permission_name;
REVERT;

/* ---------- Revisar la bitácora DDL ---------- */
SELECT TOP 20 FechaHora, Usuario, Evento, Objeto FROM auditoria.BitacoraDDL ORDER BY BitacoraID DESC;
GO
