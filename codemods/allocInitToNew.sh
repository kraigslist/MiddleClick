#!/bin/sh

sed -i '' -E 's/\[\[([A-Za-z_]+) +alloc\] +init\]/[\1 new]/g' ./MiddleClick/*.m
