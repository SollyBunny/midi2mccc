#!/bin/sh

rm mdmc/*.mdmc -f
for file in midi/*.mid*; do
    filename=$(basename "$file")
    name="${filename%.*}"
    node ./index.js "$file" "mdmc/${name}.mdmc"
done
./updateliststatic.sh