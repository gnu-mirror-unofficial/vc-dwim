# VC  -  underpinnings of a VC-agnostic diff and commit tool.

# Copyright (C) 2006-2019 Free Software Foundation, Inc.

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

package VC;

use strict;
use warnings;

use Carp;
use File::Basename; # for dirname
use File::Spec;

# Program name of our caller
(our $ME = $0) =~ s|.*/||;

# accessible to our caller via "$<this_package>::VERSION"
our $VERSION = '0.1';

# For non-OO exporting of code, symbols
our @ISA         = qw(Exporter);
our @EXPORT_OK   = ();
our %EXPORT_TAGS = (default => \@EXPORT_OK);

use constant
  {
    GIT  => 'git',
    CVS => 'cvs',
    HG  => 'hg',
    SVN => 'svn',
    BZR => 'bzr',
    DARCS => 'darcs',
  };

my $vc_cmd =
  {
   CVS() =>
   {
    DIFF_COMMAND => [qw(cvs -f -Q -n diff -Nup --)],
    VALID_DIFF_EXIT_STATUS => {0 => 1, 1 => 1},
    COMMIT_COMMAND => [qw(cvs -Q ci -F)],
    # is-version-controlled-file: search for m!^/REGEX_ESCAPED_FILE/! in CVS/Entries
   },
   GIT() =>
   {
    AUTHOR_FMT => '--author=%s',
    DIFF_COMMAND => [qw(git diff --ignore-submodules=all -B -C HEAD --)],
    DIFF_PRISTINE => [qw(git diff --ignore-submodules=all --no-ext-diff
                         -B -C HEAD --)],
    VALID_DIFF_EXIT_STATUS => {0 => 1},
    COMMIT_COMMAND => [qw(git commit -q -F)],
    # is-version-controlled-file: true, if "git cat-file -t HEAD:$file"
    # exits successfully
   },
   HG() => # aka mercurial
   {
    DIFF_COMMAND => [qw(hg diff -p -a --)],
    VALID_DIFF_EXIT_STATUS => {0 => 1},
    COMMIT_COMMAND => [qw(hg -q ci -l)],
    # For an existing FILE,
    # is-version-controlled-file: true, if "hg st -nu FILE" produces output
   },
   SVN() => # aka subversion
   {
    DIFF_COMMAND => [qw(svn diff --)],
    VALID_DIFF_EXIT_STATUS => {0 => 1},
    COMMIT_COMMAND => [qw(svn ci -q -F)],
   },
   BZR() => # aka bazaar
   {
    AUTHOR_FMT => '--author=%s',
    DIFF_COMMAND => [qw(bzr diff --)],
    VALID_DIFF_EXIT_STATUS => {0 => 1, 1 => 1},
    COMMIT_COMMAND => [qw(bzr ci -q -F)],
   },
   DARCS() => # aka bazaar
   {
    AUTHOR_FMT => '--author=%s',
    DIFF_COMMAND => [qw(darcs diff --)],
    VALID_DIFF_EXIT_STATUS => {0 => 1},
    COMMIT_COMMAND => [qw(darcs record -q -a --look-for-adds --logfile)],
   },
  };

