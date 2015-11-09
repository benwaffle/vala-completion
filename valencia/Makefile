PLUGIN = valencia

# The version number appears here and also in valencia.plugin.
VERSION = 0.8.0

ifndef VALAC
VALAC = valac
endif

ifndef LIBVALA
LIBVALA=libvala-0.24
endif

VALAC_VERSION := `$(VALAC) --version | awk '{print $$2}'`
MIN_VALAC_VERSION := 0.20.1

SOURCES = autocomplete.vala browser.vala expression.vala gtk_util.vala parser.vala program.vala \
          scanner.vala settings.vala util.vala valencia.vala

PACKAGES = --pkg gedit --pkg gee-0.8 --pkg gtk+-3.0 --pkg gtksourceview-3.0 \
           --pkg libpeas-1.0 --pkg $(LIBVALA) --pkg vte-2.90

PACKAGE_VERSIONS = \
    gedit >= 2.91.0 \
    gedit <= 3.10.4 \
    gee-0.8 >= 0.8.6 \
    gtksourceview-3.0 >= 3.0.0 \
    gtk+-3.0 >= 3.0.0 \
    $(LIBVALA) \
    vte-2.90 >= 0.27.90

OUTPUTS = libvalencia.so valencia.plugin

DIST_FILES = $(SOURCES) \
             Makefile \
             valencia.png \
             valencia.plugin valencia.plugin.m4 \
             chkver \
             AUTHORS COPYING INSTALL NEWS README THANKS
DIST_TAR = $(PLUGIN)-$(VERSION).tar
DIST_TAR_XZ = $(DIST_TAR).xz

ICON_DIR = ~/.local/share/icons/hicolor/128x128/apps

all: valacheck valencia.plugin libvalencia.so

.PHONY: valacheck
valacheck:
	@ $(VALAC) --version >/dev/null 2>/dev/null || ( echo 'Valencia requires Vala compiler $(MIN_VALAC_VERSION) or greater.  No valac found in path or $$VALAC.'; exit 1 )
	@ ./chkver min $(VALAC_VERSION) $(MIN_VALAC_VERSION) || ( echo 'Valencia requires Vala compiler $(MIN_VALAC_VERSION) or greater.  You are running' $(VALAC_VERSION) '\b.'; exit 1 )
	$(if $(MAX_VALAC_VERSION),\
		@ ./chkver max $(VALAC_VERSION) $(MAX_VALAC_VERSION) || ( echo 'Valencia cannot be built by Vala compiler $(MAX_VALAC_VERSION) or greater.  You are running' $(VALAC_VERSION) '\b.'; exit 1 ),)

valencia.plugin: valencia.plugin.m4 Makefile
	@ type m4 > /dev/null || ( echo 'm4 is missing and is required to build Valencia. ' ; exit 1 )
	m4 -DVERSION='$(VERSION)' valencia.plugin.m4 > valencia.plugin

libvalencia.so: $(SOURCES) Makefile
	@ pkg-config --print-errors --exists '$(PACKAGE_VERSIONS)'
	$(VALAC) $(VFLAGS) -X --shared -X -fPIC $(PACKAGES) $(SOURCES) -o $@

install: libvalencia.so valencia.plugin
	@ [ `whoami` != "root" ] || ( echo 'Run make install as yourself, not as root.' ; exit 1 )
	mkdir -p ~/.local/share/gedit/plugins
	cp $(OUTPUTS) ~/.local/share/gedit/plugins
	mkdir -p $(ICON_DIR)
	cp -p valencia.png $(ICON_DIR)

uninstall:
	rm -f $(foreach o, $(OUTPUTS), ~/.local/share/gedit/plugins/$o)
	rm -f $(ICON_DIR)/valencia.png

parser:  expression.vala parser.vala program.vala scanner.vala util.vala
	$(VALAC) $(VFLAGS) --pkg vala-1.0 --pkg gtk+-2.0 $^ -o $@

dist: $(DIST_FILES)
	mkdir -p $(PLUGIN)-$(VERSION)
	cp --parents $(DIST_FILES) $(PLUGIN)-$(VERSION)
	tar --xz -cvf $(DIST_TAR_XZ) $(PLUGIN)-$(VERSION)
	rm -rf $(PLUGIN)-$(VERSION)

clean:
	rm -f $(SOURCES:.vala=.c) $(SOURCES:.vala=.vala.c) $(SOURCES:.vala=.h) *.so
	rm -f valencia.plugin

