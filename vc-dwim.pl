#!/usr/bin/env perl
# vc-dwim - a version-control-agnostic ChangeLog diff and commit tool
# @configure_input@
#
# Copyright 2006-2019 Free Software Foundation, Inc.
# Written by Jim Meyering <meyering@redhat.com>

# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <https://www.gnu.org/licenses/>.

# Given a command like vc-dwim ChangeLog lib/ChangeLog..., check that each
# ChangeLog has been modified, determine the list of affected files from
# the added lines in the ChangeLog diffs.  Ensure that there is no editor
# temporary file indicating an unsaved editor buffer, then write all ChangeLog
# entries to a temporary file and run a command like
#   cvs ci -F .msg ChangeLog FILE...
# If more than one ChangeLog file has been modified, do the same
# for them, unifying all entries in the log-msg file, each preceded by
# a line giving the relative directory name, e.g. [./] or [m4/].

use strict;
use warnings;

use Errno qw(EEXIST);
use Getopt::Long;
use File::Basename; # for basename and dirname

BEGIN
{
  my $perllibdir = $ENV{'perllibdir'} || '@datadir@/@PACKAGE@';
  unshift @INC, (split '@PATH_SEPARATOR@', $perllibdir);
  unshift @INC, dirname $0; # DELETE_ME upon installation

  # Override SHELL.  This is required on DJGPP so that system() uses
  # bash, not COMMAND.COM which doesn't quote arguments properly.
  # Other systems aren't expected to use $SHELL when Automake
  # runs, but it should be safe to drop the `if DJGPP' guard if
  # it turns up other systems need the same thing.  After all,
  # if SHELL is used, ./configure's SHELL is always better than
  # the user's SHELL (which may be something like tcsh).
  $ENV{'SHELL'} = '@SHELL@' if exists $ENV{'DJGPP'};
}

use Coda;
use VC;
use ProcessStatus qw($PROCESS_STATUS process_status);
use Pod::PlainText;

our $VERSION = '@VERSION@';
(my $ME = $0) =~ s|.*/||;

my $verbose = 0;
my $debug = 0;
my $dry_run = 0;

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
      my $parser = Pod::PlainText->new (sentence => 1, width => 78,
                                     dict => {ME => $ME});
      # Read POD from __END__ (below) and write to STDOUT.
      *STDIN = *DATA;
      $parser->parse_from_filehandle;
    }
  exit $exit_code;
}

# Return nonzero if F is a "."-relative name, with no leading "./".
# Also, disallow any name containing a ".." component.
sub valid_file_name($)
{
  my ($f) = @_;
  $f =~ m!^\.?/!
    and return 0;

  # No "." or "/", and it a gimme.
  $f !~ m![./]!
    and return 1;

  my @comp = split '/', $f;
  grep { $_ eq '..' } @comp
    and return 0;

  return 1;
}

# Print the output you see with --verbose.
# Be careful to quote any meta-characters.
sub verbose_cmd ($)
{
  my ($cmd) = @_;
  warn "Running command: ", join (' ', map {quotemeta} @$cmd), "\n";
}

# Return an array of lines from running $VC diff -u on the named files.
# If $PRISTINE, do not honor e.g., git's --ext-diff option.
sub get_diffs ($$$)
{
  my ($vc, $f, $pristine) = @_;

  my @cmd = ($pristine ? $vc->diff_pristine() : $vc->diff_cmd(), @$f);
  if ($dry_run) {
    print "$ME: would run: @cmd\n";
    return [];
  }
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
      $vc->valid_diff_exit_status($? >> 8)
        or die "$ME: error closing pipe from `"
          . join (' ', @cmd) . "': $PROCESS_STATUS\n";
    }

  # This may not be needed for git (for it, just run
  # git config diff.suppress-blank-empty true), but for other
  # version control systems, it helps to normalize diff output.
  foreach my $i (0..$#added_lines)
    {
      $added_lines[$i] eq ' '
        and $added_lines[$i] = '';
    }

  return \@added_lines;
}

