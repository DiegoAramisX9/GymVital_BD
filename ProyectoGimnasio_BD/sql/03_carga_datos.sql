/* =====================================================================
   Archivo : 03_carga_datos.sql
   Responsable: Integrante 2 (Migración / carga de datos)
   Objetivo: ETL en 3 fases:  CSV -> staging (BULK INSERT) -> limpieza/validación -> tablas finales.
   Requisitos:
     1) Ejecutar antes 01 y 02.   2) Generar los CSV:  python datos/generar_datos.py
     3) Copiar la carpeta /datos a  C:\ProyectoGimnasio\datos\  (cambiar @Ruta si es otra)
     4) La cuenta de servicio de SQL Server necesita permiso de LECTURA sobre esa carpeta.
   Alternativas documentadas en el informe: Import Flat File Wizard, bcp, Power Query.
   ===================================================================== */
USE GimnasioDB;
GO
SET NOCOUNT ON;
GO

/* ============ FASE 0: parámetros y tablas de control ============ */
IF OBJECT_ID('staging.Rechazo') IS NULL
    CREATE TABLE staging.Rechazo (RechazoID INT IDENTITY PRIMARY KEY, Tabla SYSNAME, Clave NVARCHAR(50),
                                  Motivo NVARCHAR(200), Valor NVARCHAR(200), FechaHora DATETIME2(0) DEFAULT SYSDATETIME());
IF OBJECT_ID('staging.LogCarga') IS NULL
    CREATE TABLE staging.LogCarga (LogID INT IDENTITY PRIMARY KEY, Tabla SYSNAME, Leidas INT, Insertadas INT,
                                   Advertencias INT, Rechazadas INT, FechaHora DATETIME2(0) DEFAULT SYSDATETIME());
TRUNCATE TABLE staging.Rechazo;
TRUNCATE TABLE staging.LogCarga;
GO

/* ============ FASE 1: tablas de aterrizaje (todo texto, sin restricciones) ============ */
DROP TABLE IF EXISTS staging.PlanMembresia, staging.TipoClase, staging.Sala, staging.Entrenador, staging.Socio,
                     staging.Suscripcion, staging.Pago, staging.Sesion, staging.Reserva;
CREATE TABLE staging.PlanMembresia (plan_id NVARCHAR(200), nombre NVARCHAR(200), precio NVARCHAR(200), duracion_meses NVARCHAR(200), descripcion NVARCHAR(200));
CREATE TABLE staging.TipoClase     (tipo_clase_id NVARCHAR(200), nombre NVARCHAR(200), duracion_min NVARCHAR(200), intensidad NVARCHAR(200));
CREATE TABLE staging.Sala          (sala_id NVARCHAR(200), nombre NVARCHAR(200), capacidad NVARCHAR(200));
CREATE TABLE staging.Entrenador    (entrenador_id NVARCHAR(200), nombres NVARCHAR(200), apellidos NVARCHAR(200), email NVARCHAR(200), especialidad NVARCHAR(200), fecha_contratacion NVARCHAR(200), activo NVARCHAR(200));
CREATE TABLE staging.Socio         (socio_id NVARCHAR(200), nombres NVARCHAR(200), apellidos NVARCHAR(200), email NVARCHAR(200), telefono NVARCHAR(200), fecha_nacimiento NVARCHAR(200), sexo NVARCHAR(200), fecha_registro NVARCHAR(200), estado NVARCHAR(200));
CREATE TABLE staging.Suscripcion   (suscripcion_id NVARCHAR(200), socio_id NVARCHAR(200), plan_id NVARCHAR(200), fecha_inicio NVARCHAR(200), fecha_fin NVARCHAR(200), estado NVARCHAR(200));
CREATE TABLE staging.Pago          (pago_id NVARCHAR(200), suscripcion_id NVARCHAR(200), fecha_pago NVARCHAR(200), monto NVARCHAR(200), metodo_pago NVARCHAR(200), estado NVARCHAR(200));
CREATE TABLE staging.Sesion        (sesion_id NVARCHAR(200), tipo_clase_id NVARCHAR(200), entrenador_id NVARCHAR(200), sala_id NVARCHAR(200), fecha_hora_inicio NVARCHAR(200), fecha_hora_fin NVARCHAR(200), cupo_maximo NVARCHAR(200));
CREATE TABLE staging.Reserva       (reserva_id NVARCHAR(200), sesion_id NVARCHAR(200), socio_id NVARCHAR(200), fecha_reserva NVARCHAR(200), estado NVARCHAR(200));
GO

