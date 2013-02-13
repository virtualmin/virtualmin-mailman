# Defines functions for this feature

require 'virtualmin-mailman-lib.pl';
$input_name = $module_name;
$input_name =~ s/[^A-Za-z0-9]/_/g;

# feature_name()
# Returns a short name for this feature
sub feature_name
{
return $text{'feat_name'};
}

# feature_losing(&domain)
# Returns a description of what will be deleted when this feature is removed
sub feature_losing
{
return $text{'feat_losing'};
}

# feature_disname(&domain)
# Returns a description of what will be turned off when this feature is disabled
sub feature_disname
{
return $text{'feat_disname'};
}

# feature_label(in-edit-form)
# Returns the name of this feature, as displayed on the domain creation and
# editing form
sub feature_label
{
local ($edit) = @_;
return $edit ? $text{'feat_label2'} : $text{'feat_label'};
}

sub feature_hlink
{
return "label";
}

# feature_check()
# Returns undef if all the needed programs for this feature are installed,
# or an error message if not
sub feature_check
{
my $err = &mailman_check();
return $err if ($err);

# Check if qrunner is running
local $qrunner = "$mailman_dir/bin/qrunner";
if (-x $qrunner) {
	local ($pid) = &find_byname("qrunner");
	if (!$pid) {
		return &text('feat_eqrunner', "<tt>$qrunner</tt>", "/init/");
		}
	}

return undef;
}

# feature_depends(&domain)
# Returns undef if all pre-requisite features for this domain are enabled,
# or an error message if not
sub feature_depends
{
local ($d, $oldd) = @_;
if (&needs_mailman_list() && (!$oldd || !$oldd->{$module_name})) {
	return $text{'feat_emmlist'}.
	       (&virtual_server::master_admin() ? &text('feat_emmlink', "../$module_name/index.cgi") : "");
	}
return $d->{'mail'} || $config{'mode'} == 0 ? undef : $text{'feat_edepmail'};
}

# feature_clash(&domain)
# Returns undef if there is no clash for this domain for this feature, or
# an error message if so
sub feature_clash
{
return undef;
}

# feature_suitable([&parentdom], [&aliasdom], [&subdom])
# Returns 1 if some feature can be used with the specified alias and
# parent domains
sub feature_suitable
{
return $_[1] || $_[2] ? 0 : 1;		# not for alias domains
}

# feature_setup(&domain)
# Called when this feature is added, with the domain object as a parameter
sub feature_setup
{
if ($config{'mode'} == 0) {
	# Add postfix config
	&$virtual_server::first_print($text{'setup_map'});
	&virtual_server::obtain_lock_mail($_[0]);
	&foreign_require("postfix", "postfix-lib.pl");
	&virtual_server::create_replace_mapping($maillist_map,
				 { 'name' => "lists.".$_[0]->{'dom'},
				   'value' => "lists.".$_[0]->{'dom'} },
				 [ $maillist_file ]);
	&postfix::regenerate_any_table($maillist_map,
				       [ $maillist_file ]);
	&virtual_server::create_replace_mapping($transport_map,
				 { 'name' => "lists.".$_[0]->{'dom'},
				   'value' => "mailman:" });
	&postfix::regenerate_any_table($transport_map);
	&virtual_server::release_lock_mail($_[0]);
	&$virtual_server::second_print($virtual_server::text{'setup_done'});
	}

if ($_[0]->{'web'} && !$config{'no_redirects'}) {
	# Add server alias, and redirect for /cgi-bin/mailman and /mailman
	# to anonymous wrappers
	&setup_mailman_web_redirects($_[0]);
	}

# Set default limit from template
if (!exists($_[0]->{$module_name."limit"})) {
	local $tmpl = &virtual_server::get_template($_[0]->{'template'});
	$_[0]->{$module_name."limit"} =
		$tmpl->{$module_name."limit"} eq "none" ? "" :
		 $tmpl->{$module_name."limit"};
	}
}

