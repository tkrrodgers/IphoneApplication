"""Dump .xlsx (every sheet: values + formulas) or .docx (paragraph text) using only the stdlib."""
import re, sys, zipfile, xml.etree.ElementTree as ET

NS = {"m": "http://schemas.openxmlformats.org/spreadsheetml/2006/main",
      "r": "http://schemas.openxmlformats.org/officeDocument/2006/relationships",
      "w": "http://schemas.openxmlformats.org/wordprocessingml/2006/main"}


def docx(path, out):
    z = zipfile.ZipFile(path)
    root = ET.fromstring(z.read("word/document.xml"))
    for p in root.iter(f"{{{NS['w']}}}p"):
        t = "".join(x.text or "" for x in p.iter(f"{{{NS['w']}}}t"))
        if t.strip():
            out.write(t + "\n")


def xlsx(path, out, max_rows):
    z = zipfile.ZipFile(path)
    shared = []
    if "xl/sharedStrings.xml" in z.namelist():
        for si in ET.fromstring(z.read("xl/sharedStrings.xml")).findall("m:si", NS):
            shared.append("".join(t.text or "" for t in si.iter(f"{{{NS['m']}}}t")))
    wb = ET.fromstring(z.read("xl/workbook.xml"))
    rels = ET.fromstring(z.read("xl/_rels/workbook.xml.rels"))
    target = {r.get("Id"): r.get("Target") for r in rels}
    for dn in wb.iter(f"{{{NS['m']}}}definedName"):
        out.write(f"NAME {dn.get('name')} = {dn.text}\n")
    for s in wb.find("m:sheets", NS):
        rid = s.get(f"{{{NS['r']}}}id")
        t = target[rid].lstrip("/")
        t = t if t.startswith("xl/") else "xl/" + t
        out.write(f"\n===== SHEET: {s.get('name')} (state={s.get('state') or 'visible'}) =====\n")
        root = ET.fromstring(z.read(t))
        rows = root.find("m:sheetData", NS)
        n = 0
        for row in rows:
            cells = []
            for c in row:
                v = c.find("m:v", NS); f = c.find("m:f", NS)
                isel = c.find("m:is", NS)
                val = v.text if v is not None else ""
                if c.get("t") == "s" and val:
                    val = shared[int(val)]
                elif isel is not None:
                    val = "".join(x.text or "" for x in isel.iter(f"{{{NS['m']}}}t"))
                ftxt = f.text if f is not None and f.text else ""
                if val or ftxt:
                    cells.append(f"{c.get('r')}={val!r}" + (f" [={ftxt}]" if ftxt else ""))
            if cells:
                out.write(" | ".join(cells) + "\n")
                n += 1
                if n >= max_rows:
                    out.write("... (truncated)\n")
                    break


if __name__ == "__main__":
    src, dst = sys.argv[1], sys.argv[2]
    with open(dst, "w", encoding="utf-8") as out:
        if src.lower().endswith(".docx"):
            docx(src, out)
        else:
            xlsx(src, out, int(sys.argv[3]) if len(sys.argv) > 3 else 400)
