# -*- coding: utf-8 -*-
import setuptools

with open("README.md", "r") as fh:
    long_description = fh.read()

with open("blitztui/version.py") as f:
    __version__ = ""
    exec(f.read())  # set __version__

setuptools.setup(
    name="BlitzTUI",
    version=__version__,
    author="RaspiBlitz Developers",
    author_email="raspiblitz@rhab.de",
    description="Touch User Interface for RaspiBlitz",
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
    python_requires='>=3.4',
    install_requires=[
        "grpcio", "googleapis-common-protos", "inotify", "psutil", "pyqtspinner", "qrcode",
    ],
    entry_points={
        'console_scripts': ['blitz-tui=blitztui.main:main'],
    },
)