# Parse a ChangeLog diff: ignore removed lines, collect added ones.
sub get_new_changelog_lines ($$)
{
  my ($vc, $f) = @_;

  my $diff_lines = get_diffs ($vc, [$f], 1);
  if (@$diff_lines == 0)
    {
      $dry_run and return [];
      my $vc_name = $vc->name();
      die qq|$ME: "$vc_name diff $f" produced no output\n|;
    }

  my @added_lines;
  # Ignore everything up to first line with unidiff offsets: ^@@...@@

  my $found_first_unidiff_marker_line;
  my $unidiff_at_offset;  # line number in orig. file of first line in hunk
  my $offset_in_hunk = 0;
  my $push_offset;
  foreach my $line (@$diff_lines)
    {
      if ($line =~ /^\@\@ -\d+(?:,\d+)? \+(\d+)(?:,\d+)? \@\@/)
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
      $line eq '' || $line =~ /^[- ]/
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

  @added_lines == 0
    and die "$ME: $f contains no newly added lines\n";

  $found_first_unidiff_marker_line
    or die "$ME: $f: no unidiff output\n";

  return \@added_lines;
}

# For emacs, the temporary is a symlink named "$dir/.#$base",
# with useful information in the link name part.
# For Vim, the temporary is a regular file named "$dir/.$base.swp".
# Vim temporaries can also be named .$base.swo, .$base.swn, .$base.swm, etc.
# so test for a few of those, in the unusual event that one of those
# exists, but the .swp file does not.
sub exists_editor_backup ($)
{
  my ($f) = @_;

  # If $f is a symlink, use its referent.
  -l $f
    and $f = readlink $f;

  my $d = dirname $f;
  $f = basename $f;
  my @candidate_tmp =
    (
     "$d/.#$f", "$d/#$f#",                      # Emacs
     map { "$d/.$f.sw$_" } qw (p o n m l k),    # Vim
    );
  foreach my $c (@candidate_tmp)
    {
      -l $c or -f _
        and return $c; # Vim
    }
  return undef;
}

sub is_changelog ($)
{
  my ($f) = @_;
  return $f =~ m!(?:^|/)ChangeLog!;
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
     INHIBIT_STDOUT => ! $dry_run, # keep stdout if just printing
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
      open *SAVE_OUT, ">&STDOUT";

      # Redirect stdout.
      open STDOUT, ">/dev/null"
        or die "$ME: cannot redirect stdout to /dev/null: $!\n";
      select STDOUT; $| = 1; # make unbuffered
    }

  if ($options{INHIBIT_STDERR})
    {
      open *SAVE_ERR, '>&', STDERR;
      open STDERR, ">/dev/null"
        or die "$ME: cannot redirect stderr to /dev/null: $!\n";
      select STDERR; $| = 1;
    }

  my $fail = 1;
  my $rc;
  if ($dry_run) {
    print "$ME: would run: @cmd\n";
    $rc = 0;
  } else {
    $rc = 0xffff & system @cmd;
  }

  # Restore stdout.
  open STDOUT, '>&', *SAVE_OUT
    if $options{INHIBIT_STDOUT};
  open STDERR, '>&', *SAVE_ERR
    if $options{INHIBIT_STDERR};

  if ($rc == 0)
    {
      # command ran and exit'ed successfully.
      warn "$ME: ran with normal exit status\n" if $options{DEBUG};
      $fail = 0;
    }
  else
    {
      my $cmd = join (' ', @cmd);
      warn "$ME: Error running '$cmd': ", process_status($rc), "\n";
    }

  if ($fail && !$options{IGNORE_FAILURE})
    {
      eval 'use Cwd';
      my $cwd = $@ ? '' : ' (cwd= ' . Cwd::getcwd() . ')';
      my $msg = "$ME: the following command failed$cwd:\n"
        . join (' ', @cmd) . "\n";
      die $msg if $options{DIE_UPON_FAILURE};
      warn $msg;
    }

  return $fail;
}

# Given the part of a ChangeLog line after a leading "\t* ",
# return the list of named files.  E.g.,
# * foo.c: descr
# * foo.c (func_1, func_2): descr
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
      $ent =~ s/:$//;
      push @file_list, $ent;
    }
  return @file_list;
}

