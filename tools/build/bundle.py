"""Inject the source modules under src/ into the single-file scripts the loader needs.

A script marks where a module goes with a pair of comment lines:

    -- @bundle-begin src/Lead/LeadModel.lua
    -- @bundle-end src/Lead/LeadModel.lua

and the lines between them are generated here (the module source wrapped by BUNDLES below). Never edit generated lines by hand.

Usage:
    python tools/build/bundle.py            rewrite the generated regions
    python tools/build/bundle.py --check    exit 1 when a generated region is out of date (nothing is written)
"""
import re
import sys
from pathlib import Path

root = Path(__file__).resolve().parents[2]

# module path -> (opening line, closing line) wrapped around the module source
BUNDLES = {
    "src/Lead/LeadModel.lua": ('hide_manager["lead_model"] = (function()', "end)()"),
}

TARGETS = ["Visions-hook.lua"]

PATTERN = re.compile(r"(?P<begin>^[ \t]*-- @bundle-begin (?P<path>\S+)\n)(?P<body>.*?)(?P<end>^[ \t]*-- @bundle-end (?P=path)\n)", re.S | re.M)


def render(path):
    opening, closing = BUNDLES[path]
    source = (root / path).read_text(encoding="utf-8").replace("\r\n", "\n").rstrip("\n")

    return opening + "\n" + source + "\n" + closing + "\n"


def bundle(text):
    def replace(match):
        path = match.group("path")

        if path not in BUNDLES:
            raise SystemExit("unknown module in a bundle marker: " + path)

        return match.group("begin") + render(path) + match.group("end")

    return PATTERN.sub(replace, text)


def main():
    check = "--check" in sys.argv[1:]
    stale = []

    for name in TARGETS:
        target = root / name
        raw = target.read_bytes().decode("utf-8")
        crlf = "\r\n" in raw
        text = raw.replace("\r\n", "\n")
        markers = len(PATTERN.findall(text))
        built = bundle(text)

        if built != text:
            stale.append(name)

            if not check:
                target.write_bytes((built.replace("\n", "\r\n") if crlf else built).encode("utf-8"))

        print("%s: %d bundle region(s), %s" % (name, markers, "out of date" if built != text else "up to date"))

    if check and stale:
        sys.exit(1)

    if not check and stale:
        print("rewrote:", ", ".join(stale))


main()
