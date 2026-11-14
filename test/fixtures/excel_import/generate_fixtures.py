"""Regenerate the entirely fictional Excel fixtures (xlwt and openpyxl)."""

from pathlib import Path

import xlwt
from openpyxl import Workbook


ROOT = Path(__file__).resolve().parent
HEADERS = [
    "PROGRAMA",
    "CODIGOESTUDIANTE",
    "FECHAMATRICULA",
    "MAIL_INST",
    "DOCUMENTO",
    "NOMBRECOMPLETO",
    "PENG_IDENTITARIO",
    "TELEFONO",
    "EPS",
]

book = xlwt.Workbook()
sheet = book.add_sheet("Movil ficticio")
for col, header in enumerate(HEADERS):
    sheet.write(0, col, header)
for number in range(1, 36):
    values = [
        "Programa ficticio",
        2000000000 + number,
        "2026-11-01",
        f"alumno{number:02d}@example.invalid",
        f"DOC-FICTICIO-{number:02d}",
        f"Estudiante Ficticio {number:02d}",
        "FICTICIO",
        "0000000000",
        "EPS FICTICIA",
    ]
    for col, value in enumerate(values):
        sheet.write(number, col, value)
book.save(str(ROOT / "estudiantes_ficticios_35.xls"))

workbook = Workbook()
mixed = workbook.active
mixed.title = "Grupo ficticio A"
mixed_headers = [
    "NOMBRECOMPLETO",
    "MAIL_INST",
    "CODIGOESTUDIANTE",
    "DOCUMENTO",
    "EPS",
    "PROGRAMA",
    "FECHAMATRICULA",
    "PENG_IDENTITARIO",
    "TELEFONO",
]
mixed.append(mixed_headers)
mixed.append(["Persona Ficticia A", "a@example.invalid", "0000000123"])
mixed.append(["Persona Ficticia B", "b@example.invalid", 1234])
mixed["C3"].number_format = "0000000000"
mixed.append(["Persona Ficticia C", "c@example.invalid", 2000000003])
mixed.append([None] * len(mixed_headers))
mixed.append(["Persona Incompleta", "", "0000000456"])
other = workbook.create_sheet("Grupo ficticio B")
other.append(HEADERS)
other.append([
    "Programa ficticio", 2000000042, "", "otro@example.invalid", "",
    "Persona Ficticia D", "", "", "",
])
workbook.save(ROOT / "estudiantes_ficticios_mixtos.xlsx")
