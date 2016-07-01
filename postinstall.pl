use strict;
use warnings;
our $module_name;

do 'virtualmin-mailman-lib.pl';

sub module_install
{
# Make the unauthenticated sub-directory accessible anonymously
&foreign_require("acl", "acl-lib.pl");
&acl::setup_anonymous_access("/$module_name/unauthenticated",
			     $module_name);
}
