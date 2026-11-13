#!/usr/bin/env python3
"""Sets the terminal's own background opacity for the shell's glass look.

  terminal_glass.py <opacity>   0.3-1.0; below 1 the line is tagged "# ii-glass"

Alacritty reloads alacritty.toml live and the compositor blurs what a translucent window leaves
see-through. A background opacity keeps the text sharp, which a Hyprland opacity rule would not.
At 1.0 the value is only put back when this script set it (the tag), so an opacity the user wrote
by hand is never overwritten.
"""
import os
import re
import sys

TAG = "# ii-glass"
path = os.path.join(os.environ.get("XDG_CONFIG_HOME", os.path.expanduser("~/.config")), "alacritty", "alacritty.toml")

try:
    opacity = max(0.3, min(1.0, float(sys.argv[1])))
except (IndexError, ValueError):
    sys.exit("usage: terminal_glass.py <opacity>")
if not os.path.exists(path):
    sys.exit(0)

with open(path) as f:
    lines = f.read().split("\n")

section = ""
at = -1
for i, line in enumerate(lines):
    m = re.match(r"^\s*\[([^\]]+)\]\s*$", line)
    if m:
        section = m.group(1)
    elif section == "window" and re.match(r"^\s*opacity\s*=", line):
        at = i
        break

if at == -1:
    if opacity >= 1.0:
        sys.exit(0)
    for i, line in enumerate(lines):
        if re.match(r"^\s*\[window\]\s*$", line):
            lines.insert(i + 1, "opacity = %.2f %s" % (opacity, TAG))
            break
    else:
        sys.exit(0)
else:
    tagged = TAG in lines[at]
    if opacity >= 1.0:
        if not tagged:
            sys.exit(0)
        lines[at] = "opacity = 1.0"
    else:
        lines[at] = "opacity = %.2f %s" % (opacity, TAG)

new = "\n".join(lines)
with open(path) as f:
    if f.read() == new:
        sys.exit(0)
with open(path, "w") as f:
    f.write(new)