#########
# constructor: determine what version control system manages the specified file
# Most of the contortions here are to determine the value for $cwd_depth, to
# be used in full_file_name.
#########
sub new($%)
{
  # Requires one argument, a ChangeLog file name.
  my $proto = shift;
  my $class = ref($proto) || $proto;
  my $self = {};

  my $file = shift
    or croak "$ME: missing FILE argument";

  my $d = dirname $file;

  # Depth of $file, relative to the nearest VC admin directory,
  # e.g., CVS, .svn, .hg, .git.  For CVS and SVN, $cl_depth is always 0.
  my $cl_depth = 0;

  my $cwd_depth;
  my ($cwd_dev, $cwd_ino, undef) = stat '.';

  my ($root_dev, $root_ino, undef) = stat '/';
  # For any other, check parents, potentially all the way up to /.
  while (1)
    {
      if ($cl_depth == 0)
	{
	  if (-d "$d/CVS") {
	    $self->{name} = CVS;
	  } elsif (-d "$d/.svn") {
	    $self->{name} = SVN;
	  }
	}

      if (-d "$d/.git/objects" || -f "$d/.git") {
	$self->{name} = GIT;
      } elsif (-d "$d/.bzr/repository") {
	$self->{name} = BZR;
      } elsif (-d "$d/.hg") {
	$self->{name} = HG;
      } elsif (-d "$d/_darcs") {
	$self->{name} = DARCS;
      }

      my ($dev, $ino, undef) = stat $d;
      $ino == $cwd_ino && $dev == $cwd_dev
	and $cwd_depth = $cl_depth;

      if (exists $self->{name})
	{
	  if ($self->{name} eq CVS || $self->{name} eq SVN)
	    {
	      $cl_depth == 0
		or croak "$ME: internal error: depth=$cl_depth (expected 0)";
	    }
	  else
	    {
	      if (defined $cwd_depth)
		{
		  $cwd_depth <= $cl_depth
		    or croak "$ME: internal error: $cwd_depth < $cl_depth";
		  $cwd_depth = $cl_depth - $cwd_depth;
		}
	      $self->{cwd_depth} = $cwd_depth;
	    }

	  my $vc_name = $self->{name};
	  return bless $self, $class;
	}

      $ino == $root_ino && $dev == $root_dev
	and last;

      $d .= '/..';
      ++$cl_depth;
    }
  return undef;
}

sub vc_names()
{
  return sort keys %$vc_cmd;
}

sub name()
{
  my $self = shift;
  return $self->{name};
}

sub commit_cmd()
{
  my $self = shift;
  my $cmd_ref = $vc_cmd->{$self->name()}->{COMMIT_COMMAND};
  return @$cmd_ref;
}

sub diff_cmd()
{
  my $self = shift;
  my $cmd_ref = $vc_cmd->{$self->name()}->{DIFF_COMMAND};
  return @$cmd_ref;
}

sub author_option()
{
  my $self = shift;
  my $author = shift;
  my $fmt = $vc_cmd->{$self->name()}->{AUTHOR_FMT};
  my $opt = $fmt ? sprintf ($fmt, $author) : undef;
  return $opt;
}

# Print diff -u style diffs, regardless of envvar settings
# like GIT_EXTERNAL_DIFF or options like git's --ext-diff.
# If no DIFF_PRISTINE member is specified, just use DIFF_COMMAND.
sub diff_pristine()
{
  my $self = shift;
  my $cmd_ref = $vc_cmd->{$self->name()}->{DIFF_PRISTINE}
    || $vc_cmd->{$self->name()}->{DIFF_COMMAND};
  return @$cmd_ref;
}

# Return true if the diff output is not customized.
# FIXME: currently all it knows about is git's GIT_EXTERNAL_DIFF.
# I'm sure there are other ways to configure git's diff output
# as well as the other version control tools.
sub diff_is_pristine()
{
  my $self = shift;
  return $self->name() ne GIT || !defined $ENV{GIT_EXTERNAL_DIFF};
}

sub valid_diff_exit_status
{
  my $self = shift;
  my $exit_status = shift;
  my $h = $vc_cmd->{$self->name()}->{VALID_DIFF_EXIT_STATUS};
  return exists $h->{$exit_status};
}

# True if running diff from a sub-directory outputs +++/--- lines
# with full names, i.e. relative to the top level directory.
# hg and git do this.  svn and cvs output "."-relative names.
sub diff_outputs_full_file_names()
{
  my $self = shift;
  return $self->name() eq GIT || $self->name() eq HG;
}

# Given a "."-relative file name, return an equivalent full one.
# This is needed to derive a "full" (top-relative) name for each file
# listed with a "."-relative name in a ChangeLog file.  The ChangeLog
# file may be in a directory five levels below the "top", and the current
# working directory (when vc-dwim is run) may be 3 levels down.
# In that case, $self->{cwd_depth} would be 3.
sub full_file_name
{
  my $self = shift;
  my $file = shift;
  my $cwd_depth = $self->{cwd_depth};
  $cwd_depth
    or return $file;

  eval 'use Cwd';
  die $@ if $@;
  my @dirs = File::Spec->splitdir( cwd() );

  # Take the last $cwd_depth components of $PWD, and prepend them to $file:
  return File::Spec->catfile(@dirs[-$cwd_depth..-1], $file);
}

sub supported_vc_names()
{
  return sort keys %$vc_cmd;
}

1;