# feature_modify(&domain, &olddomain)
# Called when a domain with this feature is modified
sub feature_modify
{
if ($_[0]->{'dom'} ne $_[1]->{'dom'}) {
	# Domain has been re-named
	if ($config{'mode'} == 0) {
		# Update filtering
		&feature_delete($_[1], 1);
		&feature_setup($_[0]);
		}

	# Change domain for any lists
	&$virtual_server::first_print($text{'feat_rename'});
	local %lists;
	&lock_file($lists_file);
	&read_file($lists_file, \%lists);
	foreach my $f (keys %lists) {
		local ($dom, $desc) = split(/\t+/, $lists{$f}, 2);
		if ($dom eq $_[1]->{'dom'}) {
			$dom = $_[0]->{'dom'};
			$lists{$f} = join("\t", $dom, $desc);
			local $out = &backquote_logged(
				"$withlist_cmd -l -r fix_url ".
				quotemeta($f)." ".
				"-v -u ".quotemeta($dom)." 2>&1");
			}
		}
	&write_file($lists_file, \%lists);
	&unlock_file($lists_file);
	&$virtual_server::second_print(
		$virtual_server::text{'setup_done'});
	}

# Change owner email, if needed
if ($_[0]->{'emailto'} ne $_[1]->{'emailto'}) {
	&$virtual_server::first_print($text{'feat_email'});
	&read_file($lists_file, \%lists);
	foreach my $f (keys %lists) {
		local ($dom, $desc) = split(/\t+/, $lists{$f}, 2);
                if ($dom eq $_[0]->{'dom'}) {
			# Get the owner email
			my $owner = &get_list_config($f, "owner");
			if ($owner =~ /'\Q$_[1]->{'emailto'}\E'/) {
				$owner =~ s/'\Q$_[1]->{'emailto'}\E'/'$_[0]->{'emailto'}'/g;
				&save_list_config($f, "owner", $owner);
				}
			}
		}
	&$virtual_server::second_print(
		$virtual_server::text{'setup_done'});
	}

# Setup web redirects if website was just enabled
if (!$_[1]->{'web'} && $_[0]->{'web'} && !$config{'no_redirects'}) {
	&setup_mailman_web_redirects($_[0]);
	}
}

