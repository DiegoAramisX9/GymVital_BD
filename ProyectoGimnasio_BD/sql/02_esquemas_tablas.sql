/* =====================================================================
   Archivo : 02_esquemas_tablas.sql
   Responsable: Integrante 1 (Diseño y documentación)
   Objetivo: Diseño LÓGICO: esquemas, tablas, PK, FK, CHECK, UNIQUE, defaults
             y diccionario de datos (MS_Description).
   NOTA: a propósito NO se crean índices no agrupados aquí (sólo los de PK/UNIQUE).
         El Integrante 4 los crea en 05_optimizacion_consultas.sql para poder
         medir el ANTES y el DESPUÉS.
   ===================================================================== */
USE GimnasioDB;
GO

/* ---------- Esquemas: separan responsabilidades y simplifican permisos ---------- */
CREATE SCHEMA personas   AUTHORIZATION dbo;   -- socios y entrenadores (datos personales)
GO
CREATE SCHEMA operacion  AUTHORIZATION dbo;   -- salas, clases, sesiones y reservas (operación diaria)
GO
CREATE SCHEMA finanzas   AUTHORIZATION dbo;   -- planes, suscripciones, pagos (datos financieros)
GO
CREATE SCHEMA staging    AUTHORIZATION dbo;   -- zona de aterrizaje para la migración/carga
GO
CREATE SCHEMA reportes   AUTHORIZATION dbo;   -- vistas para Power BI (capa semántica de sólo lectura)
GO
CREATE SCHEMA auditoria  AUTHORIZATION dbo;   -- bitácoras de DDL y respaldos
GO

