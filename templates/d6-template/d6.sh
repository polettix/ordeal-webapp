#!/bin/bash

COLORS="$*"
[ -z "$COLORS" ] && COLORS=$(teepee <d6.yml -F 'qq(@{[HK "colors_for"]})')
for COLOR in $COLORS ; do
   DIR="d6-$COLOR"
   echo >&2 "generating $DIR..."
   mkdir -p "$DIR"
   for DOTS in 1 2 3 4 5 6 ; do
      teepee <d6.yml >"$DIR/$DOTS.svg" -t d6.svg \
         -d color="$COLOR" -d dots="$DOTS"
   done
done
