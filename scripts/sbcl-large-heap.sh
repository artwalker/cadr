#!/usr/bin/env bash
exec sbcl --dynamic-space-size 4096 "$@"
