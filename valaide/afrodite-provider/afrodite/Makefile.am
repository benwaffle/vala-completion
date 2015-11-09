NULL = 

AUTOMAKE_OPTIONS = subdir-objects

SUBDIRS = \
	$(NULL)

AM_CPPFLAGS = \
	$(AFRODITE_CFLAGS) \
	-DPACKAGE_DATADIR=\""$(pkgdatadir)"\" \
	-include $(CONFIG_HEADER) \
	$(NULL)

BUILT_SOURCES = libafrodite.vala.stamp afroditetest.vala.stamp

if ENABLE_DEBUG
        DEBUG_FLAGS = -g -D DEBUG
endif

lib_LTLIBRARIES = libafrodite.la

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
	ast.vala \
	utils.vala \
	completionengine.vala \
	ellipsistype.vala \
	queryoptions.vala \
	queryresult.vala \
	resultitem.vala \
	constants.vala \
	sourceitem.vala \
	$(NULL)


libafroditeincludedir = $(includedir)/afrodite-1.0

libafroditeinclude_HEADERS = \
	afrodite.h \
	$(NULL)


libafrodite_la_SOURCES = \
	libafrodite.vala.stamp \
	$(libafrodite_la_VALASOURCES:.vala=.c) \
	$(NULL)

libafrodite.vala.stamp: $(libafrodite_la_VALASOURCES)
	$(VALAC) $(DEBUG_FLAGS) -C -H afrodite.h --library afrodite-1.0 --vapidir ../vapi --pkg gio-2.0 --pkg config --pkg libvala-$(VALA_VERSION) --pkg utils --basedir $(top_srcdir)/afrodite $^
	touch $@

libafrodite_la_LDFLAGS = \
	-version-info 1:0:0 \
	$(NULL)

libafrodite_la_LIBADD = \
	$(AFRODITE_LIBS) \
	$(NULL)

afroditetest_VALASOURCES = \
	afroditetest.vala \
	$(NULL)

afroditetest_SOURCES = \
	$(afroditetest_VALASOURCES:.vala=.c) \
	$(NULL)

afroditetest.vala.stamp: $(afroditetest_VALASOURCES)
	$(VALAC) $(DEBUG_FLAGS) -C --vapidir ../vapi --vapidir ./ --pkg afrodite-1.0 --pkg gio-2.0 --pkg config --pkg libvala-$(VALA_VERSION) --pkg utils --basedir $(top_srcdir)/afrodite $^
	touch $@

afroditetest_LDADD = \
	$(AFRODITE_LIBS) \
	libafrodite.la  \
	$(NULL)

EXTRA_DIST = \
	$(libafrodite_la_VALASOURCES) \
	$(afroditetest_VALASOURCES) \
	libafrodite.vala.stamp \
	afroditetest.vala.stamp \
	$(NULL)

DISTCLEANFILES = \
	$(NULL)

MAINTAINERCLEANFILES = \
	afrodite-1.0.vapi \
	afrodite.h \
	$(libafrodite_la_VALASOURCES:.vala=.c) \
	$(NULL)