/* Función de apoyo: "  JOSÉ  " -> "José"   /   "RAMÍREZ HERNÁNDEZ" -> "Ramírez Hernández" */
CREATE OR ALTER FUNCTION staging.fn_InitCap (@s NVARCHAR(200)) RETURNS NVARCHAR(200)
AS
BEGIN
    SET @s = LOWER(LTRIM(RTRIM(@s)));
    DECLARE @i INT = 1, @r NVARCHAR(200) = N'', @c NCHAR(1), @prev NCHAR(1) = N' ';
    WHILE @i <= LEN(@s)
    BEGIN
        SET @c = SUBSTRING(@s, @i, 1);
        SET @r += CASE WHEN @prev = N' ' THEN UPPER(@c) ELSE @c END;
        SET @prev = @c; SET @i += 1;
    END
    RETURN @r;
END
GO

/* Procedimiento genérico de carga CSV -> staging (BULK INSERT no admite variables: SQL dinámico) */
CREATE OR ALTER PROCEDURE staging.usp_CargarCSV @Tabla SYSNAME, @Archivo NVARCHAR(300), @UltimaColumna SYSNAME
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @sql NVARCHAR(MAX) =
        N'BULK INSERT staging.' + QUOTENAME(@Tabla) + N' FROM ''' + @Archivo + N'''
          WITH (FORMAT = ''CSV'', FIRSTROW = 2, FIELDQUOTE = ''"'', ROWTERMINATOR = ''0x0a'', CODEPAGE = ''65001'', TABLOCK);
          UPDATE staging.' + QUOTENAME(@Tabla) + N' SET ' + QUOTENAME(@UltimaColumna) + N' = REPLACE(' + QUOTENAME(@UltimaColumna) + N', CHAR(13), '''');';
    EXEC (@sql);   -- el REPLACE protege contra archivos con fin de línea CRLF (Windows/Git)
END
GO

DECLARE @Ruta NVARCHAR(260) = N'C:\ProyectoGimnasio\datos\';    -- <<< AJUSTAR SI ES NECESARIO
DECLARE @t0 DATETIME2 = SYSDATETIME();
EXEC staging.usp_CargarCSV 'PlanMembresia', @Ruta + N'planes.csv',        'descripcion';
EXEC staging.usp_CargarCSV 'TipoClase',     @Ruta + N'tipos_clase.csv',   'intensidad';
EXEC staging.usp_CargarCSV 'Sala',          @Ruta + N'salas.csv',         'capacidad';
EXEC staging.usp_CargarCSV 'Entrenador',    @Ruta + N'entrenadores.csv',  'activo';
EXEC staging.usp_CargarCSV 'Socio',         @Ruta + N'socios.csv',        'estado';
EXEC staging.usp_CargarCSV 'Suscripcion',   @Ruta + N'suscripciones.csv', 'estado';
EXEC staging.usp_CargarCSV 'Pago',          @Ruta + N'pagos.csv',         'estado';
EXEC staging.usp_CargarCSV 'Sesion',        @Ruta + N'sesiones.csv',      'cupo_maximo';
EXEC staging.usp_CargarCSV 'Reserva',       @Ruta + N'reservas.csv',      'estado';
PRINT CONCAT('Fase 1 (CSV -> staging) completada en ', DATEDIFF(SECOND, @t0, SYSDATETIME()), ' s');
GO

/* ============ FASE 2: reinicio de tablas finales (permite re-ejecutar) ============ */
DELETE FROM operacion.Reserva;   DELETE FROM finanzas.Pago;       DELETE FROM finanzas.Suscripcion;
DELETE FROM operacion.Sesion;    DELETE FROM personas.Socio;      DELETE FROM personas.Entrenador;
DELETE FROM operacion.TipoClase; DELETE FROM operacion.Sala;      DELETE FROM finanzas.PlanMembresia;
GO

