application = defines["app"]
background = defines["background"]

format = "UDZO"
compression_level = 9
filesystem = "HFS+"

files = [(application, "Gaugelet.app")]
symlinks = {"Applications": "/Applications"}

window_rect = ((200, 200), (720, 440))
default_view = "icon-view"
show_status_bar = False
show_tab_view = False
show_toolbar = False
show_pathbar = False
show_sidebar = False
show_icon_preview = False
include_icon_view_settings = True

arrange_by = None
# Finder owns item-label color for picture-backed icon views and renders it dark.
# The light label plates in Packaging/DMG/background*.png provide the contrast.
label_pos = "bottom"
text_size = 14
icon_size = 128
icon_locations = {
    "Gaugelet.app": (155, 239),
    "Applications": (565, 239),
}
