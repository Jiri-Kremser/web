#!/bin/bash
rm -rf public/ && git submodule update public && hugo && cd public/ && git add -A && git commit -m "update" && git push -f origin HEAD:master && cd -
