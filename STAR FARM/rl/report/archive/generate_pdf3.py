"""Convert rapport_etat_projet.md -> rapport_etat_projet.pdf (figures embedded)."""
import os
import re

import markdown
from xhtml2pdf import pisa

HERE = os.path.dirname(os.path.abspath(__file__))
MD = os.path.join(HERE, "rapport_etat_projet.md")
PDF = os.path.join(HERE, "rapport_etat_projet.pdf")

text = open(MD, encoding="utf-8").read()
for emo, repl in {"✅": "[OK]", "⚠️": "[!]", "⚠": "[!]", "🔎": "[obs]", "👉": "=>",
                  "📄": "", "🤖": "", "🎉": "", "🏆": "(*)", "·": "-"}.items():
    text = text.replace(emo, repl)

html_body = markdown.markdown(text, extensions=["tables", "fenced_code", "sane_lists"])
html_body = re.sub(r'src="([^"]+\.png)"', lambda m: f'src="{os.path.join(HERE, m.group(1))}"', html_body)

CSS = """
@page { size: A4; margin: 1.8cm 1.6cm; }
body { font-family: Helvetica, Arial, sans-serif; font-size: 10pt; line-height: 1.4; color: #222; }
h1 { font-size: 18pt; color: #08306b; border-bottom: 2px solid #08519c; padding-bottom: 4px; }
h2 { font-size: 14pt; color: #08519c; margin-top: 16px; border-bottom: 1px solid #c6dbef; }
h3 { font-size: 11.5pt; color: #2171b5; }
em { color: #555; }
code { font-family: Courier, monospace; background: #f2f2f2; font-size: 9pt; }
pre { background: #f5f5f5; border: 1px solid #ddd; padding: 6px; font-size: 8pt; }
table { border-collapse: collapse; width: 100%; margin: 6px 0; }
th { background: #08519c; color: white; padding: 4px 6px; font-size: 9pt; text-align: left; }
td { border: 1px solid #bbb; padding: 4px 6px; font-size: 9pt; }
img { width: 15.5cm; margin: 6px 0; }
blockquote { background: #eef6ff; border-left: 3px solid #08519c; padding: 4px 10px; margin: 6px 0; }
"""

html = f"<html><head><meta charset='utf-8'><style>{CSS}</style></head><body>{html_body}</body></html>"
with open(PDF, "wb") as f:
    result = pisa.CreatePDF(html, dest=f, encoding="utf-8")
print("ERREURS" if result.err else "OK", "->", PDF)
