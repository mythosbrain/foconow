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
    assert layout["Copy command.html"]["Iloc"] == (250, 430)
    assert layout["Open Terminal"]["Iloc"] == (470, 430)
    assert (mount / "Open Terminal").readlink() == Path("/System/Applications/Utilities/Terminal.app")
    assert 'id="copy"' in (mount / "Copy command.html").read_text()
    assert not (mount / "First launch.txt").exists()
    assert not (mount / "Open FocoNow.command").exists()
    target = Alias.from_bytes(view["backgroundImageAlias"]).target
    background = mount / target.filename
    assert background.is_file() and background.suffix == ".tiff"
    assert target.cnid == background.stat().st_ino

print("Finder background alias, window bounds, and drag-to-install icon positions verified.")
