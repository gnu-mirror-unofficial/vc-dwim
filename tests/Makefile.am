EXTRA_DIST = $(TESTS)

TESTS_ENVIRONMENT = \
  top_srcdir=$(top_srcdir) \
  srcdir=$(srcdir) \
  PERL="$(PERL)" \
  perllibdir="`cd $(top_srcdir); pwd`" \
  PATH="$(VG_PATH_PREFIX)`pwd`/..$(PATH_SEPARATOR)$$PATH"

TESTS = \
  symlinked-changelog \
  two-vc \
  cl-but-no-diff \
  leading-comment \
  no-star \
  subdir \
  subdir-cvs
