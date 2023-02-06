#!/usr/bin/bash

# shell script might be ran on windows through
# msys or cygwin, but exe extension is needed
# to use tools like remedybg
case "$OSTYPE" in
  msys*)    extension=exe ;;
  cygwin*)  extension=exe ;;
  *)        extension=out;;
esac

odin build src -collection:procyon=src "-out=procyon.$extension" -debug