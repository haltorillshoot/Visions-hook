import re, json, collections
src = open("C:/Users/polla/Visions-hook/Visions-hook.lua", encoding="utf-8", errors="ignore").read().replace("\r\n", "\n")
lines = src.split("\n")

# 1) engine elements: menu_references["k"] = parent:create_element({["name"] = "n"}, {["type"] = {["flag"]=..., ["default"]=...}})
rx = re.compile(r'menu_references\["([^"]+)"\]\s*=\s*([\w\.\[\]"]+):create_(element|settings|section)\((.*)\)\s*$')
elements = []
for i, line in enumerate(lines, 1):
    m = rx.search(line)
    if not m or m.group(3) != "element":
        continue
    key, parent, _, rest = m.groups()
    name = re.search(r'\["name"\]\s*=\s*"([^"]*)"', rest)
    kind = re.search(r'\{\["(toggle|slider|dropdown|colorpicker|keybind|button|textbox|label)"\]', rest)
    flag = re.search(r'\["(?:flag|color_flag)"\]\s*=\s*"([^"]+)"', rest)
    dflt = re.search(r'\["default(?:_color)?"\]\s*=\s*([^,}]+)', rest)
    elements.append({"line": i, "key": key, "parent": parent, "name": name.group(1) if name else "", "type": kind.group(1) if kind else "?", "flag": flag.group(1) if flag else key, "default": dflt.group(1).strip() if dflt else None})

# 2) native menu rows
native = []
for i, line in enumerate(lines, 1):
    for m in re.finditer(r'\b(panelToggle|panelSlider|panelList|panelColor|panelKeybind|visualToggle|addBindableToggle|addTextSlider)\(([^)]*)\)', line):
        args = m.group(2)
        strings = re.findall(r'"([^"]*)"', args)
        native.append({"line": i, "fn": m.group(1), "strings": strings[:3]})

# 3) NL map (engine flag <-> menu flag)
nl = re.findall(r'\["([^"]+)"\]\s*=\s*\{"([^"]*)",\s*"([^"]*)"(?:,\s*"(\w+)")?\}', "\n".join(lines[6000:6470]))

by_type = collections.Counter(e["type"] for e in elements)
print("engine elements:", len(elements), dict(by_type))
print("distinct engine flags:", len({e["flag"] for e in elements}))
print("native menu calls:", len(native), dict(collections.Counter(n["fn"] for n in native)))
print("NL map entries:", len(nl))

# engine element ranges by section marker
markers = [(i, l.strip()) for i, l in enumerate(lines, 1) if re.match(r'\s*-- (>|>>) ?\(', l)]
def section(line):
    best = "?"
    for i, m in markers:
        if i <= line: best = m
        else: break
    return re.sub(r'^-- (>|>>) ?\( ?| ?\)$', '', best)
per = collections.Counter(section(e["line"]) for e in elements)
print("\nengine options per section marker (top 25):")
for k, v in per.most_common(25): print("%4d  %s" % (v, k))
json.dump({"elements": elements, "native": native, "nl": nl}, open("C:/Users/polla/audit/inventory.json", "w"), indent=1)
