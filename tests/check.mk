# Include this file at the end of each tests/*/Makefile.am.
# Copyright (C) 2007-2019 Free Software Foundation, Inc.

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

# Propagate build-related Makefile variables to test scripts.
TESTS_ENVIRONMENT =						\
  export							\
  top_srcdir=$(top_srcdir)					\
  srcdir=$(srcdir)						\
  PATCH="$(PATCH)"						\
  PERL="$(PERL)"						\
  perllibdir="`$(am__cd) $(top_srcdir) && pwd`"			\
  PATH="$(VG_PATH_PREFIX)`pwd`/..$(PATH_SEPARATOR)$$PATH"	\
  ; 9>&2

TEST_LOGS = $(TESTS:=.log)

VERBOSE = yes
