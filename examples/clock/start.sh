#!/bin/sh
erl -pa ebin deps/*/ebin -sname clock -s clock -clock port 8080
