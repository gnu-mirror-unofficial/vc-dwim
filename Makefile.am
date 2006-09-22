SUBDIRS = . tests

bin_SCRIPTS = vc-dwim
EXTRA_DIST = vc-dwim.pl
CLEANFILES = $(bin_SCRIPTS)

perllibdir = $(pkgdatadir)
dist_perllib_DATA = \
  Coda.pm \
  ProcessStatus.pm \
  VC.pm

gen_vc_name_list = \
  $(PERL) -I$(srcdir) -MVC -e 'print join(" ",sort(keys %$VC::vc_cmd))'

## We can't use configure to do the substitution here; we must do it
## by hand.  We use a funny notation here to avoid configure
## substitutions in our text.
do_subst = sed						\
  -e 's,[@]PACKAGE[@],$(PACKAGE),g'			\
  -e 's,[@]PATH_SEPARATOR[@],$(PATH_SEPARATOR),g'	\
  -e 's,[@]PERL[@],$(PERL),g'				\
  -e 's,[@]SHELL[@],$(SHELL),g'				\
  -e 's,[@]VERSION[@],$(VERSION)'"$$ver_suffix",g	\
  -e 's,[@]VC_LIST[@],'"$$($(gen_vc_name_list))",g	\
  -e 's,[@]configure_input[@],Generated from $@.pl; do not edit by hand.,g' \
  -e 's,[@]datadir[@],$(datadir),g'

hg_log_template='{date|shortdate}.{node|short}\n'

## These files depend on Makefile so they are rebuilt if $(VERSION),
## $(datadir) or other do_subst'ituted variables change.
## Use chmod a-w to prevent people from editing the wrong file by accident.
vc-dwim: vc-dwim.pl Makefile
	rm -f $@ $@.tmp
	dirty=`hg stat -nm`;						\
	test -n "$$dirty" && dirty='-dirty';				\
	rev=$$(hg log --limit=1 --template=$(hg_log_template)		\
	  $(srcdir)/vc-dwim.pl) || : ;					\
	ver_suffix="$$rev$$dirty";					\
	test -n "$$ver_suffix" && ver_suffix="($$ver_suffix)";		\
	$(do_subst) $(srcdir)/$@.pl >$@.tmp
	chmod a-w+x $@.tmp
	mv -f $@.tmp $@