# Look backwards from line number $LINENO in ChangeLog file, $LOG_FILE,
# for the preceding line that tells which file is affected.
# For example, if $LOG_FILE starts like this, and $LINENO is 4 (because
# you've just added the entry for "main"), then this function returns
# the file name from line 3: "cvci".
# -------
# 2006-08-24  Jim Meyering  <jim@meyering.net>
#
#       * cvci (get_new_changelog_lines): Allow removed ChangeLog lines.
#       (main): Prepare to use offsets.
# -------
#
# If the line in question (at $LINENO) is a summary line, then there
# will be no preceding "*"-marked line.  In that case, return the first
# _following_ "*"-marked file name, assuming there is no intervening
# blank line.  If there is no such file name, presume the specified
# line is part of a summary, and return <undef, 1>.
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
  my $file_name_line;
  if (@searchable_lines == 0)
    {
      while (defined (my $line = <$fh>))
        {
          $line =~ /^\t/
            or last;
          if ($line =~ /^\t\*(.*)/)
            {
              $file_name_line = $1;
              $is_summary_line = 1;
              last;
            }
        }
    }
  else
    {
      while (defined (my $line = pop @searchable_lines))
        {
          $line =~ /^\t\*(.*)/
            and ($file_name_line = $1), last;
        }
    }
  if ( ! defined $file_name_line)
    {
      $is_summary_line = 1;
      return (undef, $is_summary_line);
    }

  my @names = change_log_line_extract_file_list ($file_name_line);
  my $file_name = shift @names
    or die "$ME: $log_file:$line_no: `*'-line with no file names?\n";

  return ($file_name, $is_summary_line);
}

# Like find_relevant_file_name, but find the preceding date/name/email
# line in $log_file.  Return "User Name user@example.com", undef, or die.
# Thus, when adding a new entry by someone else *without* also adding
# the date+name+email in the ChangeLog.  This also works around the
# situation where diff output happens to show the date+name+email line
# being inserted only *after* the new entry.
sub find_author($$)
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

  my $name_and_email;
  while (defined (my $line = <$fh>))
    {
      $fh->input_line_number == $line_no
        and last;

      $line =~ /^\d{4}-\d\d-\d\d  (.*)/
        and $name_and_email = $1;
    }

  return $name_and_email;
}

# Check in the files in @$file_list_arg, using the lines in @$log_msg_lines
# as the log message.  $vc tells which version control system to use.
# If there's only one file, say F, and its name starts with "/", then
# do "chdir(dirname(F))" before performing the commit (committing
# "basename(F)" in that case), and restore the initial working directory
# afterwards.
sub do_commit ($$$$)
{
  my ($vc, $author, $log_msg_lines, $file_list_arg) = @_;

  my @file_list = @$file_list_arg;

  # Now that there is a strong incentive to separate each Git summary
  # line from any remaining portion of the commit log, insert an empty
  # line automatically.  E.g., given a ChangeLog entry like this:
  #
  #         Insert blank line in log after first, for git.
  #         * vc-dwim.pl (do_commit): ...
  #
  # use this 3-line log message:
  #
  # Insert blank line in log after first, for git.
  #
  # * vc-dwim.pl (do_commit): ...

  # If the commit log has two or more lines, and the second one is
  # not already empty, then insert a blank line after the first.
  # Do this for all version control types, not just git, so that
  # things will look better in the long run, once they've all been
  # converted to git :-)
  2 <= @$log_msg_lines
    && length $log_msg_lines->[1]
      and splice @$log_msg_lines, 1, 0, "";

  # Write commit log to a file.
  my ($fh, $commit_log_filename)
    = File::Temp::tempfile ('vc-dwim-log-XXXXXX', DIR => '.', UNLINK => 0);
  print $fh join ("\n", @$log_msg_lines), "\n";
  close $fh
    or die "$ME: failed to write $commit_log_filename: $!\n";

  my @vc_commit = $vc->commit_cmd();
  push @vc_commit, $commit_log_filename;

  # If the back-end has an --author=... option, use it.
  my $author_opt = $vc->author_option($author);
  $author_opt
    and push @vc_commit, $author_opt;

  my @cmd = (@vc_commit, '--', @file_list);

  my $options =
    {
     DEBUG => $debug,
     VERBOSE => $verbose,
     DIE_UPON_FAILURE => 1,
     INHIBIT_STDOUT => 0,
    };
  run_command ($options, @cmd);

  # FIXME: do this via exit/die/signal handler.
  unlink $commit_log_filename;
}

