"""Convert any report .md in this folder to a same-named .pdf.

Replaces the one-shot generate_pdf3..10.py scripts (now in archive/), which each
hard-coded a single filename over this exact pipeline.

Usage:
    py generate_pdf.py rapport_pareto.md
    py generate_pdf.py note_methodo_rl.md rapport_complet.md   (several at once)
"""
import os
import re
import sys

import markdown
from xhtml2pdf import pisa

HERE = os.path.dirname(os.path.abspath(__file__))

# xhtml2pdf's default fonts lack these glyphs; substitute ASCII-safe equivalents.
SUBS = {"→": "->", "×": "x", "·": "-", "≈": "~", "λ": "lambda", "γ": "gamma",
        "—": "-", "–": "-", "’": "'", "≥": ">=", "≤": "<="}

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


def build(md_name):
    md_path = os.path.join(HERE, md_name)
    pdf_path = os.path.splitext(md_path)[0] + ".pdf"

    text = open(md_path, encoding="utf-8").read()
    for a, b in SUBS.items():
        text = text.replace(a, b)

    body = markdown.markdown(text, extensions=["tables", "fenced_code", "sane_lists"])
    # Image links are relative to this folder; xhtml2pdf needs absolute paths.
    body = re.sub(r'src="([^"]+\.png)"',
                  lambda m: f'src="{os.path.normpath(os.path.join(HERE, m.group(1)))}"', body)

    html = f"<html><head><meta charset='utf-8'><style>{CSS}</style></head><body>{body}</body></html>"
    with open(pdf_path, "wb") as f:
        result = pisa.CreatePDF(html, dest=f, encoding="utf-8")
    print("ERREURS" if result.err else "OK", "->", pdf_path)
    return 1 if result.err else 0


if __name__ == "__main__":
    if len(sys.argv) < 2:
        raise SystemExit(__doc__)
    sys.exit(max(build(name) for name in sys.argv[1:]))
