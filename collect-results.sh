#!/bin/bash

PROTO=$1
SWD=$(pwd)
cd out/$PROTO
mkdir results
rm -rf results/*
find . -type f -wholename '*crashes/*' | xargs cp -t results/
zip -r $SWD/results.zip results
