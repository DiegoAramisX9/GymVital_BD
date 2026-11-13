# Guía Power BI (Int. 2) – el .pbix debe crearse en Power BI Desktop
1. **Obtener datos → SQL Server**: servidor de su instancia, base `GimnasioDB`, modo **Import**. Credenciales de base de datos: `lg_reportes` / contraseña de `04_seguridad.sql` (demuestra mínimo privilegio).
2. Seleccionar solo `reportes.vw_OcupacionClases`, `reportes.vw_IngresosPorPlan`, `reportes.vw_RankingEntrenadores`. Marcar `Mes` como fecha.
3. Medidas DAX:
```
% Ocupación = DIVIDE(SUM(vw_OcupacionClases[Reservas]), SUM(vw_OcupacionClases[CupoTotal]))
Ingresos = SUM(vw_IngresosPorPlan[Ingresos])
Ticket Promedio = DIVIDE(SUM(vw_IngresosPorPlan[Ingresos]), SUM(vw_IngresosPorPlan[NumPagos]))
```
4. Visuales (trazabilidad):
| Gráfico | Fuente | Configuración |
|---|---|---|
| 1 Barras | SELECT 1 | Eje `TipoClase`, valor `% Ocupación`, orden descendente |
| 2 Columnas apiladas | SELECT 2 | Eje `Mes`, leyenda `PlanNombre`, valor `Ingresos` |
| 3 Líneas | SELECT 3 | Eje `Mes`, leyenda `Entrenador`, valor `Asistencias`, filtro visual `PosicionMes ≤ 5` |
| Extra | — | Segmentador de `Mes`, tarjetas Ingresos y Ticket Promedio |
5. **Validar**: filtrar mayo 2026 en el gráfico 1 y comparar con el resultado de SELECT 1; ene–jun 2026 en gráfico 2 vs SELECT 2.
6. **Demo de actualización**: cambiar un dato en SQL → *Inicio → Actualizar* → el gráfico cambia. Guardar como `powerbi/GymVital.pbix` y tomar capturas para el informe.
