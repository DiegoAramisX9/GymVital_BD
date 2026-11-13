# GymVital – Proyecto de Cátedra: Administración de Bases de Datos (SQL Server 2025)

Sistema de **Reservas de Gimnasio**: socios, entrenadores, clases, reservas, membresías y pagos.

## Orden de ejecución (SSMS, login sysadmin)
| # | Script | Responsable | Rúbrica |
|---|--------|-------------|---------|
| 0 | `python datos/generar_datos.py` y copiar `/datos` a `C:\ProyectoGimnasio\datos\` | Int. 2 | Migración |
| 1 | `sql/01_crear_bd.sql` | Int. 1 | Diseño |
| 2 | `sql/02_esquemas_tablas.sql` | Int. 1 | Diseño |
| 3 | `sql/03_carga_datos.sql` | Int. 2 | Migración |
| 4 | `sql/04_seguridad.sql` | Int. 3 | Seguridad |
| 5 | `sql/05_optimizacion_consultas.sql` (Partes A→B→C→B→D) | Int. 4 | Optimización |
| 6 | `sql/06_vistas_powerbi.sql` | Int. 2 | Dashboard |
| 7 | `sql/04b_pruebas_seguridad.sql` (requiere 06) | Int. 3 | Seguridad |
| 8 | `sql/07_dimensionamiento.sql` | Int. 5 | Backup |
| 9 | `sql/08_backup_jobs.sql` (SQL Server Agent activo) | Int. 5 | Backup |
| 10 | `sql/09_demo_recuperacion.sql` | Int. 5 | Recuperación |

## Estructura
`sql/` scripts · `datos/` CSV + generador · `powerbi/` .pbix y guía · `docs/` informe y reparto · `presentacion/` defensa · `diagramas/` ER.

## Entregables
Informe Word/PDF (máx. 30 págs) · Script .sql · Archivo .pbix (≥3 visualizaciones) · Presentación.
Ver `docs/REPARTO_DE_TRABAJO.md` y `docs/GUIA_GIT.md`.
