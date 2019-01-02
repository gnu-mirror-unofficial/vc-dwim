# Customize maint.mk                           -*- makefile -*-
# Copyright (C) 2003-2019 Free Software Foundation, Inc.

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

# Used in maint.mk's web-manual rule
manual_title = vc-dwim

# Use the direct link.  This is guaranteed to work immediately, while
# it can take a while for the faster mirror links to become usable.
url_dir_list = https://ftp.gnu.org/gnu/$(PACKAGE)

# Tests not to run as part of "make distcheck".
# Exclude changelog-check here so that there's less churn in ChangeLog
# files -- otherwise, you'd need to have the upcoming version number
# at the top of the file for each `make distcheck' run.
local-checks-to-skip = strftime-check patch-check check-AUTHORS

# We define Exit in a different file.
Exit_witness_file = tests/trap-setup

# Used in maint.mk's web-manual rule
manual_title = vc-dwim

# Now that we have better tests, make this the default.
export VERBOSE = yes

old_NEWS_hash = f259ca9e61fffcbc09ed14172034492d

update-copyright-env = \
  UPDATE_COPYRIGHT_USE_INTERVALS=1 \
  UPDATE_COPYRIGHT_MAX_LINE_LENGTH=79
