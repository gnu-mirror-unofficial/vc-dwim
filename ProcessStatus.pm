# ProcessStatus - given an exit code, return descriptive string

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

package ProcessStatus;

use strict;
use warnings;

use Carp;
use Config;

###############################################################################
# BEGIN user-configurable section

# (exportable): name of magic tied variable containing our return value
our $PROCESS_STATUS;

# Name of each signal (filled in below from %Config)
our @sig_name;

# END   user-configurable section
###############################################################################

# Program name of our caller
(our $ME = $0) =~ s|.*/||;

# RCS id, accessible to our caller via "$<this_package>::VERSION"
(our $VERSION = '$Revision: 1.1 $ ') =~ tr/[0-9].//cd;

# For non-OO exporting of code, symbols
our @ISA         = qw(Exporter);
our @EXPORT      = qw();
our @EXPORT_OK   = qw(process_status $PROCESS_STATUS);
our %EXPORT_TAGS =   (all => \@EXPORT_OK);


###############################################################################
# BEGIN helper function

#####################
#  _find_sig_names  #  Initialize the mapping from sig number to its name
#####################
sub _find_sig_names() {
    # Only run once
    return if @sig_name;

    # Sanity tests; not expected to fail
    for my $key (qw(sig_num sig_name)) {
	exists $Config{$key}
	  or die "$ME: Internal error: no \$Config{$key}";
    }

    # (copied almost verbatim from Config(3) man page): for each known signal,
    # identify its numeric value and set the corresponding @sig_name element.
    my @names = split ' ', $Config{sig_name};
    my %sig_num;
    @sig_num{@names} = split ' ', $Config{sig_num};
    foreach my $name (@names) {
	$sig_name[$sig_num{$name}] ||= $name;
    }
}

# END   helper function
###############################################################################
# BEGIN code that does the real work

####################
#  process_status  #  Given a system exit status, return a descriptive string
####################
sub process_status($) {
    my $rc = shift;

    # (Should never happen: we're only supposed to be invoked on error)
    $rc == 0
      and return "OK";

    # Exit status 255 is used by Perl to indicate a 'die'.
    # FIXME: is this really always true?
    if ($rc == 0xFF00) {
	my $msg = "died";

	# FIXME: If $! (errno) is set, assume that it's meaningful
	$msg .= ": $!"	if $!;
	return $msg;
    }

    # Exit status 1 .. 127 is a signal (0x80 set means core dumped)
    if ($rc < 0x100) {
	_find_sig_names;	# Make sure @sig_name array is initialized

	my $sig_num     = $rc & 0x7F;
	my $dumped_core = $rc & 0x80;

	my $msg = "killed with ";
	if (my $name = $sig_name[$sig_num]) {
	    $msg .= "SIG$name";
	}
	else {
	    $msg .= sprintf "unknown signal %d", $sig_num;
	}

	$dumped_core
	  and $msg .= " (core dumped)";

	return $msg;
    }

    # Anything else (256 & up) is an exit status, which we must right-shift
    # in order to get to the range 1 .. &c
    return sprintf "terminated with exit status %d", $rc >> 8;
}

# END   code that does the real work
###############################################################################
# BEGIN code for handling 'tie'

###############
#  TIESCALAR  #  Called just once, when initializing
###############
sub TIESCALAR {
    my $class = shift;
    my $self  = "";

    return bless \$self, $class;
}


###########
#  STORE  #  Set value.  Normally prohibited, but allowed for debugging.
###########
sub STORE {
    my $self = shift;

    # Error message to croak with (except when debugging)
    my $prohibited = "Modification of a read-only value attempted";

    # For debugging, allow caller to give us a hashref with '$?' and '$!'
    my $new_val = shift;
    ref $new_val eq 'HASH'	or croak $prohibited;
    keys %$new_val == 2		or croak $prohibited;
    exists $new_val->{'$?'}	or croak $prohibited;
    exists $new_val->{'$!'}	or croak $prohibited;

    # Debugging, and all looks good.  Use these values on next FETCH.
    $$self = $new_val;
}


###########
#  FETCH  #  Returns value of error string
###########
sub FETCH {
    my $self = shift;

    # Cannot write to '$?', so let's use temp var in case of debugging.
    my $rc = $?;

    # (for debugging): use previously STOREd values of $! and $?
    if (ref $$self) {
	$!  = ${$self}->{'$!'};
	$rc = ${$self}->{'$?'};

	# Reset: next invocation will revert back to real $! and $?
	$$self = "";
    }

    # Errno set?  Return the stringified error message.
    if ($!) {
	return "$!";
    }

    # No errno.  Return stringified exit status (usually not as helpful as $!)
    return process_status( $rc );
}

# END   code for processing 'tie'
###############################################################################
# BEGIN the last step: actually do the 'tie'

tie $PROCESS_STATUS, __PACKAGE__;

# END   the last step: actually do the 'tie'
###############################################################################

1;



###############################################################################
#
# Documentation
#

__END__

=head1	NAME

ProcessStatus - human-readable process exit status

=head1	SYNOPSIS

    use ProcessStatus qw($PROCESS_STATUS);

    my @cmd = qw(mycommand -f flag arg1);
    system @cmd
      or die "Error running '$cmd': $PROCESS_STATUS\n";

=head1	DESCRIPTION

B<ProcessStatus> provides a human-friendly interpretation
of a program exit status.  It is intended to be run after an error
from C<system()> or after a C<close()> on a pipe.

ProcessStatus exports (but not by default!) a scalar
variable $PROCESS_STATUS, which can be interpolated into strings.
Typical values of this variable will be:

    killed with SIGSEGV
    terminated with exit status 1
    No such file or directory (usually if "$!" is set)

=head1	BUGS

We should probably do this, from perlfunc(1):

    or more portably by using the W*() calls of the
    POSIX extension; see perlport for more informa­
    tion.


=head1	AUTHOR

Ed Santiago <esm@edsantiago.com>

=cut
