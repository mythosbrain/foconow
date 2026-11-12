from pathlib import Path

app = Path(defines["app"]).resolve()
background = str(Path(defines["background"]).resolve())

format = "UDZO"
filesystem = "HFS+"
files = [str(app), str(Path(defines["panel"]).resolve())]
symlinks = {"Applications": "/Applications", "Open Terminal": "/System/Applications/Utilities/Terminal.app"}
icon_locations = {app.name: (206, 221), "Applications": (514, 221), "Copy command.html": (250, 430), "Open Terminal": (470, 430)}
window_rect = ((180, 180), (720, 620))
default_view = "icon-view"
arrange_by = None
icon_size = 90
text_size = 13
