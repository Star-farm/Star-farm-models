"""Convert rapport_complet.md -> .pdf (synthesis Pareto figure embedded)."""
import os
import re

import markdown
from xhtml2pdf import pisa

HERE = os.path.dirname(os.path.abspath(__file__))
MD = os.path.join(HERE, "rapport_complet.md")
PDF = os.path.join(HERE, "rapport_complet.pdf")

text = open(MD, encoding="utf-8").read()
for a, b in {"→": "->", "×": "x", "·": "-", "≈": "~", "λ": "lambda", "γ": "gamma",
             "—": "-", "–": "-", "’": "'", "≥": ">=", "≤": "<="}.items():
    text = text.replace(a, b)

html_body = markdown.markdown(text, extensions=["tables", "fenced_code", "sane_lists"])
html_body = re.sub(r'src="([^"]+\.png)"',
                   lambda m: f'src="{os.path.normpath(os.path.join(HERE, m.group(1)))}"', html_body)

CSS = """
@page { size: A4; margin: 1.8cm 1.6cm; }
body { font-family: Helvetica, Arial, sans-serif; font-size: 9.5pt; line-height: 1.4; color: #1a1a1a; }
h1 { font-size: 16pt; color: #111; border-bottom: 2px solid #333; padding-bottom: 4px; }
h2 { font-size: 12pt; color: #08519c; margin-top: 14px; border-bottom: 1px solid #ccc; }
strong { color: #000; }
em { color: #555; }
code { font-family: Courier, monospace; background: #f3f3f3; font-size: 8.5pt; }
table { border-collapse: collapse; width: 100%; margin: 6px 0; }
th { background: #333; color: #fff; padding: 4px 6px; font-size: 8pt; text-align: left; }
td { border: 1px solid #bbb; padding: 4px 6px; font-size: 8pt; }
img { width: 17cm; margin: 6px 0; }
"""

html = f"<html><head><meta charset='utf-8'><style>{CSS}</style></head><body>{html_body}</body></html>"
with open(PDF, "wb") as f:
    result = pisa.CreatePDF(html, dest=f, encoding="utf-8")
print("ERREURS" if result.err else "OK", "->", PDF)
