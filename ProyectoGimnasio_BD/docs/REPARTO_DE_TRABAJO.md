# Reparto de trabajo – 5 integrantes

Cada integrante es **dueño** de un bloque de la rúbrica: escribe su script, su capítulo del informe, sus diapositivas y hace sus commits en su rama. Todos deben poder demostrar y responder preguntas de cualquier bloque (criterio central de la defensa).

| Int. | Rol | Rúbrica | Archivos propios | Cap. informe | Diapositivas |
|---|---|---|---|---|---|
| **1** | Arquitecto de datos + coordinación e integración del informe | Diseño y documentación (5) · coordina Calidad del informe (50) | `sql/01`, `sql/02`, `diagramas/`, `README.md`, `docs/informe` (integración final) | 1, 2, 9 | 1, 2 |
| **2** | Datos y BI | Migración (5) · Dashboard Power BI (15) | `datos/`, `sql/03`, `sql/06`, `powerbi/` | 3, 7 | 8 |
| **3** | Seguridad + montaje de la presentación | Seguridad (5) · Presentación | `sql/04`, `sql/04b`, `presentacion/` | 4 | 3, 4, 12 (parte seguridad) |
| **4** | Rendimiento | Optimización y consultas avanzadas (10) | `sql/05` | 5 | 5, 6, 7, 12 (parte rendimiento) |
| **5** | Continuidad | Backup y recuperación (10) + dimensionamiento | `sql/07`, `sql/08`, `sql/09` | 6 | 9, 10, 11, 12 (parte recuperación) |

**Apoyo cruzado (revisión de PR):** 1→2→3→4→5→1. El revisor ejecuta el script ajeno en su equipo antes de aprobar.
Int. 1 ayuda a Int. 2 con el diseño visual del dashboard (carga alta de Int. 2).

## Dependencias y plan sugerido
| Fase | Qué | Quién |
|---|---|---|
| Día 1–2 | Repo, ramas, `01`, `02`, merge a `develop` | 1 (todos clonan) |
| Día 2–4 | CSV + carga `03` · seguridad `04` · borrador de consultas `05` · jobs `08` | 2, 3, 4, 5 en paralelo |
| Día 4–6 | Índices y mediciones · vistas `06` + Power BI · pruebas `04b` · demo `09` · dimensionamiento `07` | 4, 2, 3, 5 |
| Día 6–8 | Capítulos del informe + capturas · diapositivas | todos |
| Día 8–9 | Integración del informe, revisión cruzada, ensayo de defensa (cada uno demuestra un bloque ajeno) | 1 + todos |
| Día 10 | Tag `v1.0` en `main`, entrega | 1 |

## Commits sugeridos por integrante (mínimo 8 cada uno; mensajes `tipo(área): descripción`)
**Int. 1** · `feat(bd): crear base con filegroups y collation` · `feat(bd): esquemas personas/operacion/finanzas` · `feat(bd): tablas de personas y operación con PK/FK/CHECK` · `feat(bd): tablas de finanzas y auditoría` · `docs(bd): diccionario de datos con extended properties` · `docs: diagrama ER` · `docs(informe): capítulos 1 y 2` · `docs(informe): integración final y revisión de formato`
**Int. 2** · `feat(datos): generador de CSV reproducible` · `feat(etl): tablas staging y BULK INSERT` · `feat(etl): limpieza de socios (initcap, sexo, teléfono)` · `feat(etl): rechazo de pagos inválidos y log de carga` · `test(etl): conciliación e integridad referencial` · `feat(bi): vistas del esquema reportes` · `feat(bi): dashboard .pbix con 3 visuales` · `docs(informe): capítulos 3 y 7`
**Int. 3** · `feat(seg): logins y usuarios` · `feat(seg): roles y permisos por esquema` · `feat(seg): permisos por columna y DENY` · `feat(seg): enmascaramiento dinámico de datos` · `feat(seg): trigger de auditoría DDL` · `test(seg): pruebas de acceso denegado` · `docs(informe): capítulo 4` · `docs(pres): montaje y ensayo de la presentación`
**Int. 4** · `feat(sql): SELECT 1 ocupación por tipo de clase` · `feat(sql): SELECT 2 ingresos por plan` · `feat(sql): SELECT 3 ranking con funciones ventana` · `feat(sql): consultas extra NTILE y NOT EXISTS` · `perf(idx): índices para SELECT 1 y 3` · `perf(idx): índices para SELECT 2, 4 y 5` · `docs(perf): evidencias antes/después` · `docs(informe): capítulo 5`
**Int. 5** · `feat(bkp): procedimiento de respaldo con bitácora` · `feat(bkp): jobs FULL/DIFF/LOG` · `feat(bkp): retención y monitoreo` · `feat(bkp): prueba semanal de restauración` · `feat(sto): dimensionamiento y proyección` · `feat(rec): demo point-in-time con tail-log` · `docs(bkp): análisis RPO/RTO` · `docs(informe): capítulo 6`

## Matriz criterio → evidencia
| Criterio (pts) | Evidencia | Dueño |
|---|---|---|
| Diseño y documentación (5) | ER, diccionario, filegroups | 1 |
| Migración/carga (5) | `staging.LogCarga`, `staging.Rechazo` | 2 |
| Seguridad (5) | Matriz, pruebas `04b`, DDM | 3 |
| Optimización (10) | Planes, lecturas lógicas antes/después | 4 |
| Backup y recuperación (10) | Jobs, historial msdb, demo `09` | 5 |
| Dashboard (15) | `.pbix` + trazabilidad | 2 |
| Presentación e informe (50) | Informe ≤30 págs + defensa | todos (1 integra, 3 monta) |
