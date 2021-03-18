# Changelog

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]
## [0.49.0] - 2020-10-03
### Add
- xterm is replaced by uxterm, so that unicode chars are correctly displayed

## [0.48.1] - 2020-05-30
### Add
- move log file to /var/cache/raspiblitz/ if it exists

## [0.47.0] - 2020-05-23
### Removed
- remove config.py as it has been moved to the dedicated package BlitzPy

## [0.46.1] - 2020-04-17
### Removed
- remove LND config check

## [0.45.0] - 2020-01-25
### Added
- clean up log statements
- add debug flag

## [0.44.0] - 2019-12-30
### Added
- make sure to close LN RPC channels

## [0.43.0] - 2019-12-29
### Added
- remove line break for longer TORv3 NodeURI
- fix config check

## [0.42.0] - 2019-12-25
### Added
- extend error logging

## [0.41.0] - 2019-11-15
### Added
- reduce default channel check interval to 40
- increase invoice monitor time to 1 hour

## [0.39.0] - 2019-11-04
### Added
- fix logging
- update blitz.touchscreen.sh scripts

## [0.36.0] - 2019-11-03
### Added
- require at least gRPC (grpcio) version 1.24.3 (to address atomic_exchange_8 issue)
- fix issue on "not-default" setup (not bitcoin/mainnet)

## [0.29.0] - 2019-11-02
### Added
- almost all must-have features have been implemented

## [0.22.2] - 2019-10-27
### Added
- initial creation
