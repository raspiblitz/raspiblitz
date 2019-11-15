REM run this from BlitzTUI directory

REM convert ui files to python code
pyuic5 -x --import-from "." -o blitztui/ui/qcode.py designer/qcode.ui
pyuic5 -x --import-from "." -o blitztui/ui/home.py designer/home.ui
pyuic5 -x --import-from "." -o blitztui/ui/off.py designer/off.ui
pyuic5 -x --import-from "." -o blitztui/ui/invoice.py designer/invoice.ui

REM resources
pyrcc5 -o blitztui/ui/resources_rc.py resources.qrc
