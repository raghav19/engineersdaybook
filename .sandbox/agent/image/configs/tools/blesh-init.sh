# ble.sh faces. Colors 0-15 are the ANSI palette, so they follow the Omarchy theme. No face sets a background.
# Face list: https://github.com/akinomyoga/ble.sh/wiki/Manual-%C2%A77-Customization#721-ble-face
ble-face auto_complete=fg=8
ble-face syntax_error=fg=1,underline
ble-face argument_error=fg=1
ble-face region=reverse
ble-face region_insert=reverse
ble-face region_match=reverse
ble-face region_target=reverse

# menu_filter_input is defined when the completion module loads, so set it after that. See the note in ble.sh: blehook/eval-after-load.
function my/ble-face-complete { ble-face menu_filter_input=fg=3,underline; }
blehook/eval-after-load complete my/ble-face-complete
