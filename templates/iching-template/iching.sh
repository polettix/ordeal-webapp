#!/bin/sh

for i in $(seq 0 63) ; do
   I=$(printf '%02d' $i)
   teepee -t iching.svg -d n="$i" -N -o "$I.svg"
done
