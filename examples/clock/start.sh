#!/bin/sh
erl -pa ebin deps/*/ebin -s clock -clock port 8080
