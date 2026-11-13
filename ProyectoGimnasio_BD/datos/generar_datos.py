#!/usr/bin/env python3
"""
Generador de datos sintéticos - GimnasioDB   (Responsable: Integrante 2)
Produce los CSV que consume sql/03_carga_datos.sql (BULK INSERT).
Semilla fija => resultados reproducibles.   Uso:  python generar_datos.py
Incluye "suciedad" controlada en socios.csv y pagos.csv para demostrar la
limpieza/validación del proceso de migración (ETL).
"""
import csv, random, os
from datetime import date, datetime, timedelta

random.seed(2026)
OUT = os.path.dirname(os.path.abspath(__file__))
N_SOCIOS = 6000
INI, FIN = date(2024, 7, 1), date(2026, 6, 30)


def w(nombre, cab, filas):
    with open(os.path.join(OUT, nombre), "w", newline="", encoding="utf-8") as f:
        wr = csv.writer(f, lineterminator="\n")
        wr.writerow(cab)
        wr.writerows(filas)
    print(f"{nombre:<22}{len(filas):>9} filas")


def quitar_tildes(s):
    for x, y in zip("áéíóúÁÉÍÓÚñÑ", "aeiouAEIOUnN"):
        s = s.replace(x, y)
    return s


def add_months(d, m):
    y, mm = divmod(d.month - 1 + m, 12)
    return date(d.year + y, mm + 1, 1)


NOMBRES = ["José", "Carlos", "Luis", "Miguel", "Juan", "Kevin", "Walter", "Mauricio", "Roberto", "Fernando",
           "Oscar", "Jorge", "Diego", "Andrés", "Mario", "María", "Ana", "Carmen", "Sofía", "Daniela",
           "Karla", "Gabriela", "Lucía", "Patricia", "Verónica", "Alejandra", "Claudia", "Wendy", "Ingrid", "Rosa"]
APELLIDOS = ["Hernández", "Martínez", "López", "García", "Rodríguez", "Pérez", "Gómez", "Flores", "Ramírez", "Cruz",
             "Rivera", "Mejía", "Villalta", "Alvarado", "Escobar", "Portillo", "Guzmán", "Menjívar", "Aguilar",
             "Cárcamo", "Quintanilla", "Ortiz", "Castillo", "Reyes", "Molina", "Chávez", "Calderón", "Rauda"]

# ------------------------------------------------------------------ catálogos
planes = [(1, "Básico Mensual", "25.00", 1, "Acceso a sala de pesas"),
          (2, "Estándar Mensual", "40.00", 1, "Sala + clases grupales"),
          (3, "Premium Mensual", "60.00", 1, "Todo incluido + entrenador"),
          (4, "Estándar Trimestral", "108.00", 3, "Sala + clases, 10% descuento")]
w("planes.csv", ["plan_id", "nombre", "precio", "duracion_meses", "descripcion"], planes)

tipos = [(1, "Yoga", 60, "Baja"), (2, "Spinning", 45, "Media"), (3, "Zumba", 50, "Media"), (4, "CrossFit", 60, "Alta"),
         (5, "Pilates", 55, "Baja"), (6, "Funcional", 45, "Media"), (7, "Boxeo", 60, "Alta"), (8, "HIIT", 30, "Alta"),
         (9, "Stretching", 40, "Baja"), (10, "GAP", 45, "Media"), (11, "Baile Latino", 50, "Media"),
         (12, "Movilidad", 40, "Baja")]
w("tipos_clase.csv", ["tipo_clase_id", "nombre", "duracion_min", "intensidad"], tipos)

salas = [(1, "Sala Spinning", 30), (2, "Sala Funcional", 25), (3, "Estudio Yoga", 20),
         (4, "Sala Baile", 40), (5, "Box Zone", 20), (6, "Sala Multiuso", 15)]
w("salas.csv", ["sala_id", "nombre", "capacidad"], salas)

espec = ["Yoga", "Spinning", "Zumba", "CrossFit", "Pilates", "Funcional", "Boxeo", "HIIT"]
entren = []
for i in range(1, 21):
    n, a = random.choice(NOMBRES), random.choice(APELLIDOS) + " " + random.choice(APELLIDOS)
    mail = quitar_tildes(f"{n}.{a.split()[0]}{i}@gymvital.sv").lower()
    entren.append((i, n, a, mail, random.choice(espec),
                   (date(2021, 1, 1) + timedelta(days=random.randint(0, 1200))).isoformat(), 1))
w("entrenadores.csv", ["entrenador_id", "nombres", "apellidos", "email", "especialidad", "fecha_contratacion", "activo"],
  entren)

# ------------------------------------------------------ socios, suscripciones, pagos
socios, susc, pagos = [], [], []
susc_id = pago_id = 0
activo_en = {}  # (año, mes) -> [socio_id]  (para generar reservas coherentes)
PESOS_PLAN = [0.30, 0.38, 0.17, 0.15]