/* ============ FASE 3: limpieza + carga a tablas finales (respetando el orden de las FK) ============ */
-- 3.1 Catálogos
SET IDENTITY_INSERT finanzas.PlanMembresia ON;
INSERT finanzas.PlanMembresia (PlanID, Nombre, Precio, DuracionMeses, Descripcion)
SELECT TRY_CONVERT(int, plan_id), LTRIM(RTRIM(nombre)), TRY_CONVERT(decimal(8,2), precio), TRY_CONVERT(tinyint, duracion_meses), NULLIF(LTRIM(RTRIM(descripcion)), '')
FROM staging.PlanMembresia;
SET IDENTITY_INSERT finanzas.PlanMembresia OFF;
INSERT staging.LogCarga (Tabla, Leidas, Insertadas, Advertencias, Rechazadas)
SELECT 'PlanMembresia', (SELECT COUNT(*) FROM staging.PlanMembresia), (SELECT COUNT(*) FROM finanzas.PlanMembresia), 0, 0;

SET IDENTITY_INSERT operacion.TipoClase ON;
INSERT operacion.TipoClase (TipoClaseID, Nombre, DuracionMin, Intensidad)
SELECT TRY_CONVERT(int, tipo_clase_id), LTRIM(RTRIM(nombre)), TRY_CONVERT(smallint, duracion_min), LTRIM(RTRIM(intensidad)) FROM staging.TipoClase;
SET IDENTITY_INSERT operacion.TipoClase OFF;
INSERT staging.LogCarga (Tabla, Leidas, Insertadas, Advertencias, Rechazadas)
SELECT 'TipoClase', (SELECT COUNT(*) FROM staging.TipoClase), (SELECT COUNT(*) FROM operacion.TipoClase), 0, 0;

SET IDENTITY_INSERT operacion.Sala ON;
INSERT operacion.Sala (SalaID, Nombre, Capacidad)
SELECT TRY_CONVERT(int, sala_id), LTRIM(RTRIM(nombre)), TRY_CONVERT(smallint, capacidad) FROM staging.Sala;
SET IDENTITY_INSERT operacion.Sala OFF;
INSERT staging.LogCarga (Tabla, Leidas, Insertadas, Advertencias, Rechazadas)
SELECT 'Sala', (SELECT COUNT(*) FROM staging.Sala), (SELECT COUNT(*) FROM operacion.Sala), 0, 0;

SET IDENTITY_INSERT personas.Entrenador ON;
INSERT personas.Entrenador (EntrenadorID, Nombres, Apellidos, Email, Especialidad, FechaContratacion, Activo)
SELECT TRY_CONVERT(int, entrenador_id), staging.fn_InitCap(nombres), staging.fn_InitCap(apellidos), LOWER(LTRIM(RTRIM(email))),
       LTRIM(RTRIM(especialidad)), TRY_CONVERT(date, fecha_contratacion, 23), TRY_CONVERT(bit, activo)
FROM staging.Entrenador;
SET IDENTITY_INSERT personas.Entrenador OFF;
INSERT staging.LogCarga (Tabla, Leidas, Insertadas, Advertencias, Rechazadas)
SELECT 'Entrenador', (SELECT COUNT(*) FROM staging.Entrenador), (SELECT COUNT(*) FROM personas.Entrenador), 0, 0;
GO

-- 3.2 Socios: se CORRIGE (trim, capitalización, email en minúsculas, sexo normalizado, teléfono vacío -> NULL)
--     y se REGISTRA como advertencia cualquier fecha de nacimiento imposible (se carga NULL).
INSERT staging.Rechazo (Tabla, Clave, Motivo, Valor)
SELECT 'Socio', socio_id, 'ADVERTENCIA: fecha de nacimiento inválida, se cargó NULL', fecha_nacimiento
FROM staging.Socio WHERE TRY_CONVERT(date, fecha_nacimiento, 23) IS NULL AND NULLIF(LTRIM(RTRIM(fecha_nacimiento)), '') IS NOT NULL;
DECLARE @advSocio INT = @@ROWCOUNT;

