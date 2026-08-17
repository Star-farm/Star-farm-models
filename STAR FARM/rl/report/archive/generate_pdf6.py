"""Convert rapport_scalabilite.md -> .pdf (scalability curves embedded)."""
import os
import re

import markdown
from xhtml2pdf import pisa

HERE = os.path.dirname(os.path.abspath(__file__))
MD = os.path.join(HERE, "rapport_scalabilite.md")
PDF = os.path.join(HERE, "rapport_scalabilite.pdf")

text = open(MD, encoding="utf-8").read()
for emo, repl in {"✅": "[OK]", "⚠️": "[!]", "⚠": "[!]", "→": "->", "↔": "<->",
                  "≈": "~", "×": "x", "·": "-"}.items():
    text = text.replace(emo, repl)

html_body = markdown.markdown(text, extensions=["tables", "fenced_code", "sane_lists"])
html_body = re.sub(r'src="([^"]+\.png)"',
                   lambda m: f'src="{os.path.normpath(os.path.join(HERE, m.group(1)))}"', html_body)

CSS = """
@page { size: A4; margin: 1.8cm 1.6cm; }
body { font-family: Helvetica, Arial, sans-serif; font-size: 10pt; line-height: 1.4; color: #222; }
h1 { font-size: 18pt; color: #08306b; border-bottom: 2px solid #08519c; padding-bottom: 4px; }
h2 { font-size: 13pt; color: #08519c; margin-top: 14px; border-bottom: 1px solid #c6dbef; }
em { color: #555; }
code { font-family: Courier, monospace; background: #f2f2f2; font-size: 9pt; }
table { border-collapse: collapse; width: 100%; margin: 6px 0; }
th { background: #08519c; color: white; padding: 4px 6px; font-size: 9pt; text-align: left; }
td { border: 1px solid #bbb; padding: 4px 6px; font-size: 9pt; }
img { width: 17cm; margin: 6px 0; }
"""

html = f"<html><head><meta charset='utf-8'><style>{CSS}</style></head><body>{html_body}</body></html>"
with open(PDF, "wb") as f:
    result = pisa.CreatePDF(html, dest=f, encoding="utf-8")
print("ERREURS" if result.err else "OK", "->", PDF)
