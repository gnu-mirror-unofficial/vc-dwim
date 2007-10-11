AC_INIT([vc-dwim], [1.0], [jim@meyering.net])

AC_CONFIG_AUX_DIR([build-aux])
AM_INIT_AUTOMAKE([1.9.6 foreign dist-bzip2 check-news])

# Minimum Autoconf version required.
AC_PREREQ(2.59)

# Where to generate output; srcdir location.
AC_CONFIG_SRCDIR([vc-dwim.pl])

AC_PATH_PROG(PERL, perl)
if test -z "$PERL"; then
   AC_MSG_ERROR([perl not found])
fi
$PERL -e 'require 5.006;' || {
   AC_MSG_ERROR(
[perl 5.6 or better is required; perl 5.8.2 or better
is recommended.  If you have several perl versions
installed, select the one vc-dwim should use using by
  ./configure PERL=/path/to/perl])
}

AC_PROG_AWK
AC_CHECK_PROGS([CTAGS], [ctags-exuberant ctags])
AC_ARG_VAR([CTAGS], [ctags program to use for extracting identifiers])
# contrary to POSIX, Exuberant Ctags prints an extra column.
AC_CACHE_CHECK([whether $CTAGS prints an extra column],
	       [rw_cv_ctags_type_column],
[cat >conftest.c <<EOF
int
f ()
{
  return 0;
}
EOF
case `$CTAGS -x conftest.c` in
  *function*) rw_cv_ctags_type_column=yes ;;
  *) rw_cv_ctags_type_column=no;;
esac
rm -f conftest.c
])
AC_SUBST([ctags_strip_type_column], [$rw_cv_ctags_type_column])

AC_CHECK_PROGS([PATCH], [gpatch patch])
AC_ARG_VAR([PATCH], [patch program to use])

AM_MISSING_PROG([HELP2MAN], [help2man])
AM_MISSING_PROG([POD2MAN], [pod2man])

AC_CONFIG_FILES([Makefile man/Makefile tests/Makefile])
AC_CONFIG_FILES([vc-chlog], [chmod +x vc-chlog])
AC_OUTPUT
