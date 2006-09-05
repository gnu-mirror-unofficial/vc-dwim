#!@PERL@ -w
# @configure_input@
# Given a command like vc-dwim ChangeLog lib/ChangeLog..., check that each
# ChangeLog has been modified, determine the list of affected files from
# the added lines in the ChangeLog diffs.  Ensure that there is no editor
# temporary file indicating an unsaved emacs buffer, then write all ChangeLog
# entries to a temporary file and run a command like
#   cvs ci -F .msg ChangeLog FILE...
# If more than one ChangeLog file has been modified, do the same
# for them, unifying all entries in the log-msg file, each preceded by
# a line giving the relative directory name, e.g. [./] or [m4/].

# Options?
# --diff/--no-diff (do or don't print diffs)
# --changelog
# print diffs by default, and enable --changelog
#   if all command line args are ChangeLog files.
# FIXME: work also when run from a subdirectory,
#  operating on ChangeLog in that subdirectory.
# FIXME: Consider using only the first, non-"*" ChangeLog line(s)
# as the log message.
# FIXME: Add RCS
# write Documentation section

# FIXME: Optional: warn if there are modified files not listed in ChangeLogs

use strict;
use warnings;
use Getopt::Long;
use File::Basename; # for dirname
use Tie::IxHash;

BEGIN
{
  my $perllibdir = $ENV{'perllibdir'} || '@datadir@/@PACKAGE@';
  unshift @INC, (split '@PATH_SEPARATOR@', $perllibdir);

  # Override SHELL.  This is required on DJGPP so that system() uses
  # bash, not COMMAND.COM which doesn't quote arguments properly.
  # Other systems aren't expected to use $SHELL when Automake
  # runs, but it should be safe to drop the `if DJGPP' guard if
  # it turns up other systems need the same thing.  After all,
  # if SHELL is used, ./configure's SHELL is always better than
  # the user's SHELL (which may be something like tcsh).
  $ENV{'SHELL'} = '@SHELL@' if exists $ENV{'DJGPP'};
}

# FIXME: I really should publish both Coda and ProcessStatus.
# Then this script would simply "use" them, without the "use lib" kludge.
use lib dirname ($0);
use Coda;
use ProcessStatus qw($PROCESS_STATUS);

our $VERSION = '@VERSION@';
(my $ME = $0) =~ s|.*/||;

