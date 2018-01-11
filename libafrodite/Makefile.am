NULL = 

AUTOMAKE_OPTIONS = subdir-objects

SUBDIRS = \
	tests \
	$(NULL)

AM_CPPFLAGS = \
	$(AFRODITE_CFLAGS) \
	-DPACKAGE_DATADIR=\""$(pkgdatadir)"\" \
	-include $(CONFIG_HEADER) \
	$(NULL)

BUILT_SOURCES = libafrodite_la.vala.stamp afroditetest.vala.stamp

if ENABLE_DEBUG
        DEBUG_FLAGS = -g -D DEBUG
endif

pkgconfigdir = $(libdir)/pkgconfig
pkgconfig_DATA = libafrodite@PACKAGE_SUFFIX@.pc

libafrodite@PACKAGE_SUFFIX@.pc: libafrodite.pc
	cp $< $@

lib_LTLIBRARIES = libafrodite@PACKAGE_SUFFIX@.la

noinst_PROGRAMS = afroditetest

libafrodite_la_VALASOURCES = \
	astmerger.vala \
	astdumper.vala \
	parser.vala \
	parseresult.vala \
	symbol.vala \
	symbolresolver.vala \
	datatype.vala \
	voidtype.vala \
	sourcereference.vala \
	sourcefile.vala \
	codedom.vala \
	utils.vala \
	completionengine.vala \
	ellipsistype.vala \
	queryoptions.vala \
	queryresult.vala \
	resultitem.vala \
	constants.vala \
	sourceitem.vala \
	$(NULL)


libafroditeincludedir = $(includedir)/afrodite@PACKAGE_SUFFIX@

libafroditeinclude_HEADERS = \
	afrodite.h \
	$(NULL)


libafrodite@PACKAGE_SUFFIX@_la_SOURCES = \
	libafrodite_la.vala.stamp \
	$(libafrodite_la_VALASOURCES:.vala=.c) \
	$(NULL)

libafrodite_la.vala.stamp: $(libafrodite_la_VALASOURCES)
	$(VALAC) $(DEBUG_FLAGS) -C -H afrodite.h --library libafrodite@PACKAGE_SUFFIX@ --vapidir ../vapi --pkg gio-2.0 --pkg config --pkg libvala-$(VALA_VERSION) --pkg utils --basedir $(top_srcdir)/afrodite $^
	touch $@

libafrodite@PACKAGE_SUFFIX@_la_LDFLAGS = \
	-version-info 2:0:0 \
	$(NULL)

libafrodite@PACKAGE_SUFFIX@_la_LIBADD = \
	$(AFRODITE_LIBS) \
	$(NULL)

afroditetest_VALASOURCES = \
	afroditetest.vala \
	$(NULL)

afroditetest_SOURCES = \
	$(afroditetest_VALASOURCES:.vala=.c) \
	$(NULL)

afroditetest.vala.stamp: $(afroditetest_VALASOURCES)
	$(VALAC) $(DEBUG_FLAGS) -C --vapidir ../vapi --vapidir ./ --pkg libafrodite@PACKAGE_SUFFIX@ --pkg gio-2.0 --pkg config --pkg libvala-$(VALA_VERSION) --pkg utils --basedir $(top_srcdir)/afrodite $^
	touch $@

afroditetest_LDADD = \
	$(AFRODITE_LIBS) \
	libafrodite@PACKAGE_SUFFIX@.la  \
	$(NULL)

vapidir = @VAPIDIR@
vapi_DATA = libafrodite@PACKAGE_SUFFIX@.vapi

EXTRA_DIST = \
	$(libafrodite_la_VALASOURCES) \
	$(afroditetest_VALASOURCES) \
	libafrodite_la.vala.stamp \
	afroditetest.vala.stamp \
	libafrodite@PACKAGE_SUFFIX@.vapi \
	libafrodite.pc.in \
	$(NULL)

CLEANFILES = \
        libafrodite@PACKAGE_SUFFIX@.pc
        $(NULL)

DISTCLEANFILES = \
	$(NULL)

MAINTAINERCLEANFILES = \
	libafrodite@PACKAGE_SUFFIX@.vapi \
	libafrodite.pc \
	libafrodite@PACKAGE_SUFFIX@.pc \
	afrodite.h \
	$(libafrodite_la_VALASOURCES:.vala=.c) \
	$(NULL)

