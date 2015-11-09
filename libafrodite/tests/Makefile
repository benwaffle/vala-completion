# Written by Maxim Kouprianov <me@kc.vc>

NULL=

LIBNAME = libafrodite-1.0
TESTNAME = afrodite-test

VALAC = valac
VALA_VERSION = 0.18
LIBVALA = libvala-$(VALA_VERSION)

tests_integrity_SOURCES = \
	completion-manager.vala \
	tests-integrity.vala \
	$(NULL)

tests_var_SOURCES = \
	completion-manager.vala \
	tests-var.vala \
	$(NULL)

tests_basic_SOURCES = \
	completion-manager.vala \
	tests-basic.vala \
	$(NULL)

BUILDARGS = $(VALAC) -g --pkg glib-assert \
	--vapidir ../vapi --vapidir ../ \
	-X -I.. -X -L.. -X -lafrodite-1.0 \
	--pkg gio-2.0 --pkg $(LIBVALA) --pkg utils \
	--pkg libafrodite-1.0

all: test-basic test-integrity test-var

test-basic: build-basic test1

test-integrity: build-integrity test2

test-var: build-var test3

build: build-basic build-integrity build-var

build-basic: $(tests_basic_SOURCES)
	$(BUILDARGS) $^

build-integrity: $(tests_integrity_SOURCES)
	$(BUILDARGS) $^

build-var: $(tests_var_SOURCES)
	$(BUILDARGS) $^

TESTENV = gtester --g-fatal-warnings --verbose

test1: 
	$(TESTENV) completion-manager
test2: 
	$(TESTENV) completion-manager
test3: 
	$(TESTENV) completion-manager

clean:
	git clean -f -d -x
