#!/usr/bin/perl
#script to set the password, and optionally a userid, for a borrower
#written 2/5/00
#by chris@katipo.co.nz
#converted to using templates 3/16/03 by mwhansen@hmc.edu

use strict;
use warnings;

use C4::Auth;
use Koha::AuthUtils;
use C4::Output;
use C4::Context;
use C4::Members;
use C4::Circulation;
use CGI qw ( -utf8 );
use C4::Members::Attributes qw(GetBorrowerAttributes);
use Koha::Patron::Images;
use Koha::Token;

use Koha::Patron::Categories;

my $input = new CGI;

my $theme = $input->param('theme') || "default";

# only used if allowthemeoverride is set

my ( $template, $loggedinuser, $cookie, $staffflags ) = get_template_and_user(
    {
        template_name   => "members/member-password.tt",
        query           => $input,
        type            => "intranet",
        authnotrequired => 0,
        flagsrequired   => { borrowers => 1 },
        debug           => 1,
    }
);

my $flagsrequired;
$flagsrequired->{borrowers} = 1;

my $member      = $input->param('member');
my $cardnumber  = $input->param('cardnumber');
my $destination = $input->param('destination');
my $newpassword  = $input->param('newpassword');
my $newpassword2 = $input->param('newpassword2');

my %errors;

my ($bor) = GetMember( 'borrowernumber' => $member );

if ( ( $member ne $loggedinuser ) && ( $bor->{'category_type'} eq 'S' ) ) {
    $errors{'NOPERMISSION'} = 1 unless($staffflags->{'superlibrarian'} || $staffflags->{'staffaccess'} );

    # need superlibrarian for koha-conf.xml fakeuser.
}
if ($newpassword) {
    my ($success, $errorcode, $errormessage) = ValidateMemberPassword($bor->{categorycode}, $newpassword, $newpassword2);
    if ($errorcode) {
        $errors{$errorcode} = $errormessage;
    }
}

if ( $newpassword  && !scalar(keys %errors) ) {

    die "Wrong CSRF token"
        unless Koha::Token->new->check_csrf({
            session_id => scalar $input->cookie('CGISESSID'),
            token  => scalar $input->param('csrf_token'),
        });

    my $digest = Koha::AuthUtils::hash_password( scalar $input->param('newpassword') );
    my $uid    = $input->param('newuserid') || $bor->{userid};
    my $dbh    = C4::Context->dbh;
    if ( Koha::Patrons->find( $member )->update_password($uid, $digest) ) {
        $template->param( newpassword => $newpassword );
        if ( $destination eq 'circ' ) {
            print $input->redirect("/cgi-bin/koha/circ/circulation.pl?borrowernumber=$cardnumber");
        }
        else {
            print $input->redirect("/cgi-bin/koha/members/moremember.pl?borrowernumber=$member");
        }
    }
    else {
        $errors{'BADUSERID'} = 1;
    }
}
else {
    my $userid = $bor->{'userid'};
    my $newuserid = $input->param('newuserid');
    if (defined $newuserid && $newuserid ne $userid) {
        my $patron = Koha::Patrons->find($member);
        $patron->set({ userid => $newuserid })->store;
        if ( $destination eq 'circ' ) {
            print $input->redirect("/cgi-bin/koha/circ/circulation.pl?borrowernumber=$cardnumber");
        }
        else {
            print $input->redirect("/cgi-bin/koha/members/moremember.pl?borrowernumber=$member");
        }

    } else {
        my $defaultnewpassword = GenMemberPasswordSuggestion($bor->{categorycode});
        $template->param( defaultnewpassword => $defaultnewpassword );
    }
}

if ( $bor->{'category_type'} eq 'C') {
    my $patron_categories = Koha::Patron::Categories->search_limited({ category_type => 'A' }, {order_by => ['categorycode']});
    $template->param( 'CATCODE_MULTI' => 1) if $patron_categories->count > 1;
    $template->param( 'catcode' => $patron_categories->next )  if $patron_categories->count == 1;
}

$template->param( adultborrower => 1 ) if ( $bor->{'category_type'} eq 'A' || $bor->{'category_type'} eq 'I' );

my $patron_image = Koha::Patron::Images->find($bor->{borrowernumber});
$template->param( picture => 1 ) if $patron_image;

if ( C4::Context->preference('ExtendedPatronAttributes') ) {
    my $attributes = GetBorrowerAttributes( $bor->{'borrowernumber'} );
    $template->param(
        ExtendedPatronAttributes => 1,
        extendedattributes       => $attributes
    );
}

$template->param(
    othernames                 => $bor->{'othernames'},
    surname                    => $bor->{'surname'},
    firstname                  => $bor->{'firstname'},
    borrowernumber             => $bor->{'borrowernumber'},
    cardnumber                 => $bor->{'cardnumber'},
    categorycode               => $bor->{'categorycode'},
    category_type              => $bor->{'category_type'},
    categoryname               => $bor->{'description'},
    address                    => $bor->{address},
    address2                   => $bor->{'address2'},
    streettype                 => $bor->{streettype},
    city                       => $bor->{'city'},
    state                      => $bor->{'state'},
    zipcode                    => $bor->{'zipcode'},
    country                    => $bor->{'country'},
    phone                      => $bor->{'phone'},
    phonepro                   => $bor->{'phonepro'},
    streetnumber               => $bor->{'streetnumber'},
    mobile                     => $bor->{'mobile'},
    email                      => $bor->{'email'},
    emailpro                   => $bor->{'emailpro'},
    branchcode                 => $bor->{'branchcode'},
    userid                     => $bor->{'userid'},
    destination                => $destination,
    is_child                   => ( $bor->{'category_type'} eq 'C' ),
    minPasswordLength          => C4::Members::minPasswordLength($bor->{categorycode}),
    RoutingSerials             => C4::Context->preference('RoutingSerials'),
    csrf_token                 => Koha::Token->new->generate_csrf({ session_id => scalar $input->cookie('CGISESSID'), }),
    errors                     => \%errors
);

if( scalar(keys %errors )){
    $template->param( errormsg => 1 );
}

output_html_with_http_headers $input, $cookie, $template->output;
