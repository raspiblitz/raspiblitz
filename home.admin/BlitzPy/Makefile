# Makefile

build:
	python setup.py sdist bdist_wheel

clean:
	rm -rf .eggs .tox .coverage .coverage.data .cache build
	rm -rf BlitzPy.egg-info
	find ./ -iname "*.pyc" -delete
	find ./ -type d -iname "__pycache__" -delete

test:
	tox

upload:
	twine upload --skip-existing dist/* -r pypi

upload-test:
	twine upload --skip-existing dist/* -r pypitest

