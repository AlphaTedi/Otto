# dmgbuild settings for Otto's install window: the app on the left, an
# Applications shortcut on the right, a hand-drawn arrow between them on a branded
# background. dmgbuild writes the window's .DS_Store itself, so Finder is never
# scripted (that is what failed before, see release.sh).
#
#   dmgbuild -s Scripts/dmg-settings.py -D app=path/to/Otto.app Otto out.dmg
import os

app = defines["app"]
files = [app]
symlinks = {"Applications": "/Applications"}
icon = os.path.join(app, "Contents", "Resources", "AppIcon.icns")
format = "UDZO"

# Relative to the repository root, where release.sh runs.
background = "Scripts/assets/dmg-background.tiff"
window_rect = ((200, 160), (640, 400))
default_view = "icon-view"
show_status_bar = False
show_tab_view = False
show_toolbar = False
show_pathbar = False
show_sidebar = False
icon_size = 112
text_size = 13
# Centres, from the window's top left; the arrow runs between them.
icon_locations = {
    os.path.basename(app): (160, 205),
    "Applications": (480, 205),
}