SET IDENTITY_INSERT personas.Socio ON;
INSERT personas.Socio (SocioID, Nombres, Apellidos, Email, Telefono, FechaNacimiento, Sexo, FechaRegistro, Estado)
SELECT TRY_CONVERT(int, socio_id), staging.fn_InitCap(nombres), staging.fn_InitCap(apellidos), LOWER(LTRIM(RTRIM(email))),
       NULLIF(LTRIM(RTRIM(telefono)), ''), TRY_CONVERT(date, fecha_nacimiento, 23),
       CASE UPPER(LEFT(LTRIM(sexo), 1)) WHEN 'M' THEN 'M' WHEN 'F' THEN 'F' END,
       TRY_CONVERT(date, fecha_registro, 23), LTRIM(RTRIM(estado))
FROM staging.Socio;
DECLARE @insSocio INT = @@ROWCOUNT;
SET IDENTITY_INSERT personas.Socio OFF;
INSERT staging.LogCarga (Tabla, Leidas, Insertadas, Advertencias, Rechazadas)
SELECT 'Socio', (SELECT COUNT(*) FROM staging.Socio), @insSocio, @advSocio, 0;
GO

-- 3.3 Sesiones y suscripciones
SET IDENTITY_INSERT operacion.Sesion ON;
INSERT operacion.Sesion (SesionID, TipoClaseID, EntrenadorID, SalaID, FechaHoraInicio, FechaHoraFin, CupoMaximo)
SELECT TRY_CONVERT(int, sesion_id), TRY_CONVERT(int, tipo_clase_id), TRY_CONVERT(int, entrenador_id), TRY_CONVERT(int, sala_id),
       TRY_CONVERT(datetime2(0), fecha_hora_inicio, 120), TRY_CONVERT(datetime2(0), fecha_hora_fin, 120), TRY_CONVERT(smallint, cupo_maximo)
FROM staging.Sesion;
SET IDENTITY_INSERT operacion.Sesion OFF;
INSERT staging.LogCarga (Tabla, Leidas, Insertadas, Advertencias, Rechazadas)
SELECT 'Sesion', (SELECT COUNT(*) FROM staging.Sesion), (SELECT COUNT(*) FROM operacion.Sesion), 0, 0;

SET IDENTITY_INSERT finanzas.Suscripcion ON;
INSERT finanzas.Suscripcion (SuscripcionID, SocioID, PlanID, FechaInicio, FechaFin, Estado)
SELECT TRY_CONVERT(int, suscripcion_id), TRY_CONVERT(int, socio_id), TRY_CONVERT(int, plan_id),
       TRY_CONVERT(date, fecha_inicio, 23), TRY_CONVERT(date, fecha_fin, 23), LTRIM(RTRIM(estado))
FROM staging.Suscripcion;
SET IDENTITY_INSERT finanzas.Suscripcion OFF;
INSERT staging.LogCarga (Tabla, Leidas, Insertadas, Advertencias, Rechazadas)
SELECT 'Suscripcion', (SELECT COUNT(*) FROM staging.Suscripcion), (SELECT COUNT(*) FROM finanzas.Suscripcion), 0, 0;
GO

-- 3.4 Pagos: se RECHAZAN montos no numéricos o <= 0 y fechas inválidas (quedan en staging.Rechazo)
INSERT staging.Rechazo (Tabla, Clave, Motivo, Valor)
SELECT 'Pago', pago_id,
       CASE WHEN TRY_CONVERT(decimal(10,2), monto) IS NULL THEN 'RECHAZADO: monto no numérico'
            WHEN TRY_CONVERT(decimal(10,2), monto) <= 0     THEN 'RECHAZADO: monto negativo o cero'
            ELSE 'RECHAZADO: fecha de pago inválida' END, CONCAT('monto=', monto, ' fecha=', fecha_pago)
FROM staging.Pago
WHERE ISNULL(TRY_CONVERT(decimal(10,2), monto), -1) <= 0 OR TRY_CONVERT(date, fecha_pago, 23) IS NULL;
DECLARE @rechPago INT = @@ROWCOUNT;

SET IDENTITY_INSERT finanzas.Pago ON;
INSERT finanzas.Pago (PagoID, SuscripcionID, FechaPago, Monto, MetodoPago, Estado)
SELECT TRY_CONVERT(bigint, pago_id), TRY_CONVERT(int, suscripcion_id), TRY_CONVERT(date, fecha_pago, 23),
       TRY_CONVERT(decimal(10,2), monto), LTRIM(RTRIM(metodo_pago)), LTRIM(RTRIM(estado))
