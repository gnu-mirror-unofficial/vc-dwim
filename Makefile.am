SUBDIRS = tests

bin_SCRIPTS = vc-dwim
EXTRA_DIST = vc-dwim.pl
CLEANFILES = $(bin_SCRIPTS)

perllibdir = $(pkgdatadir)
dist_perllib_DATA = \
  Coda.pm \
  ProcessStatus.pm

gen_vc_name_list = \
  (./vc-dwim --print-vc-list) 2>/dev/null || echo cg cvs hg svn

## We can't use configure to do the substitution here; we must do it
## by hand.  We use a funny notation here to avoid configure
## substitutions in our text.
do_subst = sed \
  -e 's,[@]PACKAGE[@],$(PACKAGE),g' \
  -e 's,[@]PATH_SEPARATOR[@],$(PATH_SEPARATOR),g' \
  -e 's,[@]PERL[@],$(PERL),g' \
  -e 's,[@]SHELL[@],$(SHELL),g' \
  -e 's,[@]VERSION[@],$(VERSION),g' \
  -e 's,[@]VC_LIST[@],'"$$($(gen_vc_name_list))",g \
  -e 's,[@]configure_input[@],Generated from $@.pl; do not edit by hand.,g' \
  -e 's,[@]datadir[@],$(datadir),g'

## These files depend on Makefile so they are rebuilt if $(VERSION),
## $(datadir) or other do_subst'ituted variables change.
## Use chmod a-w to prevent people from editing the wrong file by accident.
vc-dwim: vc-dwim.pl Makefile
	rm -f $@ $@.tmp
	$(do_subst) $(srcdir)/$@.pl >$@.tmp
	chmod a-w+x $@.tmp
	mv -f $@.tmp $@