# Run $CODE from a different directory, then restore the initial
# working directory.  Die if anything fails.
sub do_at($$)
{
  my ($dest_dir, $code) = @_;
  eval 'use Cwd';
  die $@ if $@;
  my $initial_wd = Cwd::getcwd()
    or die "$ME: getcwd failed: $!\n";
  chdir $dest_dir
    or die "$ME: unable to chdir to $dest_dir: $!\n";
  &$code;
  chdir $initial_wd
    or die "$ME: unable to restore working directory $initial_wd: $!\n";
}

# Cross-check the file names and operations (change, add, remove) implied
# by diff output against the names listed in ChangeLog ($affected_files).
# Ensure that each affected file is mentioned in @$diff_lines
# Thus, if a new file is listed in a ChangeLog entry, but not e.g.,
# "hg add"ed, this will catch the error.  Another explanation: a typo,
# in case you manually (mis)typed the file name in the ChangeLog.
sub cross_check ($$$)
{
  my ($vc, $affected_files, $diff_lines) = @_;
  my $vc_name = $vc->name();

  # Record the name of each file marked for removal, according to diff output.
  my %is_removed_file;

  my $fail = 0;
  my %seen;
  my $prev_file;
  foreach my $diff_line (@$diff_lines)
    {
      if ($vc_name eq VC::GIT)
        {
          # Handle diff-header lines like this from git:
          #
          # diff --git a/tests/mv/setup b/tests/other-fs-tmpdir
          # similarity index 100%
          # rename from tests/mv/setup
          # rename to tests/other-fs-tmpdir
          if ($diff_line =~ /^rename (from|to) (\S+)$/)
            {
              $1 eq 'from'
                and $is_removed_file{$2} = 1;
              $seen{$2} = 1;
              next;
            }

          # Handle diff-header lines like this from git:
          # deleted file mode 100644
          # index 8f468ef..0000000
          # --- a/x
          # +++ /dev/null
          # @@ -1,3 +0,0 @@
          # -a
          # diff --git a/z b/z
          # new file mode 100644
          # index 0000000..e69de29
          $diff_line =~ /^diff /
            and undef $prev_file;

          if ($diff_line =~ m!^diff --git ./(\S+) ./\S+$!)
            {
              $prev_file = $1;
              $seen{$prev_file} = 1;
              next;
            }

          if ($diff_line =~ /^(deleted|new) file mode [0-7]{6}$/)
            {
              $1 eq 'deleted'
                and $is_removed_file{$prev_file} = 1;
              $seen{$prev_file} = 1;
              next;
            }
        }

      # For git and hg, look for lines like /^--- a/dir/file.c\s/,
      # or /^\+\+\+ b/dir/file.c\s/, for an hg-added file.
      # For cvs and svn, there won't be an "a/" or "b/" prefix.
      $diff_line =~ /^[-+]{3} (\S+)(?:[ \t]|$)/
        or next;
      my $file_name = $1;
      if ($vc_name eq VC::GIT || $vc_name eq VC::HG)
        {
          # Remove the fake leading "a/" component that git and hg add.
          $file_name =~ s,^[ab]/,,;
        }

      $diff_line =~ /^\+/ && $file_name eq '/dev/null'
        and $is_removed_file{$prev_file} = 1;
      $prev_file = $file_name;

      $seen{$file_name} = 1;
    }
  foreach my $f (@$affected_files)
    {
      my $full_name = ($vc->diff_outputs_full_file_names()
                       ? $vc->full_file_name($f) : $f);
      if ( ! $seen{$full_name})
        {
          warn "$ME: $f is listed in the ChangeLog entry, but not in diffs.\n"
            . "Did you forget to add it?\n";
          $fail = 1;
        }
    }
  $fail
    and exit 1;

  foreach my $f (@$affected_files)
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
}

# If $$AUTHOR is not yet specified, set it from $NAME_AND_EMAIL.
# If it is specified, then it must match (modulo 1 vs 2 spaces)
# the $NAME_AND_EMAIL from the ChangeLog.
sub check_attribution($$)
{
  my ($name_and_email, $author) = @_;
  $name_and_email =~ s/  +</ </;
  if ( ! defined $$author)
    {
      $$author = $name_and_email;
      return;
    }

  $$author =~ s/  +</ </;
  $$author eq $name_and_email
    or die "$ME: --author/ChangeLog mismatch:\n  $$author\n  $name_and_email\n";
}

