# Functions for setting up mailman mailing lists, for a virtual domain

do '../web-lib.pl';
&init_config();
do '../ui-lib.pl';
&foreign_require("virtual-server", "virtual-server-lib.pl");

%pconfig = &foreign_config("postfix");
if ($pconfig{'postfix_config_file'} =~ /^(.*)\//) {
        $postfix_dir = $1;
        }
else {
        $postfix_dir = "/etc/postfix";
        }
@mailman_aliases = ( "post", "admin", "bounces", "confirm", "join",
		     "leave", "owner", "request", "subscribe", "unsubscribe" );

$mailman_dir = $config{'mailman_dir'} || "/usr/local/mailman";
$mailman_var = $config{'mailman_var'} || $mailman_dir;
$newlist_cmd = "$mailman_dir/bin/newlist";
$rmlist_cmd = "$mailman_dir/bin/rmlist";
$mailman_cmd = $config{'mailman_cmd'} || "$mailman_dir/bin/mailman";
if (!-x $mailman_cmd && $config{'alt_mailman_cmd'}) {
	# Hack needed to handle CentOS 4
	$mailman_cmd = $config{'alt_mailman_cmd'};
	}
$changepw_cmd = "$mailman_dir/bin/change_pw";
$config_cmd = "$mailman_dir/bin/config_list";
$lists_dir = "$mailman_var/lists";
$archives_dir = "$mailman_var/archives";
$maillist_map = "relay_domains";
$maillist_file = "$postfix_dir/maillists";
$transport_map = "transport_maps";
$cgi_dir = "$mailman_dir/cgi-bin";
$icons_dir = "$mailman_dir/icons";
$mailman_config = "$mailman_var/Mailman/mm_cfg.py";
if (!-r $mailman_config) {
	$mailman_config = "$mailman_dir/Mailman/mm_cfg.py";
	}

%access = &get_module_acl();

$lists_file = "$module_config_directory/list-domains";

sub get_mailman_version
{
local $out = `$mailman_dir/bin/version 2>/dev/null </dev/null`;
if ($out =~ /version\s+(\S+)/i || $out =~ /version:\s+(\S+)/i) {
	return $1;
	}
return undef;
}

# list_lists()
# Returns a list of mailing lists and domains and descriptions
sub list_lists
{
local @rv;
local %lists;
&read_file($lists_file, \%lists);
opendir(DIR, $lists_dir);
local $f;
while($f = readdir(DIR)) {
	next if ($f eq "." || $f eq "..");
	local ($dom, $desc) = split(/\t+/, $lists{$f}, 2);
	push(@rv, { 'list' => $f,
		    'dom' => $dom,
		    'desc' => $desc });
	}
closedir(DIR);
return @rv;
}

# can_edit_list(&list)
sub can_edit_list
{
foreach $d (split(/\s+/, $access{'dom'})) {
	return 1 if ($d eq "*" || $d eq $_[0]->{'dom'});
	}
return 0;
}

sub mailman_check
{
return &text('feat_emailmancmd', "<tt>$mailman_cmd</tt>")
	if (!&has_command($mailman_cmd));
return &text('feat_emailman', "<tt>$mailman_dir</tt>")
	if (!-d $mailman_dir || !-d "$mailman_dir/bin");
return &text('feat_emailman2', "<tt>$mailman_var</tt>")
	if (!-d $mailman_var || !-d "$mailman_var/lists");
if ($config{'mode'} == 0) {
	# Check special postfix files
	return &text('feat_efile', "<tt>$maillist_file</tt>")
		if (!-r $maillist_file);
	local %vconfig = &foreign_config("virtual-server");
	return $text{'feat_epostfix'} if ($vconfig{'mail_system'} != 0);
	&foreign_require("postfix", "postfix-lib.pl");
	local @files = &postfix::get_maps_files(
			&postfix::get_real_value($transport_map));
	return $text{'feat_etransport'} if (!@files);
	local @files = &postfix::get_maps_files(
			&postfix::get_real_value($maillist_map));
	return $text{'feat_emaillist'} if (!@files);
	}
# Make sure the www user has a valid shell, for use with su. Not needed on
# Linux, as we can pass -s to the su command.
if ($gconfig{'os_type'} !~ /-linux$/) {
	local $user = &get_mailman_apache_user();
	local @uinfo = getpwnam($user);
	if (@uinfo && $uinfo[8] =~ /nologin/) {
		return &text('feat_emailmanuser', "<tt>$user</tt>", "<tt>$uinfo[8]</tt>");
		}
	}
return undef;
}

