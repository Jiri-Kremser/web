#!/bin/bash
hugo && cd public/ && git add -A && git commit -m "update" && git push && cd -