FROM staging.Pago
WHERE ISNULL(TRY_CONVERT(decimal(10,2), monto), -1) > 0 AND TRY_CONVERT(date, fecha_pago, 23) IS NOT NULL;
DECLARE @insPago INT = @@ROWCOUNT;
SET IDENTITY_INSERT finanzas.Pago OFF;
INSERT staging.LogCarga (Tabla, Leidas, Insertadas, Advertencias, Rechazadas)
SELECT 'Pago', (SELECT COUNT(*) FROM staging.Pago), @insPago, 0, @rechPago;
GO

-- 3.5 Reservas (tabla más grande)
SET IDENTITY_INSERT operacion.Reserva ON;
INSERT operacion.Reserva (ReservaID, SesionID, SocioID, FechaReserva, Estado)
SELECT TRY_CONVERT(bigint, reserva_id), TRY_CONVERT(int, sesion_id), TRY_CONVERT(int, socio_id),
       TRY_CONVERT(datetime2(0), fecha_reserva, 120), LTRIM(RTRIM(estado))
FROM staging.Reserva;
SET IDENTITY_INSERT operacion.Reserva OFF;
INSERT staging.LogCarga (Tabla, Leidas, Insertadas, Advertencias, Rechazadas)
SELECT 'Reserva', (SELECT COUNT(*) FROM staging.Reserva), (SELECT COUNT(*) FROM operacion.Reserva), 0, 0;
GO

/* ============ FASE 4: validaciones y evidencia para el informe ============ */
-- 4.1 Conciliación: leídas = insertadas + rechazadas
SELECT Tabla, Leidas, Insertadas, Advertencias, Rechazadas,
       IIF(Leidas = Insertadas + Rechazadas, 'OK', 'REVISAR') AS Conciliacion
FROM staging.LogCarga ORDER BY LogID;

-- 4.2 Detalle de filas rechazadas / advertencias
SELECT Tabla, Clave, Motivo, Valor FROM staging.Rechazo ORDER BY Tabla, Clave;

-- 4.3 Integridad referencial (todas deben dar 0)
SELECT 'Reservas sin socio'   AS Prueba, COUNT(*) AS Huerfanas FROM operacion.Reserva r LEFT JOIN personas.Socio s ON s.SocioID = r.SocioID WHERE s.SocioID IS NULL
UNION ALL SELECT 'Reservas sin sesion', COUNT(*) FROM operacion.Reserva r LEFT JOIN operacion.Sesion s ON s.SesionID = r.SesionID WHERE s.SesionID IS NULL
UNION ALL SELECT 'Pagos sin suscripcion', COUNT(*) FROM finanzas.Pago p LEFT JOIN finanzas.Suscripcion s ON s.SuscripcionID = p.SuscripcionID WHERE s.SuscripcionID IS NULL;

-- 4.4 Perfilado rápido
SELECT 'Socios' AS Tabla, COUNT(*) AS Filas FROM personas.Socio
UNION ALL SELECT 'Entrenadores', COUNT(*) FROM personas.Entrenador
UNION ALL SELECT 'Sesiones', COUNT(*) FROM operacion.Sesion
UNION ALL SELECT 'Reservas', COUNT(*) FROM operacion.Reserva
UNION ALL SELECT 'Suscripciones', COUNT(*) FROM finanzas.Suscripcion
UNION ALL SELECT 'Pagos', COUNT(*) FROM finanzas.Pago;
GO

-- 4.5 Estadísticas completas tras la carga masiva (mejora los planes de ejecución)
UPDATE STATISTICS operacion.Reserva WITH FULLSCAN;   UPDATE STATISTICS operacion.Sesion WITH FULLSCAN;
UPDATE STATISTICS finanzas.Pago WITH FULLSCAN;       UPDATE STATISTICS finanzas.Suscripcion WITH FULLSCAN;
UPDATE STATISTICS personas.Socio WITH FULLSCAN;
GO

/* Opcional: liberar staging tras validar
   DROP TABLE staging.Socio, staging.Pago, staging.Reserva, staging.Sesion, staging.Suscripcion, staging.Entrenador, staging.Sala, staging.TipoClase, staging.PlanMembresia;
*/
