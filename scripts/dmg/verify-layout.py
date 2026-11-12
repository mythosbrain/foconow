import sys
from pathlib import Path

from ds_store import DSStore
from mac_alias import Alias

mount = Path(sys.argv[1])
assert (mount / "Applications").readlink() == Path("/Applications")

with DSStore.open(str(mount / ".DS_Store"), "r") as layout:
    view = layout["."]["icvp"]
    bounds = layout["."]["bwsp"]
    assert view["backgroundType"] == 2
    assert view["iconSize"] == 90
    assert "720" in bounds["WindowBounds"] and "620" in bounds["WindowBounds"]
    assert not bounds["ShowToolbar"] and not bounds["ShowSidebar"]
    assert layout["FocoNow.app"]["Iloc"] == (206, 221)
    assert layout["Applications"]["Iloc"] == (514, 221)
    assert layout["Copy opening command.webloc"]["Iloc"] == (250, 440)
    assert layout["First launch.txt"]["Iloc"] == (470, 440)
    import plistlib
    shortcut = plistlib.loads((mount / "Copy opening command.webloc").read_bytes())
    assert shortcut["URL"] == "https://mythosbrain.github.io/foconow-site/#terminal-title"
    assert not (mount / "Open FocoNow.command").exists()
    assert (mount / "First launch.txt").is_file()
    target = Alias.from_bytes(view["backgroundImageAlias"]).target
    background = mount / target.filename
    assert background.is_file() and background.suffix == ".tiff"
    assert target.cnid == background.stat().st_ino

print("Finder background alias, window bounds, and drag-to-install icon positions verified.")
