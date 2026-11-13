/* =====================================================================
   PROYECTO DE CÁTEDRA - ADMINISTRACIÓN DE BASES DE DATOS (SQL Server 2025)
   Sistema: GymVital - Reservas de Gimnasio
   Archivo : 01_crear_bd.sql
   Responsable: Integrante 1 (Diseño y documentación)
   Objetivo: Diseño FÍSICO: base de datos, filegroups, archivos, collation,
             modelo de recuperación y opciones de la BD.
   Ejecutar: conectado a master, con un login sysadmin.
   ===================================================================== */
USE master;
GO
IF DB_ID(N'GimnasioDB') IS NOT NULL
BEGIN
    ALTER DATABASE GimnasioDB SET SINGLE_USER WITH ROLLBACK IMMEDIATE;
    DROP DATABASE GimnasioDB;
END
GO

/* Rutas por defecto de la instancia (portable entre equipos del grupo) */
DECLARE @data NVARCHAR(260) = CONVERT(NVARCHAR(260), SERVERPROPERTY('InstanceDefaultDataPath'));
DECLARE @log  NVARCHAR(260) = CONVERT(NVARCHAR(260), SERVERPROPERTY('InstanceDefaultLogPath'));

/* Decisión de diseño físico:
   - PRIMARY    : sólo metadatos del sistema (pequeño).
   - FG_DATOS   : tablas (clustered). Será el filegroup POR DEFECTO.
   - FG_INDICES : índices no agrupados -> permite separar E/S en discos distintos.
   - Log        : archivo propio; crecimiento fijo en MB (no en %) para evitar
                  crecimientos cada vez mayores y VLF excesivos. */
DECLARE @sql NVARCHAR(MAX) = N'
CREATE DATABASE GimnasioDB
ON PRIMARY
   (NAME = GimnasioDB_Primary, FILENAME = ''' + @data + N'GimnasioDB_Primary.mdf'', SIZE = 16MB,  FILEGROWTH = 16MB),
FILEGROUP FG_DATOS
   (NAME = GimnasioDB_Datos,   FILENAME = ''' + @data + N'GimnasioDB_Datos.ndf'',   SIZE = 256MB, MAXSIZE = 5GB, FILEGROWTH = 128MB),
FILEGROUP FG_INDICES
   (NAME = GimnasioDB_Indices, FILENAME = ''' + @data + N'GimnasioDB_Indices.ndf'', SIZE = 128MB, MAXSIZE = 2GB, FILEGROWTH = 64MB)
LOG ON
   (NAME = GimnasioDB_Log,     FILENAME = ''' + @log  + N'GimnasioDB_Log.ldf'',     SIZE = 128MB, MAXSIZE = 2GB, FILEGROWTH = 64MB)
COLLATE Modern_Spanish_CI_AI;';
EXEC (@sql);
GO

ALTER DATABASE GimnasioDB MODIFY FILEGROUP FG_DATOS DEFAULT;
ALTER DATABASE GimnasioDB SET RECOVERY FULL;              -- necesario para backups de log y point-in-time
ALTER DATABASE GimnasioDB SET PAGE_VERIFY CHECKSUM;       -- detecta corrupción de páginas
ALTER DATABASE GimnasioDB SET AUTO_UPDATE_STATISTICS ON;
ALTER DATABASE GimnasioDB SET QUERY_STORE = ON;           -- evidencia de rendimiento (Integrante 4)
GO

/* ---- Evidencia para el informe: archivos y filegroups ---- */
USE GimnasioDB;
GO
SELECT fg.name AS Filegroup, fg.is_default AS EsDefault, f.name AS ArchivoLogico, f.physical_name AS RutaFisica,
       f.size*8/1024 AS TamanoMB, f.max_size, f.growth*8/1024 AS CrecimientoMB
FROM sys.database_files f LEFT JOIN sys.filegroups fg ON fg.data_space_id = f.data_space_id;

SELECT name, collation_name, recovery_model_desc, page_verify_option_desc, compatibility_level
FROM sys.databases WHERE name = 'GimnasioDB';
GO

