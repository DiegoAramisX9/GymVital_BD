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

/* ---------- PERSONAS ---------- */
CREATE TABLE personas.Socio (
    SocioID          INT IDENTITY(1,1) NOT NULL,
    Nombres          NVARCHAR(80)  NOT NULL,
    Apellidos        NVARCHAR(80)  NOT NULL,
    Email            NVARCHAR(120) NOT NULL,
    Telefono         VARCHAR(20)   NULL,
    FechaNacimiento  DATE          NULL,
    Sexo             CHAR(1)       NULL,
    FechaRegistro    DATE          NOT NULL CONSTRAINT DF_Socio_FechaRegistro DEFAULT (CONVERT(date, GETDATE())),
    Estado           VARCHAR(10)   NOT NULL CONSTRAINT DF_Socio_Estado DEFAULT ('Activo'),
    CONSTRAINT PK_Socio PRIMARY KEY CLUSTERED (SocioID),
    CONSTRAINT UQ_Socio_Email UNIQUE (Email),
    CONSTRAINT CK_Socio_Sexo   CHECK (Sexo IN ('M','F')),
    CONSTRAINT CK_Socio_Estado CHECK (Estado IN ('Activo','Inactivo','Suspendido'))
);
GO
CREATE TABLE personas.Entrenador (
    EntrenadorID      INT IDENTITY(1,1) NOT NULL,
    Nombres           NVARCHAR(80)  NOT NULL,
    Apellidos         NVARCHAR(80)  NOT NULL,
    Email             NVARCHAR(120) NOT NULL,
    Especialidad      NVARCHAR(40)  NOT NULL,
    FechaContratacion DATE          NOT NULL,
    Activo            BIT           NOT NULL CONSTRAINT DF_Entrenador_Activo DEFAULT (1),
    CONSTRAINT PK_Entrenador PRIMARY KEY CLUSTERED (EntrenadorID),
    CONSTRAINT UQ_Entrenador_Email UNIQUE (Email)
);
GO

/* ---------- OPERACIÓN ---------- */
CREATE TABLE operacion.Sala (
    SalaID    INT IDENTITY(1,1) NOT NULL,
    Nombre    NVARCHAR(50) NOT NULL,
    Capacidad SMALLINT     NOT NULL,
    CONSTRAINT PK_Sala PRIMARY KEY CLUSTERED (SalaID),
    CONSTRAINT UQ_Sala_Nombre UNIQUE (Nombre),
    CONSTRAINT CK_Sala_Capacidad CHECK (Capacidad > 0)
);
CREATE TABLE operacion.TipoClase (
    TipoClaseID  INT IDENTITY(1,1) NOT NULL,
    Nombre       NVARCHAR(50) NOT NULL,
    DuracionMin  SMALLINT     NOT NULL,
    Intensidad   VARCHAR(10)  NOT NULL,
    CONSTRAINT PK_TipoClase PRIMARY KEY CLUSTERED (TipoClaseID),
    CONSTRAINT UQ_TipoClase_Nombre UNIQUE (Nombre),
    CONSTRAINT CK_TipoClase_Duracion CHECK (DuracionMin BETWEEN 10 AND 180),
    CONSTRAINT CK_TipoClase_Intensidad CHECK (Intensidad IN ('Baja','Media','Alta'))
);
CREATE TABLE operacion.Sesion (
    SesionID         INT IDENTITY(1,1) NOT NULL,
    TipoClaseID      INT       NOT NULL,
    EntrenadorID     INT       NOT NULL,
    SalaID           INT       NOT NULL,
    FechaHoraInicio  DATETIME2(0) NOT NULL,
    FechaHoraFin     DATETIME2(0) NOT NULL,
    CupoMaximo       SMALLINT  NOT NULL,
    CONSTRAINT PK_Sesion PRIMARY KEY CLUSTERED (SesionID),
    CONSTRAINT FK_Sesion_TipoClase  FOREIGN KEY (TipoClaseID)  REFERENCES operacion.TipoClase(TipoClaseID),
    CONSTRAINT FK_Sesion_Entrenador FOREIGN KEY (EntrenadorID) REFERENCES personas.Entrenador(EntrenadorID),
    CONSTRAINT FK_Sesion_Sala       FOREIGN KEY (SalaID)       REFERENCES operacion.Sala(SalaID),
    CONSTRAINT CK_Sesion_Horario CHECK (FechaHoraFin > FechaHoraInicio),
    CONSTRAINT CK_Sesion_Cupo    CHECK (CupoMaximo > 0)
);
CREATE TABLE operacion.Reserva (
    ReservaID     BIGINT IDENTITY(1,1) NOT NULL,
    SesionID      INT          NOT NULL,
    SocioID       INT          NOT NULL,
    FechaReserva  DATETIME2(0) NOT NULL CONSTRAINT DF_Reserva_Fecha DEFAULT (SYSDATETIME()),
    Estado        VARCHAR(12)  NOT NULL CONSTRAINT DF_Reserva_Estado DEFAULT ('Confirmada'),
    CONSTRAINT PK_Reserva PRIMARY KEY CLUSTERED (ReservaID),
    CONSTRAINT FK_Reserva_Sesion FOREIGN KEY (SesionID) REFERENCES operacion.Sesion(SesionID),
    CONSTRAINT FK_Reserva_Socio  FOREIGN KEY (SocioID)  REFERENCES personas.Socio(SocioID),
    CONSTRAINT CK_Reserva_Estado CHECK (Estado IN ('Confirmada','Cancelada','Asistio','NoAsistio'))
);
GO