# Return the name of the/an admin directory associated with
# the current directory.  If there is none, return undef.
sub admin_dir()
{
  # This is the usual case: a .git directory.
  -d '.git/objects' and return '.git';
  # With a git worktree, .git is a file containing a line of this form:
  # gitdir: /abs/dir
  my $git_file = '.git';
  if (-f $git_file)
    {
      # Read .git, and extract the name after "gitdir: "
      my $fh = new IO::File $git_file, 'r'
        or die "$ME: can't open `$git_file' for reading: $!\n";
      my $line = <$fh>;
      defined $line && $line =~ /^gitdir: (.+)$/
        and return $1;
    }
  -d '.hg' and return '.hg';
  -d 'CVS' and return 'CVS';
  -d '.svn' and return '.svn';
  -d '.bzr/repository' and return '.bzr';
  -d '_darcs' and return '_darcs';
  return undef;
}

sub main
{
  my $commit;
  my $simple_diff;
  my $print_vc_list;
  my $author;
  my $initialize;
  GetOptions
    (
     initialize => \$initialize,
     diff => \$simple_diff,
     commit => \$commit,
     'author=s' => \$author,   # makes sense only with --commit
     'print-vc-list' =>
       sub { print join (' ', VC::supported_vc_names()), "\n"; exit },
     n => \$dry_run,
     'dry-run' => \$dry_run,
     debug => \$debug,
     verbose => \$verbose,
     help => sub { usage 0 },
     version => sub { print "$ME version $VERSION\n"; exit },
    ) or usage 1;

  my $fail;

  if ($initialize)
    {
      my $adm = admin_dir
        or die "$ME: no version-control admin dir in the current directory\n";
      my $options =
        {
         DEBUG => $debug,
         VERBOSE => $verbose,
         DIE_UPON_FAILURE => 1,
         INHIBIT_STDOUT => 0,
        };

      my $cl = 'ChangeLog';
      do_at ($adm, sub
      {
        if ($dry_run) {
          print "$ME: would mkdir 'c' in $adm\n";
        } else {
          ! (mkdir ('c') || $! == EEXIST)
            and die "$ME: failed to create $adm/c: $!\n";
          chdir 'c' or die "$ME: failed to chdir to $adm/c: $!\n";
        }

        # touch ChangeLog || die
        if ($dry_run) {
          print "$ME: would touch $cl in $adm\n";
        } else {
          open FH, '>>', $cl
            or die "$ME: failed to open '$cl' for writing: $!\n";
          close FH
            or die "$ME: failed to write '$cl': $!\n";
        }

        # Initialize the git repo, add ChangeLog and commit it.
        # Any failure is fatal.
        run_command ($options, qw(git init -q));
        run_command ($options, qw(git add), $cl);
        run_command ($options, qw(git commit --allow-empty -q -m. -a));
      });

      # If a ChangeLog file exists in the current directory, rename it
      # deliberately ignoring any rename failure. (But only report the
      # rename for dry runs if it does exist.)
      if ($dry_run) {
        -e $cl and print "$ME: would rename($cl, $cl~)\n";
      } else {
        rename $cl, "$cl~";
      }

      # Create the top-level ChangeLog symlink into $adm/c:
      my $cl_sub = "$adm/c/$cl";
      if ($dry_run) {
        print "$ME: would symlink($cl_sub, $cl)\n";
      } else {
        symlink $cl_sub, $cl
          or die "$ME: failed to create symlink, $cl, to $cl_sub: $!\n";
      }

      exit 0;
    }

  if ($simple_diff)
    {
      $commit
        and (warn "$ME: you can't use --diff with --commit\n"), usage 1;
      my $f = defined $ARGV[0] ? $ARGV[0] : '.';
      my $vc = VC->new ($f)
        or die "$ME: can't determine version control system for $f\n";
      my @vc_diff = $vc->diff_cmd();
      my @cmd = (@vc_diff, @ARGV);

      $verbose
        and verbose_cmd \@cmd;

      if ($dry_run) {
        print "$ME: would run: @cmd\n";
        exit 0;
      } else {
        exec @cmd;
      }
      exit 1;
    }

  @ARGV == 0
    and @ARGV = qw(ChangeLog);

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
      my $edit_tmp = exists_editor_backup $f;
      defined $edit_tmp
        and (warn "$ME: $f has unsaved changes: $edit_tmp\n"), $fail = 1, next;
    }
  $fail
    and exit 1;

  # For each ChangeLog file, determine the version control system
  # in use for its directory.  Choke if they're not all the same.
  my $any_vc_name;
  my %vc_per_arg;
  my %seen_vc;
  foreach my $f (@changelog_file_name)
    {
      my $vc = VC->new($f)
        or next;
      $any_vc_name = $vc->name();
      $seen_vc{$any_vc_name} = 1;
      $vc_per_arg{$f} = $any_vc_name;
    }
  1 < keys %seen_vc
    and die "$ME: ChangeLog files are managed by more than one version-"
      . "control system:\n",
        map {"  $_: $vc_per_arg{$_}\n"} (sort keys %vc_per_arg);

  ! defined $any_vc_name
    and die "$ME: no FILE is managed by a supported"
      . " version-control system\n";

  my $vc = VC->new ($changelog_file_name[0]);
  my $vc_name = $vc->name();

  # Key is ChangeLog file name, value is a ref to list of
  # lines added to that file.
  my %added_log_lines;

  # If there is only one file and it's a symlink to a version-controlled
  # ChangeLog in some other directory, then record the version control
  # system it uses, as well as its absolute file name.
  my $symlinked_changelog;
  my $vc_changelog;
  if (@changelog_file_name == 1 && -l $changelog_file_name[0])
    {
      my $log = $changelog_file_name[0];
      eval 'use Cwd';
      die $@ if $@;
      $symlinked_changelog = Cwd::abs_path($log)
        or die "$ME: $log: abs_path failed: $!\n";
      $vc_changelog = VC->new ($symlinked_changelog);
      # Save working directory, chdir to dirname, perform diff, then return.
      do_at (dirname ($symlinked_changelog),
             sub {
               $added_log_lines{$log}
                 = get_new_changelog_lines ($vc_changelog,
                                            basename $symlinked_changelog)});
    }
  else
    {
      # Extract added lines from each ChangeLog.
      foreach my $log (@changelog_file_name)
        {
          $added_log_lines{$log} = get_new_changelog_lines $vc, $log;
        }
    }
  $dry_run
    and exit 0;

  foreach my $log (@changelog_file_name)
    {
      my $line_list = $added_log_lines{$log};
      if (@$line_list == 0)
        {
          warn "$ME: no $log diffs?\n";
          $fail = 1;
        }
    }
  $fail
    and exit 1;

  # Construct the log message.
  my @log_msg_lines;

  # Collect the list of affected files, retaining the order in which they
  # they appear in the ChangeLog, but ignoring duplicates.
  # Then, the diff output (using this list of files) has the same ordering.
  my %seen_affected_file;
  my @affected_files;

  foreach my $log (@changelog_file_name)
    {
      my @log_lines = @{$added_log_lines{$log}};

      # The first one is always a reference.
      my $offset = shift @log_lines;
      $offset = $$offset;

      # If the first line matches "date  name  email" (for now, just
      # check for date), and it's my name, then ignore the line.  e.g.,
      # 2006-08-19  Jim Meyering  <jim@meyering.net>
      # Ignore the following one, too, which should be blank.
      my $n_log_lines = @log_lines;
      if (3 <= $n_log_lines)
        {
          if ($log_lines[0] =~ /^\+\d{4}-\d\d-\d\d  (.*)/)
            {
              my $name_and_email = $1;
              check_attribution $name_and_email, \$author;
              shift @log_lines;

              # Accept and ignore a second ChangeLog attribution line.  E.g.,
              # 2006-09-29  user one  <u1@example.org>
              #         and user two  <u2@example.org>
              # The "and " on the second line is optional.
              $log_lines[0] =~ /^\+\t(?:and )?[^<]+<.*>$/
                and shift @log_lines;

              if ($log_lines[0] ne '+')
                {
                  $log_lines[0] =~ s/^\+//;
                  die "$ME:$log: unexpected, non-blank line after first:\n"
                    . $log_lines[0] . "\n";
                }
              shift @log_lines;
              $offset += ($n_log_lines - @log_lines);
            }
          elsif ($log_lines[@log_lines-2] =~ /^\+\d{4}-\d\d-\d\d  (.*)/
                 && $log_lines[@log_lines-1] =~ /^\+ ?$/)
            {
              # Handle the case in which the latest ChangeLog entry
              # has a header that is identical to the previous one.
              # That could result in diff output like this:
              #
              # @@ -1,3 +1,7 @@
              #  2011-03-04  Joe Random  <jr@example.com>
              #
              # +       * x: y
              # +
              # +2011-03-04  Joe Random  <jr@example.com>
              # +
              #
              # Before the 2011-05-05 fix, vc-dwim would include
              # that header line at the end of the commit log.
              pop @log_lines;
              pop @log_lines;
            }
        }

      # FIXME: now that we have this find_author function,
      # consider removing the kludge above.
      $author ||= find_author $log, $offset;

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

      my $in_summary_lines = 1;
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

                  if (! defined $file)
                    {
                      # Don't complain if it looks like an indented
                      # ChangeLog date line.
                      if ($in_summary_lines || $line =~ /^\t\d{4}-\d\d-\d\d  /)
                        {
                          # don't even warn
                        }
                      else
                        {
                          die "$ME: $log:$offset: cannot find name of "
                            . "file in block containing this line:\n$line\n";
                        }
                    }

                  # If this is a summary line, don't modify it.
                  # Otherwise, add the "* $file" prefix, using the name
                  # we've just derived, for the log message.
                  if (! $is_summary_line)
                    {
                      $in_summary_lines = 0;
                      my $colon = ($line =~ /^\(.+?\)(?:\s*\[.+?\])?: /
                                   ? '' : ':');
                      $line = "* $file$colon $line";
                    }
                }
            }
          undef $offset;

          if ($line =~ /^\*/)
            {
              $line =~ /^\* (\S.*?(:|\)$))/
                or die "$ME:$log: line of unexpected form:\n$line";
              my $f_spec = $1;
              foreach my $file (change_log_line_extract_file_list ($f_spec))
                {
                  my $rel_file = ($rel_dir eq '.' ? $file : "$rel_dir/$file");
                  exists $seen_affected_file{$rel_file}
                    or push @affected_files, $rel_file;
                  $seen_affected_file{$rel_file} = 1;
                }
            }
        }
      continue
        {
          push @log_msg_lines, $line if ! ref $line;
        }
    }

  # print "affected files:\n", join ("\n", @affected_files), "\n";

  @affected_files == 0
    and die "$ME: no files specified in ChangeLog diffs\n";

  # Note: this block is a duplicate of one above, except here we can't
  # check for existence, since a file may be "$vc_name-removed".
  foreach my $f (@affected_files)
    {
      my $edit_tmp = exists_editor_backup $f;
      defined $edit_tmp
        and (warn "$ME: $f has unsaved changes: $edit_tmp\n"), $fail = 1, next;
    }
  $fail
    and exit 1;

  # Collect diffs of non-ChangeLog files.
  # But don't print diff output unless we're sure everything is ok.
  my $diff_lines = get_diffs $vc, \@affected_files, 1;

  cross_check $vc, \@affected_files, $diff_lines;

  print join ("\n", @log_msg_lines), "\n";

  # If a user's diff settings may produce non-default-formatted diffs,
  # then recompute those diffs now, but using their settings (not pristine).
  $vc->diff_is_pristine
    or $diff_lines = get_diffs $vc, \@affected_files, 0;

  print join ("\n", @$diff_lines), "\n";

  # FIXME: add an option to take ChangeLog-style lines from a file,
  # rather than always requiring them to come from a diff.

  # Check in the listed ChangeLog files and all derived ones.
  if ($commit)
    {
      # Pull in this module only if we'll use it.
      eval 'use File::Temp';
      die $@ if $@;

      if ($symlinked_changelog)
        {
          do_commit $vc, $author, \@log_msg_lines, [@affected_files];
          do_at (dirname ($symlinked_changelog),
                 sub { do_commit ($vc_changelog, $author,
                                  ['non-empty-commit-msg'],
                                  [basename ($symlinked_changelog)])});
        }
      else
        {
          do_commit $vc, $author, \@log_msg_lines,
            [@changelog_file_name, @affected_files];
        }
    }

  # Warn if the first line of the log starts with "* ".
  # That indicates a missing one-line summary.
  $log_msg_lines[0] =~ /^\* /
    and warn "$ME: $changelog_file_name[0]: no one-line summary\n";
}

