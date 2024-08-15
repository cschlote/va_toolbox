#!/usr/bin/env bash
set -ex

# Compile and run the programm in unittest mode
dub test

# Check the code
cd source
dmd -g -O -c hashed_enum.d
objdump -S hashed_enum.o

ldc2 -g -O -c hashed_enum.d -of=hashed_enum.o2
objdump -S hashed_enum.o2