# create_list(name, domain, desc, language, email, pass)
# Create a new mailing list, and returns undef on success or an error
# message on failure.
sub create_list
{
local ($list, $dom, $desc, $lang, $email, $pass) = @_;

# Make sure our hostname is set properly
local $conf = &get_mailman_config();
foreach my $c ("DEFAULT_URL_HOST", "DEFAULT_EMAIL_HOST") {
	local $url = &find_value($c, $conf);
	if ($url && $url =~ /has_not_been_edited/) {
		&save_directive($conf, $c, &get_system_hostname());
		}
	}

# Construct and call the list creation command
local @args = ( $newlist_cmd );
if ($lang) {
	push(@args, "-l", $lang);
	}
if (&get_mailman_version() < 2.1) {
	push(@args, $list);
	}
elsif (!$dom) {
	push(@args, $list);
	}
elsif ($config{'mode'} == 0) {
	push(@args, "$list\@lists.$dom");
	}
else {
	push(@args, "$list\@$dom");
	}
push(@args, $email);
push(@args, $pass);
local $cmd = join(" ", map { $_ eq '' ? '""' : quotemeta($_) } @args);
local $out = &backquote_logged("$cmd 2>&1 </dev/null");
if ($?) {
	return &text('add_ecmd', "<pre>".&html_escape($out)."</pre>");
	}

if ($dom) {
	# Save domain and description
	&read_file($lists_file, \%lists);
	$lists{$list} = $dom."\t".$desc;
	&write_file($lists_file, \%lists);
	}

if ($config{'mode'} == 1) {
	# Add aliases
	local $a;
	foreach $a (@mailman_aliases) {
		local $virt = { 'from' => ($a eq "post" ? $list :
					   "$list-$a")."\@".$dom,
				'to' => [ "|$mailman_cmd $a $list" ] };
		&virtual_server::create_virtuser($virt);
		}
	# Sync alias copy virtusers, if supported
	local $d = &virtual_server::get_domain_by("dom", $dom);
	if ($d && defined(&virtual_server::sync_alias_virtuals)) {
		&virtual_server::sync_alias_virtuals($d);
		}
	}
return undef;
}

# delete_list(name, domain)
sub delete_list
{
local ($list, $dom) = @_;

# Run the remove command
local $out = &backquote_logged("$rmlist_cmd $list 2>&1 </dev/null");
if ($?) {
	return "<pre>$out</pre>";
	}

# Delete from domain map
&read_file($lists_file, \%lists);
delete($lists{$list});
&write_file($lists_file, \%lists);

if ($config{'mode'} == 1) {
	# Remove aliases
	local $d = &virtual_server::get_domain_by("dom", $dom);
	local @virts = &virtual_server::list_domain_aliases($d);
	local $a;
	foreach $a (@mailman_aliases) {
		local $vn = ($a eq "post" ? $list
					  : "$list-$a")."\@".$dom;
		local ($virt) = grep { $_->{'from'} eq $vn } @virts;
		if ($virt) {
			&virtual_server::delete_virtuser($virt);
			}
		}
	# Sync alias copy virtusers, if supported
	if (defined(&virtual_server::sync_alias_virtuals)) {
		&virtual_server::sync_alias_virtuals($d);
		}
	}
}

# list_members(&list)
# Returns an array of user structures for some list
sub list_members
{
local @rv;
open(MEMS, "$mailman_dir/bin/list_members -r $_[0]->{'list'} |");
while(<MEMS>) {
	s/\r|\n//g;
	push(@rv, { 'email' => $_, 'digest' => 'n' });
	}
close(MEMS);
open(MEMS, "$mailman_dir/bin/list_members -d $_[0]->{'list'} |");
while(<MEMS>) {
	s/\r|\n//g;
	push(@rv, { 'email' => $_, 'digest' => 'y' });
	}
close(MEMS);
return sort { $a->{'email'} cmp $b->{'email'} } @rv;
}

# add_member(&member, &list)
# Add one subscriber to a list
sub add_member
{
local $temp = &transname();
local $cmd = "$mailman_dir/bin/add_members";
if ($_[0]->{'digest'} eq 'y') {
	$cmd .= " -d $temp";
	}
else {
	$cmd .= " -n $temp";
	}
if ($_[0]->{'welcome'}) {
	$cmd .= " -w ".$_[0]->{'welcome'};
	}
if ($_[0]->{'admin'}) {
	$cmd .= " -a ".$_[0]->{'admin'};
	}
$cmd .= " $_[1]->{'list'}";
open(TEMP, ">$temp");
print TEMP "$_[0]->{'email'}\n";
close(TEMP);
local $out = &backquote_logged("$cmd <$temp 2>&1");
return $? ? $out : undef;
}

# remove_member(&member, &list)
# Deletes one person from a mailing list
sub remove_member
{
local $temp = &transname();
local $cmd = "$mailman_dir/bin/remove_members -f $temp $_[1]->{'list'}";
open(TEMP, ">$temp");
print TEMP "$_[0]->{'email'}\n";
close(TEMP);
local $out = &backquote_logged("$cmd <$temp 2>&1");
return $? ? $out : undef;
}

