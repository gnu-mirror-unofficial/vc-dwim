# VC  -  the beginnings of a VC-agnostic diff and commit tool.
#
package VC;

use strict;
use warnings;

use Carp;
use File::Basename; # for dirname
use File::Spec;

###############################################################################
# BEGIN user-configurable section

# END   user-configurable section
###############################################################################

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
  };

my $vc_cmd =
  {
   CVS() =>
   {
    DIFF_COMMAND => [qw(cvs -f -Q -n diff -Nu --)],
    VALID_DIFF_EXIT_STATUS => {0 => 1, 1 => 1},
    COMMIT_COMMAND => [qw(cvs ci -F)],
    # is-version-controlled-file: search for m!^/REGEX_ESCAPED_FILE/! in CVS/Entries
   },
   GIT() => # aka cogito/git
   {
    DIFF_COMMAND => [qw(cg-diff --)],
    VALID_DIFF_EXIT_STATUS => {0 => 1},
    COMMIT_COMMAND => [qw(cg-commit -M)],
    # is-version-controlled-file: true, if "git-rm -n 'FILE'" exits successfully
   },
   HG() => # aka mercurial
   {
    DIFF_COMMAND => [qw(hg diff -p -a --)],
    VALID_DIFF_EXIT_STATUS => {0 => 1},
    COMMIT_COMMAND => [qw(hg ci -l)],
    # For an existing FILE,
    # is-version-controlled-file: true, if "hg st -nu FILE" produces output
   },
   SVN() => # aka subversion
   {
    DIFF_COMMAND => [qw(svn diff --)],
    VALID_DIFF_EXIT_STATUS => {0 => 1},
    COMMIT_COMMAND => [qw(svn ci -F)],
   },
  };

#########
# constructor: determine what version control system manages the specified file
#########
sub new($%)
{
  # Requires one argument, a file name.
  my $proto = shift;
  my $class = ref($proto) || $proto;
  my $self = {};

  my $file = shift
    or croak "$ME: missing FILE argument";

  my $d = dirname $file;

  # These are quick and easy:
  if (-d "$d/CVS") {
    $self->{name} = CVS;
  } elsif (-d "$d/.svn") {
    $self->{name} = SVN;
  } elsif (-d "$d/.git/objects") {
    $self->{name} = GIT;
  } elsif (-d "$d/.hg") {
    $self->{name} = HG;
  }

  exists $self->{name}
    and return bless $self, $class;

  my $depth = 0;;
  my ($root_dev, $root_ino, undef) = stat '/';
  # For any other, check parents, potentially all the way up to /.
  while (1)
    {
      ++$depth;
      $d .= '/..';
      if (-d "$d/.git/objects") {
	$self->{name} = GIT;
      } elsif (-d "$d/.hg") {
	$self->{name} = HG;
      }

      if (exists $self->{name})
	{
	  $self->{depth} = $depth;
	  return bless $self, $class;
	}

      my ($dev, $ino, undef) = stat $d;
      $ino == $root_ino && $dev == $root_dev
	and last;
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
sub full_file_name
{
  my $self = shift;
  my $file = shift;
  my $depth = $self->{depth} || 0;
  $depth
    or return $file;

  eval 'use Cwd';
  die $@ if $@;
  my @dirs = File::Spec->splitdir( cwd() );

  # Take the last $depth components of $PWD, and prepend them to $file:
  return File::Spec->catfile(@dirs[-$depth..-1], $file);
}

sub supported_vc_names()
{
  return sort keys %$vc_cmd;
}

1;
