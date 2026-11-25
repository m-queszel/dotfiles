import re
import sys

data = open(sys.argv[1], "rb").read().decode("utf-8", "replace")
target = sys.argv[2]
row = col = 1
fg = None
ever = set()
i = 0
seq = re.compile(r"\x1b\[([0-9;:?]*)([A-Za-z])")
while i < len(data):
    m = seq.match(data, i)
    if m:
        params, cmd = m.group(1), m.group(2)
        if cmd == "H":
            parts = (params or "1;1").split(";")
            row = int(parts[0] or 1)
            col = int(parts[1] or 1) if len(parts) > 1 else 1
        elif cmd == "C":
            col += int(params or 1)
        elif cmd == "m":
            p = params.split(";") if params else ["0"]
            j = 0
            while j < len(p):
                if p[j] in ("0", "39", ""):
                    fg = None
                elif p[j] == "38" and j + 4 < len(p) and p[j + 1] == "2":
                    fg = "#%02x%02x%02x" % (int(p[j + 2]), int(p[j + 3]), int(p[j + 4]))
                    j += 4
                j += 1
        i = m.end()
        continue
    if data[i] == "\x1b":
        i += 2
        continue
    if data[i] in "\r\n":
        i += 1
        continue
    if data[i] in "━┃┏┓┗┛┣┫┳┻╋─│┼├┤┬┴" and fg == target:
        ever.add((row, col))
    col += 1
    i += 1

cols = [c for _, c in ever]
print(len(ever), min(cols) if cols else 0, max(cols) if cols else 0)
