"""Convert note_methodo_rl.md -> .pdf (professional RL methodology note, no images)."""
import os

import markdown
from xhtml2pdf import pisa

HERE = os.path.dirname(os.path.abspath(__file__))
MD = os.path.join(HERE, "note_methodo_rl.md")
PDF = os.path.join(HERE, "note_methodo_rl.pdf")

text = open(MD, encoding="utf-8").read()
# Replace non-ASCII technical glyphs that Helvetica in xhtml2pdf renders poorly.
for a, b in {"→": "->", "×": "x", "·": "-", "≈": "~", "λ": "lambda", "γ": "gamma",
             "²": "^2", "’": "'", "œ": "oe", "—": "-", "–": "-"}.items():
    text = text.replace(a, b)

html_body = markdown.markdown(text, extensions=["tables", "fenced_code", "sane_lists"])

CSS = """
@page { size: A4; margin: 2cm 1.8cm; }
body { font-family: Helvetica, Arial, sans-serif; font-size: 10pt; line-height: 1.45; color: #1a1a1a; }
h1 { font-size: 17pt; color: #111; border-bottom: 2px solid #333; padding-bottom: 5px; }
h2 { font-size: 12.5pt; color: #222; margin-top: 16px; border-bottom: 1px solid #ccc; padding-bottom: 2px; }
h3 { font-size: 10.5pt; color: #333; }
em { color: #555; }
strong { color: #000; }
code { font-family: Courier, monospace; background: #f3f3f3; font-size: 9pt; }
table { border-collapse: collapse; width: 100%; margin: 7px 0; }
th { background: #333; color: #fff; padding: 4px 7px; font-size: 8.5pt; text-align: left; }
td { border: 1px solid #bbb; padding: 4px 7px; font-size: 8.5pt; vertical-align: top; }
hr { border: none; border-top: 1px solid #ccc; margin: 12px 0; }
"""

html = f"<html><head><meta charset='utf-8'><style>{CSS}</style></head><body>{html_body}</body></html>"
with open(PDF, "wb") as f:
    result = pisa.CreatePDF(html, dest=f, encoding="utf-8")
print("ERREURS" if result.err else "OK", "->", PDF)
