# -*- coding: utf-8 -*-
import setuptools

with open("README.md", "r") as fh:
    long_description = fh.read()

with open("blitzpy/version.py") as f:
    __version__ = ""
    exec(f.read())  # set __version__

setuptools.setup(
    name="BlitzPy",
    version=__version__,
    author="RaspiBlitz Developers",
    author_email="raspiblitz@rhab.de",
    description="Common Uses Cases for RaspiBlitz",
    long_description=long_description,
    long_description_content_type="text/markdown",
    url="https://github.com/rootzoll/raspiblitz",
    packages=setuptools.find_packages(exclude=("tests", "docs")),
    classifiers=[
        # How mature is this project? Common values are
        #   3 - Alpha
        #   4 - Beta
        #   5 - Production/Stable
        "Development Status :: 4 - Beta",

        "Programming Language :: Python :: 3",
        "License :: OSI Approved :: MIT License",
        "Operating System :: POSIX :: Linux",
    ],
    python_requires='>=3.6',
    install_requires=[
    ],
)
