#!/usr/local/bin/perl
# Run a mailman CGI program, and display output ONLY

chdir("..");		# Cause we are in a sub-directory
delete($ENV{'HTTP_REFERER'});	# So that links from webmail work
$trust_unknown_referers = 1;
require './virtualmin-mailman-lib.pl';
if ($ENV{'PATH_INFO'} =~ /^\/([^\/]+)(.*)/) {
	$lname = $1;
	}
elsif ($ENV{'PATH_INFO'} eq '' || $ENV{'PATH_INFO'} eq '/') {
	# No list name
	$lname = '';
	}
else {
	&error($text{'edit_eurl'});
	}
$prog = $ENV{'SCRIPT_NAME'};
$prog =~ s/^.*\///;
$prog =~ s/\.cgi$//;

@lists = &list_lists();
if ($lname) {
	# Get the list, and from it the domain
	($list) = grep { $_->{'list'} eq $lname } @lists;
	$list && &can_edit_list($list) || &error($text{'edit_ecannot'});
	$list->{'dom'} || &error(&text('edit_edmailman2', $lname));
	$d = &virtual_server::get_domain_by("dom", $list->{'dom'});
	}
else {
	# Get the domain from the URL
	$dname = $ENV{'HTTP_HOST'};
	$dname =~ s/:\d+$//;
	$d = &virtual_server::get_domain_by("dom", $dname);
	if (!$d) {
		$dname =~ s/^(www|ftp|mail|lists)\.//i;
		$d = &virtual_server::get_domain_by("dom", $dname);
		}
	}
$d || &error(&text('edit_edname', &html_escape($dname)));
$d->{$module_name} || &error(&text('edit_edmailman', $dname));

$cgiuser = &get_mailman_apache_user($d);
if ($config{'rewriteurl'}) {
	# Custom URL for Mailman, perhaps if behind proxy
	($httphost, $httpport, $httppage, $httpssl) =
		&parse_http_url($config{'rewriteurl'});
	$httphost .= ":".$httpport if ($httpport != ($httpssl ? 443 : 80));
	$prot = $httpssl ? "https" : "http";
	}
else {
	# Same as supplied by browser
	$httphost = $ENV{'HTTP_HOST'};
	if ($httphost !~ /:\d+$/) {
		# Need to add the port
		$httphost .= ":".$ENV{'SERVER_PORT'};
		}
	$prot = $ENV{'HTTPS'} eq 'ON' ? "https" : "http";
	}

# Work out possible hostnames for URLs
@realhosts = ( &get_system_hostname(),
	       (map { $_->{'dom'} } grep { $_->{$module_name} }
			&virtual_server::list_domains()) );

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
$textarea = 0;
open(CGI, "$cmd <$temp |");
while(<CGI>) {
	# Check if we are in a textarea
	if (/<textarea/i) { $textarea = 1; }
	if (/<\/textarea/i) { $textarea = 0; }

	# Replace URLs, if not in input fields
	if (!/<input.*type=\S*text/i && !$textarea) {
		if (!/\.(gif|png|jpg|jpeg)/) {
			s/\/(cgi-bin\/)?mailman\/([^\/ "']+)\.cgi/\/$module_name\/unauthenticated\/$2.cgi/g || s/\/(cgi-bin\/)?mailman\/([^\/ "']+)([\/ "'])/\/$module_name\/unauthenticated\/$2.cgi$3/g;
			}
		if (!/pipermail/) {
			foreach $realhost (@realhosts) {
				s/(http|https):\/\/$realhost\//$prot:\/\/$httphost\//g && last;
				}
			s/(http|https):\/\/(lists\.)?$d->{'dom'}\//$prot:\/\/$httphost\//g;
			}
		}
	if (/^Set-Cookie:/i) {
		s/(\/cgi-bin)?\/mailman/\/$module_name\/unauthenticated/g;
		}
	s/\/(icons|mailmanicons|images)\/(mailman\/)?(\S+\.(gif|png|jpg|jpeg))/\/$module_name\/unauthenticated\/icons.cgi\/$3/g;
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


