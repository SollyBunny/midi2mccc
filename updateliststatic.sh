#!/bin/sh
cd mdmc
ls *.mdmc | paste -sd ";" > liststatic
echo mdmc/liststatic updated