main();

__END__

###############################################################################
#
# Documentation
#

=head1  NAME

vc-dwim - use new ChangeLog entries to direct and cross-check a
version-control "diff" or "commit" command

=head1  SYNOPSIS

B<vc-dwim> [OPTIONS] [CHANGELOG_FILE...]

B<vc-dwim> [OPTIONS] --commit CHANGELOG_FILE...

B<vc-dwim> [OPTIONS] --diff [FILE...]

B<vc-dwim> [OPTIONS] --print-vc-list

B<vc-dwim> [OPTIONS] --initialize

=head1  DESCRIPTION

By default, each command line argument should specify a locally modified,
version-controlled ChangeLog file.  If there is no command line argument,
B<vc-dwim> tries to use the ChangeLog file in the current directory.
In this default mode, B<vc-dwim> works by first computing diffs of those
files and parsing the
diff output to determine which named files are being changed.
Then, it diffs the affected files and prints the resulting output.  One
advantage of using this tool is that before printing any diffs, it warns
you if it sees that a ChangeLog or an affected file has unsaved changes.
It detects that by searching for an editor temporary file corresponding
to each affected file.  Another common error you can avoid with this
tool is the one where you create a new file, add its name to Makefiles,
etc., mention the addition in ChangeLog, but forget to e.g., "git add"
(or "hg add", etc.) the file to the version control system.  B<vc-dwim>
detects this discrepancy and fails with a diagnostic explaining the
probable situation.  You might also have simply mistyped the file name
in the ChangeLog.

