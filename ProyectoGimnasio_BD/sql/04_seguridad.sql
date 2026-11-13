/* =====================================================================
   Archivo : 04_seguridad.sql
   Responsable: Integrante 3 (Seguridad)
   Objetivo: Logins, usuarios, roles, GRANT/DENY, mínimo privilegio,
             enmascaramiento dinámico de datos y auditoría de DDL.
   Requisito: autenticación MIXTA en la instancia (SQL + Windows) para los logins SQL.
   IMPORTANTE: las contraseñas de abajo son de ejemplo para el entorno académico;
               en producción se guardan en un gestor de secretos.
   ===================================================================== */
USE master;
GO
/* ---------- 1. LOGINS (nivel servidor) ---------- */
IF SUSER_ID('lg_recepcion') IS NULL CREATE LOGIN lg_recepcion WITH PASSWORD = N'Gym#Recep2026!', CHECK_POLICY = ON, CHECK_EXPIRATION = OFF, DEFAULT_DATABASE = GimnasioDB;
IF SUSER_ID('lg_entrenador') IS NULL CREATE LOGIN lg_entrenador WITH PASSWORD = N'Gym#Entre2026!', CHECK_POLICY = ON, CHECK_EXPIRATION = OFF, DEFAULT_DATABASE = GimnasioDB;
IF SUSER_ID('lg_finanzas')  IS NULL CREATE LOGIN lg_finanzas  WITH PASSWORD = N'Gym#Finan2026!', CHECK_POLICY = ON, CHECK_EXPIRATION = OFF, DEFAULT_DATABASE = GimnasioDB;
IF SUSER_ID('lg_reportes')  IS NULL CREATE LOGIN lg_reportes  WITH PASSWORD = N'Gym#Repor2026!', CHECK_POLICY = ON, CHECK_EXPIRATION = OFF, DEFAULT_DATABASE = GimnasioDB;
IF SUSER_ID('lg_admin_bd')  IS NULL CREATE LOGIN lg_admin_bd  WITH PASSWORD = N'Gym#Admin2026!', CHECK_POLICY = ON, CHECK_EXPIRATION = OFF, DEFAULT_DATABASE = GimnasioDB;
GO

USE GimnasioDB;
GO
/* ---------- 2. USUARIOS (nivel base de datos) ---------- */
CREATE USER usr_recepcion FOR LOGIN lg_recepcion;
CREATE USER usr_entrenador FOR LOGIN lg_entrenador;
CREATE USER usr_finanzas  FOR LOGIN lg_finanzas;
CREATE USER usr_reportes  FOR LOGIN lg_reportes;      -- cuenta de servicio de Power BI
CREATE USER usr_admin_bd  FOR LOGIN lg_admin_bd;
GO

/* ---------- 3. ROLES: los permisos se asignan a ROLES, nunca a usuarios sueltos ---------- */
CREATE ROLE rol_recepcion;
CREATE ROLE rol_entrenador;
CREATE ROLE rol_finanzas;
CREATE ROLE rol_reportes;
GO
ALTER ROLE rol_recepcion  ADD MEMBER usr_recepcion;
ALTER ROLE rol_entrenador ADD MEMBER usr_entrenador;
ALTER ROLE rol_finanzas   ADD MEMBER usr_finanzas;
ALTER ROLE rol_reportes   ADD MEMBER usr_reportes;
ALTER ROLE db_owner       ADD MEMBER usr_admin_bd;    -- administrador del proyecto (no se usa 'sa')
GO

/* ---------- 4. PERMISOS (principio de MÍNIMO PRIVILEGIO) ---------- */
/* 4.1 RECEPCIÓN: atiende socios, gestiona reservas y registra cobros. Nunca borra. */
GRANT SELECT, INSERT, UPDATE ON SCHEMA::personas  TO rol_recepcion;
DENY  DELETE                 ON SCHEMA::personas  TO rol_recepcion;
GRANT SELECT                 ON SCHEMA::operacion TO rol_recepcion;
GRANT INSERT, UPDATE         ON operacion.Reserva TO rol_recepcion;
DENY  DELETE                 ON SCHEMA::operacion TO rol_recepcion;
GRANT SELECT                 ON SCHEMA::finanzas  TO rol_recepcion;
GRANT INSERT                 ON finanzas.Pago         TO rol_recepcion;
GRANT INSERT                 ON finanzas.Suscripcion  TO rol_recepcion;
DENY  UPDATE, DELETE         ON SCHEMA::finanzas  TO rol_recepcion;
GRANT UNMASK TO rol_recepcion;                         -- ve email/teléfono reales para contactar al socio

