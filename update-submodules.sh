#!/bin/bash
git pull
git submodule sync --recursive
git submodule update --init --recursive --remote
git submodule foreach --recursive git pull