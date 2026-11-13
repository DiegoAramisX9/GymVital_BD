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

/* ---------- FINANZAS ---------- */
CREATE TABLE finanzas.PlanMembresia (
    PlanID         INT IDENTITY(1,1) NOT NULL,
    Nombre         NVARCHAR(50)  NOT NULL,
    Precio         DECIMAL(8,2)  NOT NULL,
    DuracionMeses  TINYINT       NOT NULL,
    Descripcion    NVARCHAR(150) NULL,
    CONSTRAINT PK_PlanMembresia PRIMARY KEY CLUSTERED (PlanID),
    CONSTRAINT UQ_PlanMembresia_Nombre UNIQUE (Nombre),
    CONSTRAINT CK_Plan_Precio CHECK (Precio > 0)
);
CREATE TABLE finanzas.Suscripcion (
    SuscripcionID INT IDENTITY(1,1) NOT NULL,
    SocioID       INT         NOT NULL,
    PlanID        INT         NOT NULL,
    FechaInicio   DATE        NOT NULL,
    FechaFin      DATE        NOT NULL,
    Estado        VARCHAR(10) NOT NULL,
    CONSTRAINT PK_Suscripcion PRIMARY KEY CLUSTERED (SuscripcionID),
    CONSTRAINT FK_Suscripcion_Socio FOREIGN KEY (SocioID) REFERENCES personas.Socio(SocioID),
    CONSTRAINT FK_Suscripcion_Plan  FOREIGN KEY (PlanID)  REFERENCES finanzas.PlanMembresia(PlanID),
    CONSTRAINT CK_Suscripcion_Fechas CHECK (FechaFin >= FechaInicio),
    CONSTRAINT CK_Suscripcion_Estado CHECK (Estado IN ('Vigente','Vencida','Cancelada'))
);
CREATE TABLE finanzas.Pago (
    PagoID        BIGINT IDENTITY(1,1) NOT NULL,
    SuscripcionID INT          NOT NULL,
    FechaPago     DATE         NOT NULL,
    Monto         DECIMAL(10,2) NOT NULL,
    MetodoPago    VARCHAR(15)  NOT NULL,
    Estado        VARCHAR(10)  NOT NULL,
    CONSTRAINT PK_Pago PRIMARY KEY CLUSTERED (PagoID),
    CONSTRAINT FK_Pago_Suscripcion FOREIGN KEY (SuscripcionID) REFERENCES finanzas.Suscripcion(SuscripcionID),
    CONSTRAINT CK_Pago_Monto  CHECK (Monto > 0),
    CONSTRAINT CK_Pago_Metodo CHECK (MetodoPago IN ('Tarjeta','Efectivo','Transferencia')),
    CONSTRAINT CK_Pago_Estado CHECK (Estado IN ('Pagado','Pendiente','Rechazado'))
);
GO

/* ---------- AUDITORÍA (la usan los Integrantes 3 y 5) ---------- */
CREATE TABLE auditoria.BitacoraDDL (
    BitacoraID  INT IDENTITY(1,1) PRIMARY KEY,
    FechaHora   DATETIME2(0) NOT NULL DEFAULT SYSDATETIME(),
    Usuario     SYSNAME      NOT NULL DEFAULT ORIGINAL_LOGIN(),
    Evento      NVARCHAR(100) NULL,
    Objeto      NVARCHAR(300) NULL,
    Sentencia   NVARCHAR(MAX) NULL
);
CREATE TABLE auditoria.BitacoraBackup (
    BitacoraID  INT IDENTITY(1,1) PRIMARY KEY,
    Tipo        VARCHAR(10)   NOT NULL,
    Archivo     NVARCHAR(400) NULL,
    Inicio      DATETIME2(0)  NOT NULL,
    Fin         DATETIME2(0)  NULL,
    Resultado   VARCHAR(10)   NOT NULL,
    TamanoMB    DECIMAL(12,2) NULL,
    Mensaje     NVARCHAR(2000) NULL
);
GO

/* ---------- DICCIONARIO DE DATOS (extended properties) ---------- */
EXEC sys.sp_addextendedproperty N'MS_Description', N'Clientes inscritos en el gimnasio (datos personales)', N'SCHEMA', N'personas',  N'TABLE', N'Socio';
EXEC sys.sp_addextendedproperty N'MS_Description', N'Instructores que imparten las clases',                  N'SCHEMA', N'personas',  N'TABLE', N'Entrenador';
EXEC sys.sp_addextendedproperty N'MS_Description', N'Espacios físicos donde se imparten clases',             N'SCHEMA', N'operacion', N'TABLE', N'Sala';
EXEC sys.sp_addextendedproperty N'MS_Description', N'Catálogo de disciplinas (Yoga, Spinning, ...)',          N'SCHEMA', N'operacion', N'TABLE', N'TipoClase';
EXEC sys.sp_addextendedproperty N'MS_Description', N'Clase programada: tipo + entrenador + sala + horario',   N'SCHEMA', N'operacion', N'TABLE', N'Sesion';
EXEC sys.sp_addextendedproperty N'MS_Description', N'Reserva de un socio en una sesión (y su asistencia)',    N'SCHEMA', N'operacion', N'TABLE', N'Reserva';
EXEC sys.sp_addextendedproperty N'MS_Description', N'Planes de membresía y su precio',                        N'SCHEMA', N'finanzas',  N'TABLE', N'PlanMembresia';
EXEC sys.sp_addextendedproperty N'MS_Description', N'Periodo contratado por un socio con un plan',            N'SCHEMA', N'finanzas',  N'TABLE', N'Suscripcion';
EXEC sys.sp_addextendedproperty N'MS_Description', N'Cobros asociados a una suscripción',                     N'SCHEMA', N'finanzas',  N'TABLE', N'Pago';
EXEC sys.sp_addextendedproperty N'MS_Description', N'Valores: Confirmada | Cancelada | Asistio | NoAsistio',  N'SCHEMA', N'operacion', N'TABLE', N'Reserva', N'COLUMN', N'Estado';
EXEC sys.sp_addextendedproperty N'MS_Description', N'Valores: Pagado | Pendiente | Rechazado',                 N'SCHEMA', N'finanzas',  N'TABLE', N'Pago',    N'COLUMN', N'Estado';
GO

/* ---------- Evidencia para el informe: diccionario de datos ---------- */
SELECT s.name AS Esquema, t.name AS Tabla, c.column_id AS Nro, c.name AS Columna,
       ty.name + CASE WHEN ty.name LIKE '%char%' THEN '(' + CASE c.max_length WHEN -1 THEN 'MAX' ELSE CAST(c.max_length / CASE WHEN ty.name LIKE 'n%' THEN 2 ELSE 1 END AS VARCHAR(5)) END + ')' ELSE '' END AS Tipo,
       IIF(c.is_nullable = 1, 'Sí', 'No') AS Nulo, CAST(ep.value AS NVARCHAR(200)) AS Descripcion
FROM sys.tables t
JOIN sys.schemas s ON s.schema_id = t.schema_id
JOIN sys.columns c ON c.object_id = t.object_id
JOIN sys.types ty ON ty.user_type_id = c.user_type_id
LEFT JOIN sys.extended_properties ep ON ep.major_id = t.object_id AND ep.minor_id = c.column_id AND ep.name = 'MS_Description'
WHERE s.name IN ('personas','operacion','finanzas')
ORDER BY s.name, t.name, c.column_id;
GO