# This VC-selecting business belongs in a class of its own.
use constant
  {
    CVS => 'cvs',
    CG => 'cg',
    HG => 'hg',
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
my $vc;
my $vc_diff;
my $vc_commit;

my $verbose = 0;
my $debug = 0;

sub usage ($)
{
  my ($exit_code) = @_;
  my $STREAM = ($exit_code == 0 ? *STDOUT : *STDERR);
  if ($exit_code != 0)
    {
      print $STREAM "Try `$ME --help' for more information.\n";
    }
  else
    {
      my $vc_list = join (', ', sort keys %$vc_cmd);
      print $STREAM <<EOF;
Usage: $ME [OPTIONS] CHANGELOG_FILE...
  or:  $ME [OPTIONS] --commit CHANGELOG_FILE...
  or:  $ME [OPTIONS] --diff FILE...

OPTIONS:

By default, command line each argument is expected to be a version-controlled
ChangeLog file.  In this default mode, $ME works by first computing diffs to
any named ChangeLog files, and then parsing that output to determine which
named files are being changed.  Then, it diffs the named files and prints the
resulting output.  One advantage of using this tool is that before printing
any diffs, it ensures that there is no editor temporary file corresponding
to any affected file.  The existence of such a temporary can mean that you
have unsaved changes, usually a bad thing.  Another common error you can
avoid with this tool is that in which you create a new file, add its name to
Makefiles, mention the addition in ChangeLog, but forget to e.g., "git add"
(or "hg add", etc.)  the file to the version control system.  $ME detects this
discrepancy and fails with a diagnostic explaining the probably situation.
You might also have simply mistyped the file name in the ChangeLog.  Similarly,
if diff output suggests you've "cvs remove"d a file, then that file should
no longer exist.  If it does, $ME detects the problem.

This tool automatically detects which version control system affects the
listed files, and uses that.  If it guesses wrong, you can override it's
guess with the --vc=VC option.

Once you are happy with your ChangeLog-derived diffs, you can commit
those changes and the ChangeLog simply by rerunning the command with
the --commit option.

   --commit     perform the commit, too
   --vc=VC      don't guess the version control system: use VC
                  VC must be one of: $vc_list
   --diff       determine which version control system manages the first
                  FILE, then use that to print diffs of the named FILES
   --help       display this help and exit
   --version    output version information and exit
   --verbose	generate verbose output
   --debug	generate debug output

EOF
    }
  exit $exit_code;
}

# Given a file name, F, determine which version control system to use.
# Examine its directory, and possibly all of its parents.
sub vc_name($)
{
  my ($f) = @_;
  my $d = dirname $f;

  # These are quick and easy:
  -d "$d/CVS"
    and return CVS;
  -d "$d/.svn"
    and return SVN;

  -d "$d/.git/objects" and return CG;
  -d "$d/.hg" and return HG;

  my ($root_dev, $root_ino, undef) = stat '/';
  # For any other, we have to check parents, potentially all the way up to /.
  while (1)
    {
      $d .= '/..';
      -d "$d/.git/objects" and return CG;
      -d "$d/.hg" and return HG;
      my ($dev, $ino, undef) = stat $d;
      $ino == $root_ino && $dev == $root_dev
	and last;
    }
  return undef;
}

sub valid_diff_exit_status($)
{
  my ($exit_status) = @_;
  my $h = $vc->{VALID_DIFF_EXIT_STATUS};
  return exists $h->{$exit_status};
}

# Return nonzero if F is a "."-relative name, with no leading "./".
# Also, disallow any name containing a ".." component.
sub valid_file_name($)
{
  my ($f) = @_;
  $f =~ m!^\.?/!
    and return 0;

  # No "." or "/", and it a gimme.
  $f =~ m!^[^./]$!
    and return 1;

  my @comp = split '/', $f;
  grep { $_ eq '..' } @comp
    and return 0;

  return 1;
}

# FIXME: quote any argument that contains meta-characters.
sub verbose_cmd ($)
{
  my ($cmd) = @_;
  warn "Running command: ", join (' ', @$cmd), "\n";
}

# Return an array of lines from running $VC diff -u on the named files.
sub get_diffs ($)
{
  my ($f) = @_;

  my @cmd = (@$vc_diff, @$f);
  $verbose
    and verbose_cmd \@cmd;
  open PIPE, '-|', @cmd
    or die "$ME: failed to run `" . join (' ', @cmd) . "': $!\n";
  # Ignore everything up to first ^@@...@@$ line, which should be line #8.
  my @added_lines = <PIPE>;
  @added_lines
    and chomp @added_lines;
  if ( ! close PIPE)
    {
      # Die if VC diff exits with unexpected status.
      valid_diff_exit_status ($? >> 8)
	or die "$ME: error closing pipe from `"
	  . join (' ', @cmd) . "': $PROCESS_STATUS\n";
    }

  return \@added_lines
}

# Choke if this diff removes any lines, or if there are no added lines.
sub get_new_changelog_lines ($)
{
  my ($f) = @_;

  my $diff_lines = get_diffs ([$f]);
  my @added_lines;
  # Ignore everything up to first line with unidiff offsets: ^@@...@@

  my $found_first_unidiff_marker_line;
  my $unidiff_at_offset;  # line number in orig. file of first line in hunk
  my $offset_in_hunk = 0;
  my $push_offset;
  foreach my $line (@$diff_lines)
    {
      if ($line =~ /^\@\@ -\d+,\d+ \+(\d+),\d+ \@\@/)
	{
	  $push_offset = 1;
	  $unidiff_at_offset = $1;
	  $offset_in_hunk = 0;
	  $found_first_unidiff_marker_line = 1;
	  next;
	}
      ++$offset_in_hunk;
      $found_first_unidiff_marker_line
	or next;
      $line =~ /^[- ]/
	and next;
      $line =~ /^\+/
	or die "$ME: unexpected diff output on line $.:\n$line";
      chomp $line;
      my $offset = $unidiff_at_offset + $offset_in_hunk - 1;
      $push_offset
	and push @added_lines, \$offset;
      $push_offset = 0;
      push @added_lines, $line;
    }
  $found_first_unidiff_marker_line
    or die "$ME: $f: no unidiff output\n";

  0 < @added_lines
    or die "$ME: $f is not modified\n";

  return \@added_lines
}

# For emacs, the temporary is a symlink named ".#ChangeLog",
# with useful information in the link name part.
sub exists_editor_backup ($)
{
  my ($f) = @_;
  my $d = dirname $f;
  $f = basename $f;
  -f "$d/#$f#" || -l "$d/.#$f"
    and return 1;
  return 0;
}

sub is_changelog ($)
{
  my ($f) = @_;
  return $f =~ m!(?:^|/)ChangeLog$!;
}

# This is an interface to perl's system command with a global hook for
# tracing and options to suppress stderr and to die upon failure.
# If the first argument is a hash reference, then treat its key/value
# pairs as option-name/value pairs.  Valid option names are the keys of
# the %all_options hash.
sub run_command
{
  my (@cmd) = @_;

  my %all_options =
    (
     # defaults
     DEBUG => 0,
     VERBOSE => 0,
     IGNORE_FAILURE => 0,
     DIE_UPON_FAILURE => 1,
     INHIBIT_STDERR => 0,
     INHIBIT_STDOUT => 1,
    );

  my %options = %all_options;

  if (@cmd && defined $cmd[0] && ref $cmd[0] && ref $cmd[0] eq 'HASH')
    {
      my $h = shift @cmd;

      my ($key, $val);
      while (($key, $val) = each %$h)
	{
	  exists $all_options{$key}
	    or die "$ME: internal error: invalid option: $key";

	  $options{$key} = $val;
	}
    }

  $verbose
    and verbose_cmd \@cmd;

  use vars qw (*SAVE_OUT *SAVE_ERR);

  if ($options{INHIBIT_STDOUT})
    {
      # Save dup'd copies of stdout.
      open SAVE_OUT, ">&STDOUT";

      # Redirect stdout.
      open STDOUT, ">/dev/null"
	or die "$ME: cannot redirect stdout to /dev/null: $!\n";
      select STDOUT; $| = 1; # make unbuffered
    }

  if ($options{INHIBIT_STDERR})
    {
      open SAVE_ERR, ">&STDERR";
      open STDERR, ">/dev/null"
	or die "$ME: cannot redirect stderr to /dev/null: $!\n";
      select STDERR; $| = 1;
    }

  my $fail = 1;
  my $rc = 0xffff & system @cmd;

  # Restore stdout.
  open STDOUT, ">&SAVE_OUT"
    if $options{INHIBIT_STDOUT};
  open STDERR, ">&SAVE_ERR"
    if $options{INHIBIT_STDERR};

  if ($rc == 0)
    {
      # command ran and exit'ed successfully.
      warn "$ME: ran with normal exit status\n" if $options{DEBUG};
      $fail = 0;
    }
  else
    {
      my $cmd = join (' ', @cmd) . "\n";
      $? = $rc;
      warn "$ME: Error running '$cmd': $PROCESS_STATUS\n";
    }

  if ($fail && !$options{IGNORE_FAILURE})
    {
      my $msg = "$ME: the following command failed:\n"
	. join (' ', @cmd) . "\n";
      die $msg if $options{DIE_UPON_FAILURE};
      warn $msg;
    }

  return $fail;
}

# Look backwards from line number $LINENO in ChangeLog file, $LOG_FILE,
# for the preceding line that tells which file is affected.
# For example, if $LOG_FILE starts like this, and $LINENO is 4 (because
# you've just added the entry for "main"), then this function returns
# the file name from line 3: "cvci".
# -------
# 2006-08-24  Jim Meyering  <jim@meyering.net>
#
#	* cvci (get_new_changelog_lines): Allow removed ChangeLog lines.
#	(main): Prepare to use offsets.
# -------
#
# If the line in question (at $LINENO) is a summary line, then there
# will be no preceding "*"-marked line.  In that case, return the first
# _following_ "*"-marked file name, assuming there is no intervening
# blank line.  If there is no such file name, die.
# Return the pair, <file_name, is_summary_line>.
sub find_relevant_file_name($$)
{
  my ($log_file, $line_no) = @_;

  1 <= $line_no
    or die "$ME: invalid line number, $line_no, derived "
      . "from $log_file diff output\n";

  # Pull in this module only if we'll use it.
  eval 'use IO::File';
  die $@ if $@;
  my $fh = new IO::File $log_file, 'r'
    or die "$ME: can't open `$log_file' for reading: $!\n";

  my @searchable_lines;
  while (defined (my $line = <$fh>))
    {
      $fh->input_line_number == $line_no
	and last;

      if ($line eq "\n")
	{
	  @searchable_lines = ();
	  next;
	}
      chomp $line;
      push @searchable_lines, $line;
    }

  # The list of searchable lines can be empty, e.g., with this diff output:
  # @@ -1,6 +1,8 @@
  # 2006-08-24  Jim Meyering  <jim@meyering.net>
  #
  # +       Work when the first added ChangeLog line doesn't start with '*'.
  #         * cvci (get_new_changelog_lines): Allow removed ChangeLog lines.
  # +       (main): Prepare to use offsets.
  #
  # In that case, search any following sequence of \t-prefixed lines.
  my $is_summary_line;
  my $file_name;
  if (@searchable_lines == 0)
    {
      while (defined (my $line = <$fh>))
	{
	  $line =~ /^\t/
	    or last;
	  if ($line =~ /^\t\* (\S+) /)
	    {
	      $file_name = $1;
	      $is_summary_line = 1;
	      last;
	    }
	}
    }
  else
    {
      while (defined (my $line = pop @searchable_lines))
	{
	  $line =~ /^\t\* (\S+) /
	    and ($file_name = $1), last;
	}
    }
  defined $file_name
    or die "$ME: $log_file: can't find name of file in block containing "
      . "line $line_no\n";

  $file_name =~ s/:$//;
  return ($file_name, $is_summary_line);
}

# Given the part of a ChangeLog line after a leading "\t* ",
# return the list of named files.  E.g.,
# * foo.c: descr
# * lib/bar.c (func): descr
# * glarp.c (struct) [member]: descr
# and multiple files per line, with each comma-separated entry potentially
# looking like one of the above:
# * ix.c (chi), co.c (ff), blurp.h: descr
sub change_log_line_extract_file_list ($)
{
  my ($line) = @_;

  # First, remove any parenthesized and bracketed quantities:
  $line =~ s/\([^)]+\)//g;
  $line =~ s/\[[^]]+\]//g;

  my @comma_sep = split ',', $line;

  my @file_list;
  foreach my $ent (@comma_sep)
    {
      $ent =~ s/^ +//;
      $ent =~ s/ .*//;
      push @file_list, $ent;
    }
  return @file_list;
}

