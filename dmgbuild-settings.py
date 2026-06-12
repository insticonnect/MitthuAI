# -*- coding: utf-8 -*-
from __future__ import unicode_literals
import plistlib
import os.path

# Path to the compiled .app bundle
application = defines.get('app', 'build/Mitthu.app')
appname = os.path.basename(application)

# Extracts the app icon to badge the mounted volume
def icon_from_app(app_path):
    plist_path = os.path.join(app_path, 'Contents', 'Info.plist')
    if os.path.exists(plist_path):
        try:
            with open(plist_path, "rb") as f:
                plist = plistlib.load(f)
            icon_name = plist.get('CFBundleIconFile', 'AppIcon')
            icon_root, icon_ext = os.path.splitext(icon_name)
            if not icon_ext:
                icon_ext = '.icns'
            icon_name = icon_root + icon_ext
            icon_path = os.path.join(app_path, 'Contents', 'Resources', icon_name)
            if os.path.exists(icon_path):
                return icon_path
        except Exception as e:
            print("Could not load icon from plist: {}".format(e))
    return None

# UDBZ is the standard compressed read-only DMG format
format = 'UDBZ'

# Target files to include in DMG
files = [ application ]

# Symbolic links (shortcut to Application folder)
symlinks = { 'Applications': '/Applications' }

# Badge icon for the volume
badge_icon = icon_from_app(application)

# Align Mitthu.app on the left and Applications shortcut on the right
icon_locations = {
    appname:        (140, 120),
    'Applications': (460, 120)
}

# Window custom dimensions and styling (no sidebars/toolbars)
show_status_bar = False
show_tab_view = False
show_toolbar = False
show_pathbar = False
show_sidebar = False

window_rect = ((100, 100), (600, 260))
default_view = 'icon-view'
show_icon_preview = False
text_size = 14
icon_size = 96
grid_spacing = 100
arrange_by = None
label_pos = 'bottom'
