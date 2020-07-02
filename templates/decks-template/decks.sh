#!/bin/sh
me="$(readlink -f "$0")"
md="$(dirname "$me")"

find "$md/../../ordeal-assets/decks" -type f \
   | sed -e 's#^.*/ordeal-assets/decks/##' \
   | grep -v '\(^\|/\)\.' \
   | sort \
   | sed -e "s/^/- '/;s/$/'/" \
   | teepee -t "$md/index2.html.ep" -y -

#teepee -t decks.html.ep -o ../decks.html.ep
