EXTRA_DIST = $(TESTS) \
  require-git \
  require-hg \
  trap-setup

TESTS_ENVIRONMENT = \
  top_srcdir=$(top_srcdir) \
  srcdir=$(srcdir) \
  PERL="$(PERL)" \
  perllibdir="`$(am__cd) $(top_srcdir) && pwd`" \
  PATH="$(VG_PATH_PREFIX)`pwd`/..$(PATH_SEPARATOR)$$PATH"

TESTS = \
  add-empty \
  git-mv \
  two-line-attr \
  cl-other-user \
  no-vc \
  symlinked-changelog \
  two-vc \
  cl-but-no-diff \
  leading-comment \
  no-star \
  subdir \
  subdir-cvs \
  t-vc-chlog