Once you are happy with your ChangeLog-derived diffs, you can commit
those changes and the ChangeLog simply by rerunning the command with
the --commit option.

But what if you'd like to use B<vc-dwim> on a project that doesn't have
or want a ChangeLog file?  In that case, you can maintain your own,
private, version-controlled ChangeLog file in a different hierarchy.
Then just make a symlink to it from the top level directory of the
hierarchy in which you'd like to use it and everything should work.
Your private ChangeLog file need not even use the same version control
system as the rest of the project hierarchy.

=head1  OPTIONS

=over 4

=item B<--commit>

perform the commit, too

=item B<--author="User Name <user@example.orgE<gt>">

Specify the user name and email address of the author
of this change set.

=item B<--diff>

Determine which version control system manages the first
FILE, then use that to print diffs of the named FILEs.
If no FILE is specified, print all diffs for the current
hierarchy.

=item B<--print-vc-list>

Print the list of recognized version control names, then exit.

=item B<--initialize>

This option, or the equivalent operations, is needed in a project that
does not version-control a ChangeLog file. Use this option in the
top-level project directory to create your personal ChangeLog file --
that file will be a symlink to a git-version-controlled ChangeLog file
in a just-created single-file repository residing in the VC admin
directory (.git, .hg, etc.). If there is an existing C<ChangeLog> file
in the top-level directory, running B<vc-dwim --initialize> first
renames it to C<ChangeLog~>.

=item B<--help>

Display this help and exit.

=item B<--version>

Output version information and exit.

=item B<--verbose>

Generate verbose output.

=item B<--debug>

Generate debug output.

=back

=head1  RESTRICTIONS

This tool can be useful to you only if you use a version control system.
It's most useful if you maintain a ChangeLog file and create a log entry
per file per "commit" operation.

Relies on fairly strict adherence to recommended ChangeLog syntax.
Detects editor temporaries created by Emacs and Vim.
Eventually, it will detect temporaries created by other editors.

=head1  AUTHOR

Jim Meyering <jim@meyering.net>

Report bugs and all other discussion to <@PACKAGE_BUGREPORT@>.

GNU <@PACKAGE_NAME> home page: &lt;https://www.gnu.org/software/<@PACKAGE_NAME>/&gt;

General help using GNU software: <https://www.gnu.org/gethelp/>

=cut

## Local Variables:
## indent-tabs-mode: nil
## End:
