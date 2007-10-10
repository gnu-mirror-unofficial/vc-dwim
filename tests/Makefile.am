EXTRA_DIST = $(TESTS) \
  require-cvs \
  require-git \
  require-hg \
  trap-setup

TESTS_ENVIRONMENT = \
  top_srcdir=$(top_srcdir) \
  srcdir=$(srcdir) \
  PATCH="$(PATCH)" \
  PERL="$(PERL)" \
  perllibdir="`$(am__cd) $(top_srcdir) && pwd`" \
  PATH="$(VG_PATH_PREFIX)`pwd`/..$(PATH_SEPARATOR)$$PATH"

TESTS = \
  git-log-summary \
  author \
  subdir-middle \
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
  t-vc-chlog \
  multiple-chlogs
