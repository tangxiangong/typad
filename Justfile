default:
    @just --list

check:
    cargo xtask check

build:
    bash macos/build.sh
