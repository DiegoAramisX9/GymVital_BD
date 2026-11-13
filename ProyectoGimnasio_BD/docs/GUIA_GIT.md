# Guía Git para el equipo
**Ramas:** `main` (entrega) ← `develop` (integración) ← `feature/int1-diseno`, `feature/int2-datos-bi`, `feature/int3-seguridad`, `feature/int4-optimizacion`, `feature/int5-backup`.

## Int. 1 (una sola vez)
```bash
git init && git add . && git commit -m "chore: estructura inicial del proyecto"
git branch -M main && git remote add origin <URL> && git push -u origin main
git checkout -b develop && git push -u origin develop
```
## Cada integrante
```bash
git clone <URL> && cd ProyectoGimnasio_BD
git checkout develop && git pull
git checkout -b feature/intN-<tema>          # tu rama
# ... trabaja un archivo/paso, prueba en SQL Server ...
git add sql/05_optimizacion_consultas.sql
git commit -m "feat(sql): SELECT 1 ocupación por tipo de clase"
git push -u origin feature/intN-<tema>       # abrir Pull Request hacia develop
```
**Reglas:** commits pequeños (un paso lógico), no subir a `main`, PR revisado por otro integrante (ver rotación), `git pull --rebase origin develop` antes de abrir PR, nunca subir `.bak/.mdf` ni contraseñas reales.
Tipos: `feat`, `fix`, `perf`, `test`, `docs`, `chore`. Para el informe: `git shortlog -sn` demuestra la contribución de cada uno.
**Entrega:** Int. 1 hace PR `develop → main` y `git tag v1.0`.
