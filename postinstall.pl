
do 'virtualmin-mailman-lib.pl';

sub module_install
{
&foreign_require("acl", "acl-lib.pl");
if (defined(&acl::setup_anonymous_access)) {
	# Use new function
	&acl::setup_anonymous_access("/$module_name/unauthenticated",
				     $module_name);
	}
else {
	# Make the unauthenticated sub-directory accessible anonymously
	local %miniserv;
	&get_miniserv_config(\%miniserv);
	local @anon = split(/\s+/, $miniserv{'anonymous'});
	local $found = 0;
	foreach my $a (@anon) {
		local ($path, $user) = split(/=/, $a);
		$found++ if ($path eq "/$module_name/unauthenticated");
		}
	if (!$found) {
		local %acl;
		&read_acl(undef, \%acl);
		local $defuser = $acl{'root'} ? 'root' :
				 $acl{'admin'} ? 'admin' :
				 (keys %acl)[0];
		push(@anon, "/$module_name/unauthenticated=$defuser");
		$miniserv{'anonymous'} = join(" ", @anon);
		&put_miniserv_config(\%miniserv);
		&reload_miniserv();
		}
	}
}

