#!/usr/local/bin/perl
# Run a mailman CGI program, and display output ONLY

chdir("..");		# Cause we are in a sub-directory
require './virtualmin-mailman-lib.pl';
$ENV{'PATH_INFO'} =~ /^\/([^\/]+)(.*)/ ||
	&error($text{'edit_eurl'});
$list = $1;
$prog = $ENV{'SCRIPT_NAME'};
$prog =~ s/^.*\///;
$prog =~ s/\.cgi$//;

@lists = &list_lists();
($list) = grep { $_->{'list'} eq $list } @lists;
&can_edit_list($list) || &error($text{'edit_ecannot'});
$d = &virtual_server::get_domain_by("dom", $list->{'dom'});

$cgiuser = &get_mailman_apache_user($d);
$realhost = &get_system_hostname();
$httphost = $ENV{'HTTP_HOST'};
if ($httphost !~ /:\d+$/) {
	# Need to add the port
	$httphost .= ":".$ENV{'SERVER_PORT'};
	}

$temp = &transname();
open(TEMP, ">$temp");
if (defined(&read_fully)) {
	&read_fully(STDIN, \$qs, $ENV{'CONTENT_LENGTH'});
	}
else {
	read(STDIN, $qs, $ENV{'CONTENT_LENGTH'});
	}
print TEMP $qs;
close(TEMP);
$cmd = &command_as_user($cgiuser, 0, "$mailman_dir/cgi-bin/$prog");
$prot = $ENV{'HTTPS'} eq 'ON' ? "https" : "http";
open(CGI, "$cmd <$temp |");
while(<CGI>) {
	if (!/<input.*type=\S*text/i) {
		if (s/\/(cgi-bin\/)?mailman\/([^\/ "']+)\.cgi/\/$module_name\/unauthenticated\/$2.cgi/g == 0) {
			s/\/(cgi-bin\/)?mailman\/([^\/ "']+)/\/$module_name\/unauthenticated\/$2.cgi/g;
			}
		s/(http|https):\/\/$realhost\//$prot:\/\/$httphost\//g;
		s/(http|https):\/\/(lists\.)?$d->{'dom'}\//$prot:\/\/$httphost\//g;
		}
	if (/^Set-Cookie:/i) {
		s/\/mailman/\/$module_name\/unauthenticated/g;
		}
	s/\/icons\/(\S+\.(gif|png|jpg|jpeg))/\/$module_name\/unauthenticated\/icons.cgi\/$1/g;
	if (/^(\S+):\s*(.*)\r?\n$/ && !$doneheaders) {
		$headers .= $_;
		}
	elsif (/^\r?\n/) {
		$doneheaders = 1;
		}
	else {
		$body .= $_;
		}
	}
close(CGI);

print $headers;
print "\n";
print $body;


