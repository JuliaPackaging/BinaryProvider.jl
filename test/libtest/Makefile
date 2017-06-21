# Figure out our OS, and subsequently our SHLIB_EXT
OS := $(shell uname)
ifneq (,$(findstring MINGW,$(OS)))
override OS := WINNT
endif
ifneq (,$(findstring MSYS,$(OS)))
override OS := WINNT
endif

ifeq ($(OS), WINNT)
CC := gcc
SHLIB_EXT := dll
LIBDIR := bin
else ifeq ($(OS), Darwin)
CC := clang
SHLIB_EXT := dylib
RPATH := -Wl,-rpath,'@executable_path/../lib' -Wl,-rpath,'@executable_path'
INSTALL_NAME := -install_name '@rpath/libtest.$(SHLIB_EXT)'
LIBDIR := lib
else
CC := gcc
SHLIB_EXT := so
RPATH := -Wl,-rpath,'$$ORIGIN/../lib' -Wl,-rpath,'$$ORIGIN'
LIBDIR := lib
endif



all: libtest.tar.gz

fooifier: libtest.$(SHLIB_EXT) fooifier.c Makefile
	$(CC) fooifier.c -g -o $@ -L"$(shell pwd)" $(RPATH) -ltest

libtest.$(SHLIB_EXT): libtest.c Makefile
	$(CC) libtest.c -g -o $@ $(INSTALL_NAME) -shared

libtest.tar.gz: fooifier libtest.$(SHLIB_EXT)
	mkdir -p staging/bin staging/$(LIBDIR)
	cp fooifier staging/bin/
	cp libtest.$(SHLIB_EXT) staging/$(LIBDIR)/
	(cd staging; tar -czvf ../libtest.tar.gz *)
	rm -rf staging

clean:
	rm -rf fooifier fooifier.dSYM
	rm -rf libtest.$(SHLIB_EXT) libtest.$(SHLIB_EXT).dSYM
	rm -rf staging libtest.tar.gz