sub main
{
  my $commit;
  my $simple_diff;
  my $vc_name;
  GetOptions
    (
     'vc=s' => sub { $vc_name = $_[1] },

     diff => \$simple_diff,
     commit => \$commit,
     debug => \$debug,
     verbose => \$verbose,
     help => sub { usage 0 },
     version => sub { print "$ME version $VERSION\n"; exit },
    ) or usage 1;

  # Make sure we have at least one FILE argument.
  @ARGV == 0
    and (warn "$ME: no FILE specified\n"), usage 1;

  defined $vc_name && !exists $vc_cmd->{$vc_name}
    and die "$ME: $vc_name: not a supported version control system\n";

  my $fail;

  if ($simple_diff)
    {
      $commit
	and (warn "$ME: you can't use --diff with --commit\n"), usage 1;
      my $f = $ARGV[0];
      $vc_name ||= vc_name $f
	or die "$ME: can't determine version control system for $f\n";
      my $vc = $vc_cmd->{$vc_name};
      my $vc_diff = $vc->{DIFF_COMMAND};
      my @cmd = (@$vc_diff, @ARGV);

      $verbose
	and verbose_cmd \@cmd;

      exec @cmd;
      exit 1;
    }

  my @changelog_file_name = @ARGV;

  # Each FILE must be a "."-relative name, with no leading "./".
  foreach my $f (@changelog_file_name)
    {
      if ( ! valid_file_name $f)
	{
	  warn "$ME: $f: invalid file name\n";
	  $fail = 1;
	}

      # Fail if a command line arg is not a ChangeLog file.
      if ( ! is_changelog($f))
	{
	  warn "$ME: $f: doesn't look like a ChangeLog file\n";
	  $fail = 1;
	}
    }
  $fail
    and exit 1;

  # If there is a temporary indicating that a ChangeLog
  # file has unsaved changes, bail out now.
  foreach my $f (@changelog_file_name)
    {
      -f $f
	or (warn "$ME: $f: no such file\n"), $fail = 1, next;
      exists_editor_backup $f
	and (warn "$ME: $f has unsaved changes\n"), $fail = 1, next;
    }
  $fail
    and exit 1;

  # For each ChangeLog file, determine the version control system
  # in use for its directory.  Choke if they're not all the same.
  my $any_vc_name;
  my %vc_per_arg;
  foreach my $f (@changelog_file_name)
    {
      $any_vc_name = vc_name $f;
      $vc_per_arg{$f} = $any_vc_name;
    }
  1 < keys %vc_per_arg
    and die "$ME: ChangeLog files are managed by more than one version-"
      . "control system\n";

  defined $vc_name
    or $vc_name = $any_vc_name;

  # FIXME: list the offending files.
  ! defined $any_vc_name
    and die "$ME: some file(s) are managed by an unknown"
      . " version-control system\n";

  $vc = $vc_cmd->{$vc_name};
  $vc_diff = $vc->{DIFF_COMMAND};
  $vc_commit = $vc->{COMMIT_COMMAND};

  # Key is ChangeLog file name, value is a ref to list of
  # lines added to that file.
  my %added_log_lines;
  # Extract added lines from each ChangeLog.
  foreach my $log (@changelog_file_name)
    {
      my $new_lines = get_new_changelog_lines $log;
      if (@$new_lines == 0)
	{
	  warn "$ME: no $log diffs?\n";
	  $fail = 1;
	}
      $added_log_lines{$log} = $new_lines;
    }
  $fail
    and exit 1;

  # Construct the log message.
  my @log_msg_lines;

  # Make $log_msg_file an ordered hash, so we ignore duplicate file names,
  # i.e. a file name can appear more than once in a ChangeLog, yet their
  # ordering is preserved.  Then, the diff output (using this list of files)
  # has the same ordering.
  my $log_msg_file = Tie::IxHash->new;

  foreach my $log (@changelog_file_name)
    {
      my @log_lines = @{$added_log_lines{$log}};

      # The first one is always a reference.
      my $offset = shift @log_lines;
      $offset = $$offset;

      # FIXME: extract this to use customized user name/email.
      # FIXME: and add an option to disable entirely.
      # If the first line matches "date  name  email", and it's my name,
      # then ignore the line.  The following one, too, which should be blank.
      # 2006-08-19  Jim Meyering  <jim@meyering.net>
      if (3 <= @log_lines
	  && $log_lines[0] =~ /^\+\d{4}-\d\d-\d\d  Jim Meyering  /)
	{
	  if ($log_lines[1] ne '+')
	    {
	      $log_lines[1] =~ s/^\+//;
	      die "$ME:$log: unexpected, non-blank line after first:\n"
		. $log_lines[1] . "\n";
	    }
	  shift @log_lines;
	  shift @log_lines;
	  $offset += 2;
	}

      # Ignore any leading "+"-only (i.e., added, blank) lines.
      while (@log_lines && $log_lines[0] eq '+')
	{
	  shift @log_lines;
	  ++$offset;
	}

      # If the last line is empty, remove it.
      $log_lines[$#log_lines] eq '+'
	and pop @log_lines;

      foreach my $line (@log_lines)
	{
	  # skip offsets
	  ref $line
	    and next;
	  $line =~ s/^\+//;
	  $line =~ s/^\t//;
	}

      # Insert a preceding marker with the name of the ChangeLog file,
      # if there are two or more ChangeLog files.
      2 <= @changelog_file_name
	and push @log_msg_lines, "[$log]";

      my $rel_dir = dirname $log;

      # Extract file list from each group of log lines.
      foreach my $line (@log_lines)
	{
	  # If the line is a reference, then it's an offset.  Record it,
	  # in case the first added line in that hunk lacks a file name.
	  if (ref $line)
	    {
	      $offset = $$line;
	      next;
	    }

	  # Skip lines like this:
	  # * Version 6.1.
	  $line =~ /^\* Version \d/
	    and next;

	  $line eq ''
	    and next;

	  # If the first added line doesn't start with "*", then
	  # search back through the original ChangeLog file for the
	  # line that does.  But stop at a blank line.  Barf if there
	  # is no such "*"-prefixed line.
	  if (defined $offset)
	    {
	      if ($line !~ /^\* (\S+) /)
		{
		  my ($file, $is_summary_line) =
		    find_relevant_file_name ($log, $offset);
		  # If this is a summary line, don't modify it.
		  # Otherwise, add the "* $file" prefix, using the name
		  # we've just derived, for the log message.
		  if (! $is_summary_line)
		    {
		      my $colon = ($line =~ /^\([^\)]+\)(?:\s*\[[^\]]+\])?: /
				   ? '' : ':');
		      $line = "* $file$colon $line";
		    }
		}
	    }
	  undef $offset;

	  if ($line =~ /^\*/)
	    {
	      $line =~ /^\* (\S.*?):/
		or die "$ME:$log: line of unexpected form:\n$line";
	      my $f_spec = $1;
	      foreach my $file (change_log_line_extract_file_list ($f_spec))
		{
		  my $rel_file = ($rel_dir eq '.' ? $file : "$rel_dir/$file");
		  $log_msg_file->Push($rel_file, undef);
		}
	    }
	}
      continue
	{
	  push @log_msg_lines, $line;
	}
    }

  my @affected_files = $log_msg_file->Keys;
  # print "affected files:\n", join ("\n", @affected_files), "\n";

  @affected_files == 0
    and die "$ME: no files specified in ChangeLog diffs\n";

  # Note: this block is a duplicate of one above, except here we can't
  # check for existence, since a file may be "$vc_name-removed".
  foreach my $f (@affected_files)
    {
      exists_editor_backup $f
	and (warn "$ME: $f has unsaved changes\n"), $fail = 1, next;
    }
  $fail
    and exit 1;

  my @non_ref_log_msg_lines = grep { ! ref $_ } @log_msg_lines;

  # Collect diffs of non-ChangeLog files.
  # But don't print diff output unless we're sure everything is ok.
  my $diff_lines = get_diffs \@affected_files;

  # Record the name of each file marked for removal, according to diff output.
  my %is_removed_file;

  # Ensure that each affected file is mentioned in @$diff_lines
  # Thus, if a new file is listed in a ChangeLog entry, but not e.g.,
  # "hg add"ed, this will catch the error.  Another explanation: a typo,
  # in case you manually (mis)typed the file name in the ChangeLog.
  my %seen;
  my $prev_file;
  foreach my $diff_line (@$diff_lines)
    {
      # For git and hg, look for lines like /^--- a/dir/file.c\s/,
      # or /^\+\+\+ b/dir/file.c\s/, for an hg-added file.
      # For cvs and svn, there won't be an "a/" or "b/" prefix.
      $diff_line =~ /^[-+]{3} (\S+)(?:[ \t]|$)/
	or next;
      my $file_name = $1;
      if ($vc_name eq CG || $vc_name eq HG)
	{
	  # Remove the fake leading "a/" component that git and hg add.
	  $file_name =~ s,^[ab]/,,;
	}

      $diff_line =~ /^\+/ && $file_name eq '/dev/null'
	and $is_removed_file{$prev_file} = 1;
      $prev_file = $file_name;

      $seen{$file_name} = 1;
    }
  foreach my $f (@affected_files)
    {
      if ( ! $seen{$f})
	{
	  warn "$ME: $f is listed in the ChangeLog entry, but not in diffs.\n"
	    . "Did you forget to \"$vc_name add\" it?\n";
	  $fail = 1;
	}
    }
  $fail
    and exit 1;

  foreach my $f (@affected_files)
    {
      if (exists $is_removed_file{$f})
	{
	  -f $f
	    and (warn "$ME: $f: to-be-removed file is still here?!?\n"),
	      $fail = 1, next;
	}
      else
	{
	  -f $f
	    or (warn "$ME: $f: no such file\n"), $fail = 1, next;
	}
    }
  $fail
    and exit 1;

  print join ("\n", @non_ref_log_msg_lines), "\n";
  print join ("\n", @$diff_lines), "\n";

  # FIXME: add an option to take ChangeLog-style lines from a file,
  # rather than always requiring them to come from a diff.

  # Check in the listed ChangeLog files and all derived ones.
  if ($commit)
    {
      # Pull in this module only if we'll use it.
      eval 'use File::Temp';
      die $@ if $@;

      # Write commit log to a file.
      my ($fh, $commit_log_filename)
	= File::Temp::tempfile ('vc-dwim-log-XXXXXX', DIR => '.', UNLINK => 0);
      print $fh join ("\n", @log_msg_lines), "\n";
      close $fh
	or die "$ME: failed to write $commit_log_filename: $!\n";

      my @cmd = (@$vc_commit, $commit_log_filename, '--',
		 @changelog_file_name, @affected_files);
      my $options =
	{
	 DEBUG => $debug,
	 VERBOSE => $verbose,
	 DIE_UPON_FAILURE => 0,
	 INHIBIT_STDOUT => 0,
	};
      run_command ($options, @cmd);

      # FIXME: do this via exit/die/signal handler.
      unlink $commit_log_filename;
    }
}

