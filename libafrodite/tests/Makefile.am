NULL=

AM_CPPFLAGS = \
        $(AFRODITE_CFLAGS) \
	-I $(top_srcdir)/afrodite \
        -DPACKAGE_DATADIR=\""$(pkgdatadir)"\" \
        -include $(CONFIG_HEADER) \
        $(NULL)

COMMON_LIBS = \
        $(AFRODITE_LIBS) \
        ../libafrodite@PACKAGE_SUFFIX@.la  \
        $(NULL)

LIBVALA = libvala-$(VALA_VERSION)

BUILT_SOURCES = tests_basic.vala.stamp tests_var.vala.stamp tests_integrity.vala.stamp

COMMON_FLAGS = -g --vapidir .. --vapidir . --pkg glib-assert --pkg libafrodite@PACKAGE_SUFFIX@ --pkg $(LIBVALA)

TESTDATA = \
	$(NULL)

####################################################
# Test: tests-basic
####################################################

TESTDATA += tests-basic-source.vala

tests_basic_VALAFLAGS = $(COMMON_FLAGS)

tests_basic_VALASOURCES = \
	completion-manager.vala \
	tests-basic.vala \
	$(NULL)

tests_basic_LDADD = $(COMMON_LIBS) \
	$(NULL)

tests_basic_SOURCES = \
	$(tests_basic_VALASOURCES:.vala=.c) \
	$(NULL)

tests_basic.vala.stamp: $(tests_basic_VALASOURCES)
	$(VALAC) $(COMMON_FLAGS) -C $^
	touch $@
####################################################


####################################################
# Test: tests-var
####################################################

TESTDATA += tests-var-source.vala

tests_var_VALAFLAGS = $(COMMON_FLAGS)

tests_var_VALASOURCES = \
	completion-manager.vala \
	tests-var.vala \
	$(NULL)

tests_var_LDADD = $(COMMON_LIBS) \
	$(NULL)

tests_var_SOURCES = \
	$(tests_var_VALASOURCES:.vala=.c) \
	$(NULL)

tests_var.vala.stamp: $(tests_var_VALASOURCES)
	$(VALAC) $(COMMON_FLAGS) -C $^
	touch $@
####################################################

####################################################
# Test: tests-integrity
####################################################

TESTDATA += tests-integrity.vala

tests_integrity_VALAFLAGS = $(COMMON_FLAGS)

tests_integrity_VALASOURCES = \
	completion-manager.vala \
	tests-integrity.vala \
	$(NULL)

tests_integrity_LDADD = $(COMMON_LIBS) \
	$(NULL)

tests_integrity_SOURCES = \
	$(tests_integrity_VALASOURCES:.vala=.c) \
	$(NULL)

tests_integrity.vala.stamp: $(tests_integrity_VALASOURCES)
	$(VALAC) $(COMMON_FLAGS) -C $^
	touch $@
####################################################


TESTS_ENVIRONMENT = gtester --g-fatal-warnings --verbose

check_PROGRAMS = \
	tests-basic \
	tests-var \
	tests-integrity \
	$(NULL)

TESTS = \
	tests-basic \
	tests-var \
	tests-integrity \
	$(NULL)

EXTRA_DIST = \
	$(tests_var_VALASOURCES) \
	tests_var.vala.stamp \
	$(tests_basic_VALASOURCES) \
	tests_basic.vala.stamp \
	$(tests_integrity_VALASOURCES) \
	tests_integrity.vala.stamp \
	$(TESTDATA) \
	$(NULL)

