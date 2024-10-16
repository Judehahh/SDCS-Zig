#!/bin/bash
trap "kill 0" EXIT

zig build -Doptimize=ReleaseFast
./zig-out/bin/sdcs-zig 0 &
sleep 0.5
./zig-out/bin/sdcs-zig 1 &
sleep 0.5
./zig-out/bin/sdcs-zig 2 &

wait
