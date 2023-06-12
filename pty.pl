#!/usr/local/bin/perl
# Run some command in a PTY. Used for Xen console.
# Only works on Linux!

use POSIX;

# Delay before each input line
if ($ARGV[0] eq "--sleep") {
	shift(@ARGV);
	$sleeptime = shift(@ARGV);
	}

($ptyfh, $ttyfh, $pty, $tty) = &get_new_pty();
$ptyfh || die "Failed to create new PTY";
$pid = fork();
if (!$pid) {
	&close_controlling_pty();
	setsid();

	if (!$ttyfh) {
		# Needs to be opened, as get_new_pty on linux cannot do
		# this so soon
		$ttyfh = "TTY";
		open($ttyfh, "+<$tty") || die "Failed to open $tty : $!";
		}

	&open_controlling_pty($ptyfh, $ttyfh, $pty, $tty);
	close(STDIN); close(STDOUT); close(STDERR);
	open(STDIN, "<$tty") || die "Failed to reset STDIN : $!";
	open(STDOUT, ">&$ttyfh") || die "Failed to reset STDOUT : $!";
	open(STDERR, ">&STDOUT");
	close($ptyfh);
	exec(@ARGV);
	die "Exec failed : $!\n";
	}
print "PTY PID: $pid\n";
$| = 1;
select($ptyfh); $| = 1; select(STDOUT);
&forward_connection_sockets(STDIN, STDOUT, $ptyfh, $ptyfh);
waitpid($pid, 0);
exit($? / 256);

sub forward_connection_sockets
{
my ($in1, $out1, $in2, $out2) = @_;
my ($closed1, $closed2);
while(1) {
	my $rmask = undef;
	vec($rmask, fileno($in1), 1) = 1 if (!$closed1);
	vec($rmask, fileno($in2), 1) = 1 if (!$closed2);
	my $sel = select($rmask, undef, undef, 10);
	if (vec($rmask, fileno($in1), 1)) {
		# Got something from stdin
		my $buf;
		$ok = sysread($in1, $buf, 1024);
		if ($ok <= 0) {
			$closed1 = 1;
			}
		else {
			if ($sleeptime) {
				# Split into lines, sleep between each one
				sleep($sleeptime);
				my @lines = split(/\n/, $buf);
				foreach my $l (@lines) {
					sleep($sleeptime);
					syswrite($out2, $l."\n", length($l)+1)
						|| last;
					}
				}
			else {
				syswrite($out2, $buf, length($buf)) || last;
				}
			}
		}
	if (vec($rmask, fileno($in2), 1)) {
		# Got something from command
		my $buf;
		$ok = sysread($in2, $buf, 1024);
		if ($ok <= 0) {
			$closed2 = 1;
			}
		else {
			syswrite($out1, $buf, length($buf)) || last;
			}
		}
	last if ($closed1 && $closed2);
	}
}



# get_new_pty()
# Returns the filehandles and names for a pty and tty
sub get_new_pty
{
if (-r "/dev/ptmx" && -d "/dev/pts" && open(PTMX, "+>/dev/ptmx")) {
	# Can use new-style PTY number allocation device
	my $unl;
	my $ptn;

	# ioctl to unlock the PTY (TIOCSPTLCK)
	$unl = pack("i", 0);
	ioctl(PTMX, 0x40045431, $unl) || die "Unlock ioctl failed : $!";
	$unl = unpack("i", $unl);

	# ioctl to request a TTY (TIOCGPTN)
	ioctl(PTMX, 0x80045430, $ptn) || die "PTY ioctl failed : $!";
	$ptn = unpack("i", $ptn);

	my $tty = "/dev/pts/$ptn";
	return (*PTMX, undef, $tty, $tty);
	}
else {
	# Have to search manually through pty files!
	my @ptys;
	my $devstyle;
	if (-d "/dev/pty") {
		opendir(DEV, "/dev/pty");
		@ptys = map { "/dev/pty/$_" } readdir(DEV);
		closedir(DEV);
		$devstyle = 1;
		}
	else {
		opendir(DEV, "/dev");
		@ptys = map { "/dev/$_" } (grep { /^pty/ } readdir(DEV));
		closedir(DEV);
		$devstyle = 0;
		}
	my ($pty, $tty);
	foreach $pty (@ptys) {
		open(PTY, "+>$pty") || next;
		my $tty = $pty;
		if ($devstyle == 0) {
			$tty =~ s/pty/tty/;
			}
		else {
			$tty =~ s/m(\d+)$/s$1/;
			}
		my $old = select(PTY); $| = 1; select($old);
		if ($< == 0) {
			# Don't need to open the TTY file here for root,
			# as it will be opened later after the controlling
			# TTY has been released.
			return (*PTY, undef, $pty, $tty);
			}
		else {
			# Must open now ..
			open(TTY, "+>$tty");
			select(TTY); $| = 1; select($old);
			return (*PTY, *TTY, $pty, $tty);
			}
		}
	return ();
	}
}

# close_controlling_pty()
# Disconnects this process from it's controlling PTY, if connected
sub close_controlling_pty
{
if (open(DEVTTY, "/dev/tty")) {
	# Special ioctl to disconnect (TIOCNOTTY)
	ioctl(DEVTTY, 0x5422, 0);
	close(DEVTTY);
	}
}

# open_controlling_pty(ptyfh, ttyfh, ptyfile, ttyfile)
# Makes a PTY returned from get_new_pty the controlling TTY (/dev/tty) for
# this process.
sub open_controlling_pty
{
my ($ptyfh, $ttyfh, $pty, $tty) = @_;

# Call special ioctl to attach /dev/tty to this new tty (TIOCSCTTY)
ioctl($ttyfh, 0x540e, 0);
}


