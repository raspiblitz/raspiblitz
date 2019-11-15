# Makefile

build:
	python setup.py sdist bdist_wheel

build-ui:
	pyuic5 -x --import-from "." -o blitztui/ui/qcode.py designer/qcode.ui
	pyuic5 -x --import-from "." -o blitztui/ui/home.py designer/home.ui
	pyuic5 -x --import-from "." -o blitztui/ui/off.py designer/off.ui
	pyuic5 -x --import-from "." -o blitztui/ui/invoice.py designer/invoice.ui
	pyrcc5 -o blitztui/ui/resources_rc.py resources.qrc

clean:
	rm -rf .eggs .tox .coverage .coverage.data .cache build
	rm -rf blitz-tui.log BlitzTUI.egg-info
	find ./ -iname "*.pyc" -delete
	find ./ -type d -iname "__pycache__" -delete

test:
	tox

upload:
	twine upload --skip-existing dist/* -r pypi

upload-test:
	twine upload --skip-existing dist/* -r pypitest

