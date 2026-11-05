#!/bin/sh
set -eu
presentation_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
mkdir -p "$presentation_dir/build"
cd "$presentation_dir"
latexmk -pdf -interaction=nonstopmode -halt-on-error \
  -outdir=build localstat-beamer.tex
cp build/localstat-beamer.pdf localstat-professor-presentation.pdf
