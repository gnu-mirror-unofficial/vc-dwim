AC_INIT([vc-dwim], [0.1.3], [jim@meyering.net])

AC_CONFIG_AUX_DIR([build-aux])
AM_INIT_AUTOMAKE([dist-bzip2])

# Minimum Autoconf version required.
AC_PREREQ(2.60)

# Where to generate output; srcdir location.
AC_CONFIG_HEADERS([config.h:config.in])dnl Keep filename to 8.3 for MS-DOS.
AC_CONFIG_SRCDIR([vc-dwim.pl])

AC_PATH_PROG(PERL, perl)
if test -z "$PERL"; then
   AC_MSG_ERROR([perl not found])
fi
$PERL -e 'require 5.006;' || {
   AC_MSG_ERROR(
[perl 5.6 or better is required; perl 5.8.2 or better
is recommended.  If you have several perl versions
installed, select the one Automake should use using
  ./configure PERL=/path/to/perl])
}

AC_CONFIG_FILES([Makefile tests/Makefile])
AC_OUTPUT