/* 4.2 ENTRENADOR: consulta su agenda y marca asistencia; ve SÓLO columnas no sensibles del socio. */
GRANT SELECT ON SCHEMA::operacion TO rol_entrenador;
GRANT UPDATE (Estado) ON operacion.Reserva TO rol_entrenador;     -- permiso a nivel de COLUMNA
GRANT SELECT (SocioID, Nombres, Apellidos, Estado) ON personas.Socio TO rol_entrenador;
GRANT SELECT ON personas.Entrenador TO rol_entrenador;
DENY  SELECT, INSERT, UPDATE, DELETE ON SCHEMA::finanzas TO rol_entrenador;   -- sin acceso a dinero
DENY  DELETE ON SCHEMA::operacion TO rol_entrenador;

/* 4.3 FINANZAS: gestiona cobros. Ve al socio pero con email/teléfono ENMASCARADOS (sin UNMASK). */
GRANT SELECT, INSERT, UPDATE ON SCHEMA::finanzas TO rol_finanzas;
DENY  DELETE                 ON SCHEMA::finanzas TO rol_finanzas;
GRANT SELECT ON personas.Socio TO rol_finanzas;
DENY  SELECT, INSERT, UPDATE, DELETE ON SCHEMA::operacion TO rol_finanzas;

/* 4.4 REPORTES (Power BI): SÓLO lectura sobre el esquema 'reportes' (vistas).
       Las vistas funcionan gracias al ENCADENAMIENTO DE PROPIEDAD (mismo dueño dbo),
       por eso NO se necesita ningún permiso sobre las tablas base. */
GRANT SELECT ON SCHEMA::reportes TO rol_reportes;
DENY  SELECT, INSERT, UPDATE, DELETE ON SCHEMA::personas  TO rol_reportes;
DENY  SELECT, INSERT, UPDATE, DELETE ON SCHEMA::operacion TO rol_reportes;
DENY  SELECT, INSERT, UPDATE, DELETE ON SCHEMA::finanzas  TO rol_reportes;
DENY  SELECT, INSERT, UPDATE, DELETE ON SCHEMA::staging   TO rol_reportes;
GO

/* ---------- 5. ENMASCARAMIENTO DINÁMICO DE DATOS (datos personales) ---------- */
ALTER TABLE personas.Socio ALTER COLUMN Email    ADD MASKED WITH (FUNCTION = 'email()');
ALTER TABLE personas.Socio ALTER COLUMN Telefono ADD MASKED WITH (FUNCTION = 'partial(0,"****-",4)');
GO

/* ---------- 6. AUDITORÍA DE CAMBIOS DDL (quién creó/alteró/borró objetos) ---------- */
CREATE OR ALTER TRIGGER trg_AuditarDDL ON DATABASE FOR DDL_DATABASE_LEVEL_EVENTS
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @e XML = EVENTDATA();
    INSERT auditoria.BitacoraDDL (Usuario, Evento, Objeto, Sentencia)
    VALUES (ORIGINAL_LOGIN(),
            @e.value('(/EVENT_INSTANCE/EventType)[1]',  'NVARCHAR(100)'),
            @e.value('(/EVENT_INSTANCE/SchemaName)[1]', 'NVARCHAR(100)') + N'.' + @e.value('(/EVENT_INSTANCE/ObjectName)[1]', 'NVARCHAR(200)'),
            @e.value('(/EVENT_INSTANCE/TSQLCommand/CommandText)[1]', 'NVARCHAR(MAX)'));
END
GO
GRANT SELECT ON SCHEMA::auditoria TO usr_admin_bd;   -- (db_owner ya lo tiene; se deja explícito para la matriz)
GO

/* ---------- 7. EVIDENCIA PARA EL INFORME: matriz de privilegios real ---------- */
-- 7.1 Pertenencia a roles
SELECT r.name AS Rol, m.name AS Usuario
FROM sys.database_role_members rm
JOIN sys.database_principals r ON r.principal_id = rm.role_principal_id
JOIN sys.database_principals m ON m.principal_id = rm.member_principal_id
WHERE r.name LIKE 'rol_%' OR r.name = 'db_owner'
ORDER BY r.name;

-- 7.2 Permisos efectivos declarados (GRANT/DENY) por rol
SELECT pr.name AS Rol, dp.state_desc AS Estado, dp.permission_name AS Permiso, dp.class_desc AS Clase,
       CASE dp.class WHEN 3 THEN SCHEMA_NAME(dp.major_id)
                     WHEN 1 THEN OBJECT_SCHEMA_NAME(dp.major_id) + '.' + OBJECT_NAME(dp.major_id) END AS Objeto,
       COL_NAME(dp.major_id, NULLIF(dp.minor_id, 0)) AS Columna
FROM sys.database_permissions dp
JOIN sys.database_principals pr ON pr.principal_id = dp.grantee_principal_id
WHERE pr.name LIKE 'rol_%'
ORDER BY pr.name, Objeto, dp.permission_name;
GO