sub list_mailman_languages
{
opendir(DIR, "$mailman_dir/templates");
local @rv = grep { $_ !~ /^\./ &&
		   $_ !~ /\.(txt|html)$/i &&
		   -d "$mailman_dir/templates/$_" } readdir(DIR);
closedir(DIR);
return sort { $a cmp $b } @rv;
}

# get_mailman_config()
# Returns an array ref of mailman config options
sub get_mailman_config
{
if (!defined(@mailman_config_cache)) {
	@mailman_config_cache = ( );
	local $lnum = 0;
	open(CONF, $mailman_config);
	while(<CONF>) {
		s/\r|\n//g;
		s/^\s*#.*$//;
		if (/^\s*(\S+)\s*=\s*'(.*)'/ ||
		    /^\s*(\S+)\s*=\s*"(.*)"/ ||
		    /^\s*(\S+)\s*=\s*\S+/) {
			push(@mailman_config_cache,
				{ 'name' => $1,
				  'value' => $2,
				  'line' => $lnum });
			}
		$lnum++;
		}
	close(CONF);
	}
return \@mailman_config_cache;
}

# find(name, &conf)
sub find
{
local ($rv) = grep { $_->{'name'} eq $_[0] } @{$_[1]};
return $rv;
}

# find_value(name, &conf)
sub find_value
{
local $rv = &find(@_);
return $rv ? $rv->{'value'} : undef;
}

# save_directive(&conf, name, value)
# Updates a setting in the mailman config
sub save_directive
{
local ($conf, $name, $value) = @_;
local $old = &find($name, $conf);
local $lref = &read_file_lines($mailman_config);
local $newline;
if (defined($value)) {
	$newline = "$name = ";
	if ($value =~ /^[0-9\.]+$/) {
		$newline .= $value;
		}
	elsif ($value =~ /'/) {
		$newline .= "\"$value\"";
		}
	else {
		$newline .= "'$value'";
		}
	}
if ($old && defined($value)) {
	# Just update
	$lref->[$old->{'line'}] = $newline;
	$old->{'value'} = $value;
	}
elsif ($old && !defined($value)) {
	# Take this value out
	splice(@$lref, $old->{'line'}, 1);
	@$conf = grep { $_ ne $old } @$conf;
	foreach my $c (@$conf) {
		$c->{'line'}-- if ($c->{'line'} > $old->{'line'});
		}
	}
elsif (!$old && defined($value)) {
	# Add a value
	push(@$conf, { 'name' => $name,
		       'value' => $value,
		       'line' => scalar(@$lref) });
	push(@$lref, $newline);
	}
&flush_file_lines($mailman_config);
}

# get_list_config(list)
# Returns the configuration for some list as a hash reference
sub get_list_config
{
local $temp = &transname();
&execute_command("$config_cmd -o $temp $_[0]");
local %rv;
open(CONFIG, $temp);
while(<CONFIG>) {
	s/\r|\n//g;
	s/^\s*#.*$//;
	if (/^\s*(\S+)\s*=\s*'(.*)'/ ||
	    /^\s*(\S+)\s*=\s*"(.*)"/ ||
	    /^\s*(\S+)\s*=\s*(\d+)/) {
		# Single value
		$rv{$1} = $2;
		}
	elsif (/^\s*(\S+)\s*=\s*\[(.*)\]/) {
		# A list of values
		local ($name, $values) = ($1, $2);
		local @values;
		while($values =~ /,?'([^']*)'(.*)/ ||
		      $values =~ /,?"([^"]*)"(.*)/ ||
		      $values =~ /,?(\d+)(.*)/) {
			push(@values, $1);
			$values = $2;
			}
		$rv{$name} = \@values;
		}
	elsif (/^\s*(\S+)\s*=\s*"""/) {
		# Multiline value
		local $name = $1;
		local $value;
		while(1) {
			local $line = <CONFIG>;
			last if (!$line || $line =~ /^"""/);
			if ($line =~ /^(.*)"""/) {
				$value .= $1;
				last;
				}
			else {
				$value .= $line;
				}
			}
		$rv{$name} = $value;
		}
	}
close(CONFIG);
return \%rv;
}

# get_mailman_apache_user([&domain])
sub get_mailman_apache_user
{
local ($d) = @_;
if ($config{'cgiuser'}) {
	return $config{'cgiuser'};
	}
elsif (defined(&virtual_server::get_apache_user)) {
	return &virtual_server::get_apache_user($d);
	}
else {
	foreach my $u ("www", "httpd", "apache") {
		if (defined(getpwnam($u))) {
			return $u;
			}
		}
	return "nobody";
	}
}

1;

