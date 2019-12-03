# Copyright (C) 2008-2019 Free Software Foundation, Inc.

# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.

# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.

# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <https://www.gnu.org/licenses/>.

EXTRA_DIST =
MOSTLYCLEANFILES =
noinst_LIBRARIES =
include gnulib.mk

SUBDIRS = . doc man tests
ACLOCAL_AMFLAGS = -I m4

bin_SCRIPTS = vc-dwim vc-chlog
EXTRA_DIST += \
  ChangeLog-2011 \
  .prev-version \
  bootstrap \
  bootstrap.conf \
  vc-dwim.pl \
  vc-chlog.in \
  cfg.mk \
  maint.mk

CLEANFILES = $(bin_SCRIPTS)

perllibdir = $(pkgdatadir)
dist_perllib_DATA = \
  Coda.pm \
  ProcessStatus.pm \
  VC.pm

gen_vc_name_list = \
  $(PERL) -I$(srcdir) -MVC -e 'print join(q( ),VC::vc_names())'

## We can't use configure to do the substitution here; we must do it
## by hand.  We use a funny notation here to avoid configure
## substitutions in our text.
do_subst = sed						\
  -e 's,[@]PACKAGE[@],$(PACKAGE),g'			\
  -e 's,[@]PATH_SEPARATOR[@],$(PATH_SEPARATOR),g'	\
  -e 's,[@]SHELL[@],$(SHELL),g'				\
  -e 's,[@]VERSION[@],$(VERSION)',g			\
  -e 's,[@]PACKAGE_BUGREPORT[@],$(PACKAGE_BUGREPORT)',g	\
  -e 's,[@]VC_LIST[@],'"`$(gen_vc_name_list)`",g	\
  -e 's,[@]configure_input[@],Generated from $@.pl; do not edit by hand.,g' \
  -e 's,[@]datadir[@],$(datadir),g'

## These files depend on Makefile so they are rebuilt if $(VERSION),
## $(datadir) or other do_subst'ituted variables change.
## Use chmod a-w to prevent people from editing the wrong file by accident.
## Write this so it works even when hg is not installed on this system.
vc-dwim: vc-dwim.pl Makefile
	$(AM_V_GEN)rm -f $@ $@.tmp
	$(AM_V_at)$(do_subst) $(srcdir)/$@.pl >$@.tmp
	$(AM_V_at)chmod a-w+x $@.tmp
	$(AM_V_at)mv -f $@.tmp $@

# Arrange so that .tarball-version appears only in the distribution
# tarball, and never in a checked-out repository.
dist-hook: gen-ChangeLog
	echo $(VERSION) > $(distdir)/.tarball-version

gen_start_date = 2011-03-08
.PHONY: gen-ChangeLog
gen-ChangeLog:
	$(AM_V_GEN)if test -d .git; then				\
	  $(top_srcdir)/build-aux/gitlog-to-changelog			\
	    --since=$(gen_start_date) > $(distdir)/cl-t &&		\
	    { rm -f $(distdir)/ChangeLog &&				\
	      mv $(distdir)/cl-t $(distdir)/ChangeLog; }		\
	fi

install-exec-hook:
	$(AM_V_at)p=vc-dwim;						\
        ptrans=$$(printf '%s' "$$p" | sed -e "$(transform)");		\
	perl -ni -e '/DELETE_ME/ or print' $(DESTDIR)$(bindir)/$$ptrans
