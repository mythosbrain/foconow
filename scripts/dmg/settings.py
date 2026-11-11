from pathlib import Path

app = Path(defines["app"]).resolve()
background = str(Path(defines["background"]).resolve())

format = "UDZO"
filesystem = "HFS+"
files = [str(app)]
symlinks = {"Applications": "/Applications"}
icon_locations = {app.name: (206, 221), "Applications": (514, 221)}
window_rect = ((180, 180), (720, 492))
default_view = "icon-view"
arrange_by = None
icon_size = 90
text_size = 13
