# VC  -  the beginnings of a VC-agnostic diff and commit tool.
#
package VC;

use strict;
use warnings;

use Carp;
use File::Basename; # for dirname

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
    CG  => 'cg',  # FIXME: maybe call this GIT/'git'
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
   },
   CG() => # aka cogito/git
   {
    DIFF_COMMAND => [qw(git-diff --)],
    VALID_DIFF_EXIT_STATUS => {0 => 1},
    COMMIT_COMMAND => [qw(cg-commit -M)],
   },
   HG() => # aka mercurial
   {
    DIFF_COMMAND => [qw(hg diff -p -a --)],
    VALID_DIFF_EXIT_STATUS => {0 => 1},
    COMMIT_COMMAND => [qw(hg ci -l)],
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
    or croak "$ME: missing FILE argument\n";

  my $d = dirname $file;

  # These are quick and easy:
  if (-d "$d/CVS") {
    $self->{name} = CVS;
  } elsif (-d "$d/.svn") {
    $self->{name} = SVN;
  } elsif (-d "$d/.git/objects") {
    $self->{name} = CG;
  } elsif (-d "$d/.hg") {
    $self->{name} = HG;
  }

  exists $self->{name}
    and return bless $self, $class;

  my ($root_dev, $root_ino, undef) = stat '/';
  # For any other, check parents, potentially all the way up to /.
  while (1)
    {
      $d .= '/..';
      if (-d "$d/.git/objects") {
	$self->{name} = CG;
      } elsif (-d "$d/.hg") {
	$self->{name} = HG;
      }

      exists $self->{name}
	and return bless $self, $class;

      my ($dev, $ino, undef) = stat $d;
      $ino == $root_ino && $dev == $root_dev
	and last;
    }
  return undef;
}

sub name()
{
  my $self = shift;
  return $self->{name};
}

sub commit_cmd()
{
  my $self = shift;
  my $cmd_ref = $vc_cmd->{$self->{name}}->{COMMIT_COMMAND};
  return @$cmd_ref;
}

sub diff_cmd()
{
  my $self = shift;
  my $cmd_ref = $vc_cmd->{$self->{name}}->{DIFF_COMMAND};
  return @$cmd_ref;
}

sub valid_diff_exit_status
{
  my $self = shift;
  my $exit_status = shift;
  my $h = $vc_cmd->{$self->{name}}->{VALID_DIFF_EXIT_STATUS};
  return exists $h->{$exit_status};
}

sub supported_vc_names()
{
  return sort keys %$vc_cmd;
}

1;