for sid in range(1, N_SOCIOS + 1):
    mes_alta = int((random.random() ** 1.4) * 23)
    alta = add_months(INI, mes_alta) + timedelta(days=random.randint(0, 27))
    n, a = random.choice(NOMBRES), random.choice(APELLIDOS) + " " + random.choice(APELLIDOS)
    nac_txt = (date(1960, 1, 1) + timedelta(days=random.randint(0, 365 * 42))).isoformat()
    sexo = random.choice(["M", "F"])
    email = quitar_tildes(f"{n}.{a.split()[0]}{sid}@correo.com").lower()
    tel = f"{random.choice([6, 7])}{random.randint(100, 999)}-{random.randint(1000, 9999)}"

    # ---- suciedad controlada (se corrige / registra en la carga) ----
    r = random.random()
    if r < 0.02:
        n, a, email = "  " + n.upper() + " ", a.upper() + "  ", email.upper()   # espacios y mayúsculas
    elif r < 0.03:
        sexo = random.choice(["masculino", "Femenino", "m", "f"])                  # sexo sin normalizar
    elif r < 0.04:
        tel = ""                                                                   # teléfono vacío
    elif r < 0.045:
        nac_txt = "31/02/1990"                                                     # fecha imposible

    meses_posibles = (FIN.year - alta.year) * 12 + FIN.month - alta.month + 1
    meses = min(meses_posibles, max(1, int(random.expovariate(1 / 9)) + 1))
    estado = "Inactivo" if (alta.year * 12 + alta.month - 1 + meses <= FIN.year * 12 + FIN.month - 1) else "Activo"
    socios.append((sid, n, a, email, tel, nac_txt, sexo, alta.isoformat(), estado))

    plan = random.choices([1, 2, 3, 4], PESOS_PLAN)[0]
    pasos = 3 if plan == 4 else 1
    m = 0
    while m < meses:
        ini = add_months(alta, m)
        fin = add_months(ini, pasos) - timedelta(days=1)
        susc_id += 1
        susc.append((susc_id, sid, plan, ini.isoformat(), fin.isoformat(), "Vigente" if fin >= FIN else "Vencida"))
        precio = float(planes[plan - 1][2])
        est = random.choices(["Pagado", "Pendiente", "Rechazado"], [0.94, 0.04, 0.02])[0]
        monto = f"{precio:.2f}"
        x = random.random()
        if x < 0.0008:
            monto = f"-{precio:.2f}"       # suciedad: monto negativo -> se rechaza
        elif x < 0.0014:
            monto = "N/D"                  # suciedad: monto no numérico -> se rechaza
        pago_id += 1
        pagos.append((pago_id, susc_id, (ini + timedelta(days=random.randint(0, 3))).isoformat(), monto,
                      random.choices(["Tarjeta", "Efectivo", "Transferencia"], [0.5, 0.3, 0.2])[0], est))
        for k in range(pasos):
            mm = add_months(ini, k)
            if mm <= FIN:
                activo_en.setdefault((mm.year, mm.month), []).append(sid)
        m += pasos
        if random.random() < 0.08:  # a veces cambia de plan al renovar
            plan = random.choices([1, 2, 3, 4], PESOS_PLAN)[0]
            pasos = 3 if plan == 4 else 1

w("socios.csv", ["socio_id", "nombres", "apellidos", "email", "telefono", "fecha_nacimiento", "sexo",
                 "fecha_registro", "estado"], socios)
w("suscripciones.csv", ["suscripcion_id", "socio_id", "plan_id", "fecha_inicio", "fecha_fin", "estado"], susc)
w("pagos.csv", ["pago_id", "suscripcion_id", "fecha_pago", "monto", "metodo_pago", "estado"], pagos)

# ------------------------------------------------------------ sesiones y reservas
horas = [6, 7, 8, 9, 10, 11, 12, 16, 17, 18, 19, 20]
sesiones, reservas = [], []
ses_id = res_id = 0
d = INI
while d <= FIN:
    if d.weekday() != 6:  # lunes a sábado
        for h in sorted(random.sample(horas, 11)):
            sala, tipo = random.choice(salas), random.choice(tipos)
            ses_id += 1
            ini = datetime(d.year, d.month, d.day, h, 0)
            fin = ini + timedelta(minutes=tipo[2])
            cupo = sala[2]
            sesiones.append((ses_id, tipo[0], random.randint(1, 20), sala[0],
                             ini.isoformat(sep=" "), fin.isoformat(sep=" "), cupo))
            pool = activo_en.get((d.year, d.month), [])
            n = min(len(pool), round(cupo * random.uniform(0.45, 0.98)))
            for sid in random.sample(pool, n):
                res_id += 1
                est = random.choices(["Asistio", "NoAsistio", "Cancelada"], [0.68, 0.15, 0.17])[0]
                fr = ini - timedelta(hours=random.randint(1, 72), minutes=random.randint(0, 59))
                reservas.append((res_id, ses_id, sid, fr.isoformat(sep=" "), est))
    d += timedelta(days=1)
w("sesiones.csv", ["sesion_id", "tipo_clase_id", "entrenador_id", "sala_id", "fecha_hora_inicio",
                   "fecha_hora_fin", "cupo_maximo"], sesiones)
w("reservas.csv", ["reserva_id", "sesion_id", "socio_id", "fecha_reserva", "estado"], reservas)
