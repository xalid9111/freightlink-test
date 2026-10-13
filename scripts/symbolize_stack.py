#!/usr/bin/env python3
"""Turn a minified AutoFix stack (release web build) into Dart file:line.

The deploy workflow keeps `main.dart.js` + `main.dart.js.map` of every
build as the artifact `sourcemap-<commit>` (Actions → the deploy run →
Artifacts). Download it for the commit shown in the report's version
("0.1.0+abc1234"), then paste the copied AutoFix text (Admin → AutoFix →
Kopyala) into this script:

    python3 scripts/symbolize_stack.py path/to/sourcemap-dir < report.txt

It rewrites every `main.dart.js:LINE:COL` frame and every
`minified:Xyz` class name it can resolve. Standard library only.
"""
import bisect
import json
import os
import re
import sys

_B64 = {c: i for i, c in enumerate("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/")}


def _vlq(segment):
    out, value, shift = [], 0, 0
    for ch in segment:
        digit = _B64[ch]
        more = digit & 32
        value += (digit & 31) << shift
        if more:
            shift += 5
        else:
            out.append(-(value >> 1) if value & 1 else value >> 1)
            value, shift = 0, 0
    return out


class SourceMap:
    def __init__(self, js_path, map_path):
        with open(js_path, encoding="utf-8") as f:
            self.js = f.read()
        with open(map_path, encoding="utf-8") as f:
            m = json.load(f)
        self.rows = []
        src = line = col = name = 0
        for text in m["mappings"].split(";"):
            gen_col, row = 0, []
            for seg in text.split(","):
                if not seg:
                    continue
                f = _vlq(seg)
                gen_col += f[0]
                if len(f) >= 4:
                    src += f[1]
                    line += f[2]
                    col += f[3]
                    nm = None
                    if len(f) >= 5:
                        name += f[4]
                        nm = m["names"][name]
                    row.append((gen_col, m["sources"][src], line + 1, nm))
            self.rows.append(row)
        self._line_starts = [0] + [i + 1 for i, c in enumerate(self.js) if c == "\n"]

    def lookup(self, line0, col0):
        """(dart file, line, name) for a 0-based generated position."""
        if not 0 <= line0 < len(self.rows):
            return None
        row = self.rows[line0]
        i = bisect.bisect_right([r[0] for r in row], col0) - 1
        if i < 0:
            return None
        _, file, line, name = row[i]
        return _short_path(file), line, name

    def class_name(self, minified):
        """Dart class for a dart2js minified class name, if found."""
        m = re.search(r"\bA\.%s\.prototype=\{" % re.escape(minified), self.js)
        if not m:
            return None
        start = m.end()
        for k in range(0, 400, 4):
            off = start + k
            line0 = bisect.bisect_right(self._line_starts, off) - 1
            hit = self.lookup(line0, off - self._line_starts[line0])
            if hit and hit[2] and "." in hit[2]:
                return hit[2].split(".")[0]
        return None


def _short_path(path):
    for marker in ("/lib/src/", "/lib/"):
        i = path.find(marker)
        if i >= 0:
            pkg = path[:i].rstrip("/").split("/")[-1]
            return "%s:%s" % (pkg, path[i + 1:])
    return path


def symbolize(text, smap):
    def frame(m):
        hit = smap.lookup(int(m.group(1)) - 1, int(m.group(2)) - 1)
        if not hit:
            return m.group(0)
        file, line, name = hit
        return "%s  [%s:%d%s]" % (m.group(0), file, line, " " + name if name else "")

    def cls(m):
        name = smap.class_name(m.group(1))
        return "%s [%s]" % (m.group(0), name) if name else m.group(0)

    text = re.sub(r"main\.dart\.js:(\d+):(\d+)", frame, text)
    return re.sub(r"minified:([A-Za-z0-9_$]+)", cls, text)


def main():
    if len(sys.argv) != 2:
        print(__doc__)
        return 2
    d = sys.argv[1]
    smap = SourceMap(os.path.join(d, "main.dart.js"), os.path.join(d, "main.dart.js.map"))
    sys.stdout.write(symbolize(sys.stdin.read(), smap))
    return 0


if __name__ == "__main__":
    sys.exit(main())