main();

__END__

###############################################################################
#
# Documentation
#

=head1	NAME

vc-dwim - use new ChangeLog entries to direct and cross check a
version-control "diff" or "commit" command

=head1	SYNOPSIS

B<vc-dwim> [OPTIONS] CHANGELOG_FILE...

B<vc-dwim> [OPTIONS] --commit CHANGELOG_FILE...

B<vc-dwim> [OPTIONS] --diff FILE...

=head1	DESCRIPTION

By default, each command line argument is expected to be a
version-controlled ChangeLog file.  In this default mode, B<vc-dwim> works
by first computing diffs of any named ChangeLog files, and then parsing
that output to determine which named files are being changed.  Then, it
diffs the named files and prints the resulting output.  One advantage
of using this tool is that before printing any diffs, it ensures that
there is no editor temporary file corresponding to any affected file.
The existence of such a temporary can mean that you have unsaved changes,
usually a bad thing.  Another common error you can avoid with this tool
is the one where you create a new file, add its name to Makefiles, etc.,
mention the addition in ChangeLog, but forget to e.g., "git add" (or
"hg add", etc.)  the file to the version control system.  B<vc-dwim>
detects this discrepancy and fails with a diagnostic explaining the
probable situation.  You might also have simply mistyped the file name in
the ChangeLog.  Similarly, if diff output suggests you've "cvs remove"d
a file, then that file should no longer exist.  If it does, B<vc-dwim>
detects the problem.

This tool automatically detects which version control system affects the
listed files, and uses that.  If it guesses wrong, you can override it's
guess with the --vc=VC option.

Once you are happy with your ChangeLog-derived diffs, you can commit
those changes and the ChangeLog simply by rerunning the command with
the --commit option.

=head1	OPTIONS

=over 4

=item B<--commit>

perform the commit, too

=item B<--vc=VC>

Don't guess the version control system: use VC.
VC must be one of: FIXME $vc_list

=item B<--diff>

Determine which version control system manages the first
FILE, then use that to print diffs of the named FILES.

=item B<--help>

Display this help and exit.

=item B<--version>

Output version information and exit.

=item B<--verbose>

Generate verbose output.

=item B<--debug>

Generate debug output.

=item B<--verbose>

Show progress messages.

=item B<--help>

Emit usage hints.

=item B<--version>

Display program version.

=back

=head1	RESTRICTIONS

Relies on fairly strict adherence to recommended ChangeLog syntax.
This tool detects editor temporaries created by Emacs.
FIXME: add support to detect other-editor (e.g., vim) temporaries.

=head1	AUTHOR

Jim Meyering <jim@meyering.net>

Please report bugs or suggestions to <FIXME>

=cut