# feature_delete(&domain, [keep-lists])
# Called when this feature is disabled, or when the domain is being deleted
sub feature_delete
{
local ($d, $keep) = @_;
if ($config{'mode'} == 0) {
	# Remove postfix config
	&$virtual_server::first_print($text{'delete_map'});
	&foreign_require("postfix", "postfix-lib.pl");
	&virtual_server::obtain_lock_mail($_[0]);
	local $ok = 0;
	local $mmap = &postfix::get_maps($maillist_map, [ $maillist_file ]);
	local ($maillist) = grep { $_->{'name'} eq "lists.".$_[0]->{'dom'} }
				 @$mmap;
	if ($maillist) {
		&postfix::delete_mapping($maillist_map, $maillist);
		&postfix::regenerate_any_table($maillist_map,
					       [ $maillist_file ]);
		$ok++;
		}
	local $tmap = &postfix::get_maps($transport_map);
	local ($trans) = grep { $_->{'name'} eq "lists.".$_[0]->{'dom'} }
			      @$tmap;
	if ($trans) {
		&postfix::delete_mapping($transport_map, $trans);
		&postfix::regenerate_any_table($transport_map);
		$ok++;
		}
	&virtual_server::release_lock_mail($_[0]);
	if ($ok == 2) {
		&$virtual_server::second_print(
			$virtual_server::text{'setup_done'});
		}
	else {
		&$virtual_server::second_print($text{'delete_missing'});
		}
	}

if ($_[0]->{'web'} && !$config{'no_redirects'}) {
	# Remove server alias and redirects
	&$virtual_server::first_print($text{'delete_alias'});
	&virtual_server::require_apache();
	&virtual_server::obtain_lock_web($_[0]);
	local $conf = &apache::get_config();
	local @ports = ( $_[0]->{'web_port'},
			 $_[0]->{'ssl'} ? ( $_[0]->{'web_sslport'} ) : ( ) );
	local $deleted;
	foreach my $p (@ports) {
		local ($virt, $vconf) = &virtual_server::get_apache_virtual(
			$_[0]->{'dom'}, $p);
		next if (!$virt);

		# Remove server alias
		local @sa = &apache::find_directive("ServerAlias", $vconf);
		@sa = grep { $_ ne "lists.$_[0]->{'dom'}" } @sa;
		&apache::save_directive("ServerAlias", \@sa, $vconf, $conf);

		# Remove redirects
		local @rm = &apache::find_directive("RedirectMatch", $vconf);
		foreach my $p ("/cgi-bin/mailman", "/mailman") {
			@rm = grep { !/^\Q$p\E\// } @rm;
			}
		&apache::save_directive("RedirectMatch", \@rm, $vconf, $conf);
		$deleted++;
		}
	if ($deleted) {
		&flush_file_lines();
		&virtual_server::register_post_action(
		    defined(&main::restart_apache) ? \&main::restart_apache
					   : \&virtual_server::restart_apache);
		&$virtual_server::second_print(
			$virtual_server::text{'setup_done'});
		}
	else {
		&$virtual_server::second_print(
			$virtual_server::text{'delete_noapache'});
		}
	&virtual_server::release_lock_web($_[0]);
	}

# Remove mailing lists
if (!$keep) {
	local @lists = grep { $_->{'dom'} eq $_[0]->{'dom'} } &list_lists();
	if (@lists) {
		&$virtual_server::first_print(&text('delete_lists',
						    scalar(@lists)));
		foreach $l (@lists) {
			&delete_list($l->{'list'}, $l->{'dom'});
			}
		&$virtual_server::second_print(
			$virtual_server::text{'setup_done'});
		}
	}
}

# feature_validate(&domain)
# Make sure that needed Apache directives exist
sub feature_validate
{
local ($d) = @_;
if ($d->{'web'}) {
	local ($virt, $vconf) = &virtual_server::get_apache_virtual(
					$d->{'dom'}, $d->{'web_port'});
	if (!$virt) {
		return &text('validate_eweb', $d->{'dom'});
		}
	local @rm = &apache::find_directive_struct("RedirectMatch", $vconf);
	local $webminurl = &get_mailman_webmin_url($d);
	foreach my $p ("/cgi-bin/mailman", "/mailman") {
		local ($rm) = grep { $_->{'words'}->[0] =~ /^\Q$p\E/ } @rm;
		if (!$rm) {
			return &text('validate_eredirect', "<tt>$p</tt>");
			}
		if ($rm->{'words'}->[1] !~ /^\Q$webminurl\E\//) {
			return &text('validate_eredirect2', "<tt>$p</tt>",
				     "<tt>$rm->{'words'}->[1]</tt>",
				     "<tt>$webminurl</tt>");
			}
		}
	}
return undef;
}

# feature_webmin(&main-domain, &all-domains)
# Returns a list of webmin module names and ACL hash references to be set for
# the Webmin user when this feature is enabled
sub feature_webmin
{
local @doms = map { $_->{'dom'} } grep { $_->{$module_name} } @{$_[1]};
if (@doms) {
	return ( [ $module_name,
		   { 'dom' => join(" ", @doms),
		     'max' => $_[0]->{$module_name.'limit'},
		     'noconfig' => 1 } ] );
	}
else {
	return ( );
	}
}

sub feature_modules
{
return ( [ $module_name, $text{'feat_module'} ] );
}

# feature_limits_input(&domain)
# Returns HTML for editing limits related to this plugin
sub feature_limits_input
{
local ($d) = @_;
return undef if (!$d->{$module_name});
return &ui_table_row(&hlink($text{'limits_max'}, "limits_max"),
	&ui_opt_textbox($input_name."limit", $d->{$module_name."limit"},
			4, $virtual_server::text{'form_unlimit'},
			   $virtual_server::text{'form_atmost'}));
}

# feature_limits_parse(&domain, &in)
# Updates the domain with limit inputs generated by feature_limits_input
sub feature_limits_parse
{
local ($d, $in) = @_;
return undef if (!$d->{$module_name});
if ($in->{$input_name."limit_def"}) {
	delete($d->{$module_name."limit"});
	}
else {
	$in->{$input_name."limit"} =~ /^\d+$/ || return $text{'limit_emax'};
	$d->{$module_name."limit"} = $in->{$input_name."limit"};
	}
return undef;
}

# feature_links(&domain)
# Returns an array of link objects for webmin modules for this feature
sub feature_links
{
local ($d) = @_;
return ( { 'mod' => $module_name,
	   'desc' => $text{'links_link'},
	   'page' => 'index.cgi?show='.$d->{'dom'},
	   'cat' => 'services',
	 } );
}

# feature_backup(&domain, file, &opts, &all-opts)
# Create a tar file of all list directories for this domain
sub feature_backup
{
local ($d, $file, $opts, $allopts) = @_;
local @lists = grep { $_->{'dom'} eq $d->{'dom'} } &list_lists();
&$virtual_server::first_print($text{'feat_backup'});

if (!@lists) {
	# No lists, so we can skip most of this
	open(EMPTY, ">$file");
	close(EMPTY);
	if ($opts->{'archive'} && -d $archives_dir) {
		open(EMPTY, ">".$file."_private");
		close(EMPTY);
		open(EMPTY, ">".$file."_public");
		close(EMPTY);
		}
	&$virtual_server::second_print($text{'feat_nolists'});
	return 1;
	}

# Tar up lists directories
local $tar = defined(&virtual_server::get_tar_command) ?
		&virtual_server::get_tar_command() : "tar";
local $out = &backquote_command("cd $lists_dir && $tar cf ".quotemeta($file)." ".join(" ", map { $_->{'list'} } @lists)." 2>&1");
if ($?) {
	&$virtual_server::second_print(&text('feat_failed', "<pre>$out</pre>"));
	return 0;
	}
else {
	# Create file of list names and descriptions
	local %dlists;
	foreach my $l (@lists) {
		$dlists{$l->{'list'}} = $l->{'desc'};
		}
	&write_file($file."_lists", \%dlists);
	&$virtual_server::second_print($virtual_server::text{'setup_done'});

	# Tar up archive directories, if selected
	if ($opts->{'archive'} && -d $archives_dir) {
		# Tar up private dir
		&$virtual_server::first_print($text{'feat_barchive'});
		local $anyfiles = 0;
		local @files = grep { -e "$archives_dir/private/$_" }
			map { $_->{'list'}, "$_->{'list'}.mbox" } @lists;
		if (@files) {
			local $out = &backquote_command(
				"cd $archives_dir/private && $tar cf ".
				quotemeta($file."_private")." ".
				join(" ", @files)." 2>&1");
			if ($?) {
				&$virtual_server::second_print(&text('feat_failed', "<pre>$out</pre>"));
				return 0;
				}
			$anyfiles += scalar(@files);
			}

		# Tar up public dir
		local @files = grep { -e "$archives_dir/public/$_" }
			map { $_->{'list'}, "$_->{'list'}.mbox" } @lists;
		if (@files) {
			local $out = &backquote_command(
				"cd $archives_dir/public && $tar cf ".
				quotemeta($file."_public")." ".
				join(" ", @files)." 2>&1");
			if ($?) {
				&$virtual_server::second_print(&text('feat_failed', "<pre>$out</pre>"));
				return 0;
				}
			$anyfiles += scalar(@files);
			}
		if ($anyfiles) {
			&$virtual_server::second_print(
				$virtual_server::text{'setup_done'});
			}
		else {
			&$virtual_server::second_print($text{'feat_noarchive'});
			}
		}

	return 1;
	}
}

# feature_restore(&domain, file, &opts, &all-opts)
# Restore the tar file of all list directories for this domain
sub feature_restore
{
local ($d, $file) = @_;
&$virtual_server::first_print($text{'feat_restore'});

# Delete existing lists
local @lists = grep { $_->{'dom'} eq $d->{'dom'} } &list_lists($d);
foreach my $l (@lists) {
	&delete_list($l->{'list'}, $l->{'dom'});
	}


# Delete old list archives, if they are in the backup
if (-r $file."_public") {
	foreach my $l (@lists) {
		&system_logged("rm -rf ".quotemeta("$archives_dir/public/$l"));
		&system_logged("rm -rf ".quotemeta("$archives_dir/public/$l.mbox"));
		}
	}
if (-r $file."_private") {
	foreach my $l (@lists) {
		&system_logged("rm -rf ".quotemeta("$archives_dir/private/$l"));
		&system_logged("rm -rf ".quotemeta("$archives_dir/private/$l.mbox"));
		}
	}

local @st = stat($file);
if (@st && $st[7] == 0) {
	# Source had no mailing lists .. so nothing to do
	&$virtual_server::second_print($text{'feat_nolists2'});
	return 1;
	}

# Extract lists tar file
local $tar = defined(&virtual_server::get_tar_command) ?
		&virtual_server::get_tar_command() : "tar";
local $out = &backquote_command("cd $lists_dir && $tar xf ".quotemeta($file)." 2>&1");
if ($?) {
	&$virtual_server::second_print(&text('feat_failed', "<pre>$out</pre>"));
	return 0;
	}
else {
	# Re-add domain and descriptions for lists
	local %dlists;
	&read_file($file."_lists", \%dlists);
	local %lists;
	&read_file($lists_file, \%lists);
	foreach my $l (keys %dlists) {
		$lists{$l} = $d->{'dom'}."\t".$dlists{$l};
		}
	&write_file($lists_file, \%lists);

	# Re-create aliases
	if ($config{'mode'} == 1) {
		&virtual_server::obtain_lock_mail($_[0]);
		local @virts = &virtual_server::list_virtusers();
		foreach my $l (keys %dlists) {
			local $a;
			foreach $a (@mailman_aliases) {
				local $virt = {
				  'from' => ($a eq "post" ? $l : "$l-$a").
					    "\@".$d->{'dom'},
				  'to' => [ "|$mailman_cmd $a $l" ]
				  };
				local ($c) = grep { $_->{'from'} eq
						    $virt->{'from'} } @virts;
				if ($c) {
					&virtual_server::delete_virtuser($c);
					}
				&virtual_server::create_virtuser($virt);
				}
			}
		&virtual_server::release_lock_mail($_[0]);
		}
	&$virtual_server::second_print($virtual_server::text{'setup_done'});

	# If the backup included archives, restore them too
	if (-r $file."_public" || -r $file."_private") {
		&$virtual_server::first_print($text{'feat_rarchive'});
		}
	if (-r $file."_public") {
		local $out = &backquote_command("cd $archives_dir/public && $tar xf ".quotemeta($file."_public")." 2>&1");
		if ($?) {
			&$virtual_server::second_print(&text('feat_failed', "<pre>$out</pre>"));
			return 0;
			}
		}
	if (-r $file."_private") {
		local $out = &backquote_command("cd $archives_dir/private && $tar xf ".quotemeta($file."_private")." 2>&1");
		if ($?) {
			&$virtual_server::second_print(&text('feat_failed', "<pre>$out</pre>"));
			return 0;
			}

		}
	if (-r $file."_public" || -r $file."_private") {
		&$virtual_server::second_print($virtual_server::text{'setup_done'});
		}

	return 1;
	}
}

# feature_backup_name()
# Returns a description for what is backed up for this feature
sub feature_backup_name
{
return $text{'feat_backupname'};
}

# feature_backup_opts(&opts)
# Returns HTML for selecting options for a backup of this feature
sub feature_backup_opts
{
local ($opts) = @_;
if (-d $archives_dir) {
	return "(".&ui_checkbox("virtualmin_mailman_archive", 1,
			    $text{'feat_archive'}, $opts->{'archive'}).")";
	}
else {
	return undef;
	}
}

# feature_backup_parse(&in)
# Return a hash reference of backup options, based on the given HTML inputs
sub feature_backup_parse
{
local ($in) = @_;
if (-d $archives_dir) {
	return { 'archive' => $in->{'virtualmin_mailman_archive'} };
	}
else {
	return { };
	}
}

# virtusers_ignore([&domain])
# Returns a list of virtuser addresses (like foo@bar.com) that are used by
# mailing lists.
sub virtusers_ignore
{
local ($d) = @_;
return ( ) if ($config{'mode'} == 0);
local @rv;
foreach my $l (&list_lists()) {
	if ($d && $l->{'dom'} eq $d->{'dom'} ||
	    !$d && $l->{'dom'}) {
		my $short_list = $l->{'list'};
		$short_list =~ s/_\Q$l->{'dom'}\E$//;
		push(@rv, $l->{'list'}."\@".$l->{'dom'});
		push(@rv, $short_list."\@".$l->{'dom'});
		foreach my $a (@mailman_aliases) {
			push(@rv, $l->{'list'}."-".$a."\@".$l->{'dom'});
			push(@rv, $short_list."-".$a."\@".$l->{'dom'});
			}
		}
	}
return @rv;
}

# template_input(&template)
# Returns HTML for editing per-template options for this plugin
sub template_input
{
local ($tmpl) = @_;
local $v = $tmpl->{$module_name."limit"};
$v = "none" if (!defined($v) && $tmpl->{'default'});
return &ui_table_row($text{'tmpl_limit'},
	&ui_radio($input_name."_mode",
		  $v eq "" ? 0 : $v eq "none" ? 1 : 2,
		  [ $tmpl->{'default'} ? ( ) : ( [ 0, $text{'default'} ] ),
		    [ 1, $text{'tmpl_unlimit'} ],
		    [ 2, $text{'tmpl_atmost'} ] ])."\n".
	&ui_textbox($input_name, $v eq "none" ? undef : $v, 10));
}

# template_parse(&template, &in)
# Updates the given template object by parsing the inputs generated by
# template_input. All template fields must start with the module name.
sub template_parse
{
local ($tmpl, $in) = @_;
if ($in->{$input_name.'_mode'} == 0) {
	$tmpl->{$module_name."limit"} = "";
	}
elsif ($in->{$input_name.'_mode'} == 1) {
	$tmpl->{$module_name."limit"} = "none";
	}
else {
	$in->{$input_name} =~ /^\d+$/ || &error($text{'tmpl_elimit'});
	$tmpl->{$module_name."limit"} = $in->{$input_name};
	}
}

# setup_mailman_web_redirects(&domain)
# Configure Apache to support mailman CGIs for this domain
sub setup_mailman_web_redirects
{
&$virtual_server::first_print($text{'setup_alias'});
&virtual_server::require_apache();
&virtual_server::obtain_lock_web($_[0]);
local $conf = &apache::get_config();
local @ports = ( $_[0]->{'web_port'},
		 $_[0]->{'ssl'} ? ( $_[0]->{'web_sslport'} ) : ( ) );
local $added;
foreach my $p (@ports) {
	local ($virt, $vconf) = &virtual_server::get_apache_virtual(
		$_[0]->{'dom'}, $p);
	next if (!$virt);

	# Add lists.$domain alias, if in special Postfix mode
	if ($config{'mode'} == 0) {
		local @sa = &apache::find_directive("ServerAlias",
						    $vconf);
		push(@sa, "lists.$_[0]->{'dom'}");
		&apache::save_directive("ServerAlias",
					\@sa, $vconf, $conf);
		}

	# Add wrapper redirects
	local @rm = &apache::find_directive("RedirectMatch", $vconf);
	local $webminurl = &get_mailman_webmin_url($_[0]);
	foreach my $p ("/cgi-bin/mailman", "/mailman") {
		local ($already) = grep { /^\Q$p\E\// } @rm;
		if (!$already) {
			push(@rm, "$p/([^/\\.]*)(.cgi)?(.*) ".
				  "$webminurl/$module_name/".
				  "unauthenticated/\$1.cgi\$3");
			}
		}
	&apache::save_directive("RedirectMatch", \@rm, $vconf, $conf);
	$added++;

	# Add alias from /pipermail to archives directory
	local @al = &apache::find_directive("Alias", $vconf);
	push(@al, "/pipermail $archives_dir/public");
	&apache::save_directive("Alias", \@al, $vconf, $conf);
	}
if ($added) {
	&flush_file_lines();
	&virtual_server::register_post_action(
	    defined(&main::restart_apache) ? \&main::restart_apache
				   : \&virtual_server::restart_apache);
	&$virtual_server::second_print(
		$virtual_server::text{'setup_done'});
	}
else {
	&$virtual_server::second_print(
		$virtual_server::text{'delete_noapache'});
	}
&virtual_server::release_lock_web($_[0]);

# Add the apache user to the mailman group, so that symlinks work
my $auser = &virtual_server::get_apache_user($_[0]);
my @st = stat("$archives_dir/public");
if ($auser && @st) {
	&virtual_server::obtain_lock_unix($_[0]);
	my ($group) = grep { $_->{'gid'} == $st[5] }
			   &virtual_server::list_all_groups();
	if ($group) {
		my @mems = split(/,/, $group->{'members'});
		if (&indexof($auser, @mems) < 0) {
			my $oldgroup = { %$group };
			$group->{'members'} = join(",", @mems, $auser);
			&foreign_call($group->{'module'},
				"set_group_envs", $group,
				'MODIFY_GROUP', $oldgroup);
			&foreign_call($group->{'module'},
				"making_changes");
			&foreign_call($group->{'module'},
				"modify_group", $oldgroup, $group);
			&foreign_call($group->{'module'},
				"made_changes");
			}
		}
	&virtual_server::release_lock_unix($_[0]);
	}
}

1;

