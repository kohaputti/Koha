package Koha::REST::V1::Checkout;

# This file is part of Koha.
#
# Koha is free software; you can redistribute it and/or modify it under the
# terms of the GNU General Public License as published by the Free Software
# Foundation; either version 3 of the License, or (at your option) any later
# version.
#
# Koha is distributed in the hope that it will be useful, but WITHOUT ANY
# WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR
# A PARTICULAR PURPOSE.  See the GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License along
# with Koha; if not, write to the Free Software Foundation, Inc.,
# 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA.

use Modern::Perl;

use Mojo::Base 'Mojolicious::Controller';
use Mojo::JSON;
use C4::Auth qw( haspermission );
use C4::Context;
use C4::Circulation;
use Koha::Availability::Checks::Patron;
use Koha::Checkouts;
use Koha::Old::Checkouts;

use Try::Tiny;

sub list {
    my $c = shift->openapi->valid_input or return;

    my $borrowernumber = $c->validation->param('borrowernumber');
    my $checkouts = Koha::Checkouts->search({
        borrowernumber => $borrowernumber
    });

    $c->render( status => 200, openapi => $checkouts );
}

sub get {
    my $c = shift->openapi->valid_input or return;

    my $checkout_id = $c->validation->param('checkout_id');
    my $checkout = Koha::Checkouts->find($checkout_id);

    if (!$checkout) {
        return $c->render( status => 404, openapi => {
            error => "Checkout doesn't exist"
        } );
    }

    return $c->render( status => 200, openapi => $checkout );
}

sub renew {
    my $c = shift->openapi->valid_input or return;

    my $checkout_id = $c->validation->param('checkout_id');
    my $checkout = Koha::Checkouts->find($checkout_id);

    try {
        my $borrowernumber = $checkout->borrowernumber;
        my $itemnumber = $checkout->itemnumber;

        # Disallow renewal if OpacRenewalAllowed is off and user has insufficient rights
        unless (C4::Context->preference('OpacRenewalAllowed')) {
            my $user = $c->stash('koha.user');
            unless ($user && haspermission($user->userid, {
                circulate => "circulate_remaining_permissions" })) {
                return $c->render(status => 403, openapi => {
                    error => "Opac Renewal not allowed"});
            }
        }

        my ($can_renew, $error) = C4::Circulation::CanBookBeRenewed(
            $borrowernumber, $itemnumber);

        # TODO: Create Koha::Availability::Renew for checking renewability
        #       via Koha::Availability
        my $patron_checks = Koha::Availability::Checks::Patron->new(
            scalar Koha::Patrons->find($borrowernumber)
        );
        if (!$error && (my $err = $patron_checks->debt_renew_opac ||
            $patron_checks->debarred || $patron_checks->gonenoaddress ||
            $patron_checks->lost || $patron_checks->expired)) {
            $err = ref($err);
            $can_renew = 0;
            $err =~ s/Koha::Exceptions::Patron:://;
            $error = lc($err);
        }
        # END TODO

        if (!$can_renew) {
            return $c->render(status => 403, openapi => {
                error => "Renewal not authorized ($error)"});
        }

        AddRenewal($borrowernumber, $itemnumber, $checkout->branchcode);
        $checkout = Koha::Checkouts->find($checkout_id);

        return $c->render( status => 200, openapi => $checkout );
    }
    catch {
        unless ($checkout) {
            return $c->render( status => 404, openapi => {
                error => "Checkout doesn't exist"
            } );
        }
        Koha::Exceptions::rethrow_exception($_);
    };
}

sub renewability {
    my $c = shift->openapi->valid_input or return;

    my $user = $c->stash('koha.user');

    my $checkout_id = $c->validation->param('checkout_id');
    my $checkout = Koha::Checkouts->find($checkout_id);

    try {
        my $borrowernumber = $checkout->borrowernumber;
        my $itemnumber = $checkout->itemnumber;

        unless (_opac_renewal_allowed($user, $borrowernumber))  {
            return $c->render(status => 403, openapi => {
                error => "You don't have the required permission"});
        }

        my ($can_renew, $error) = C4::Circulation::CanBookBeRenewed(
            $borrowernumber, $itemnumber);

        # TODO: Create Koha::Availability::Renew for checking renewability
        #       via Koha::Availability
        my $patron_checks = Koha::Availability::Checks::Patron->new(
            scalar Koha::Patrons->find($borrowernumber)
        );
        if (!$error && (my $err = $patron_checks->debt_renew_opac ||
            $patron_checks->debarred || $patron_checks->gonenoaddress ||
            $patron_checks->lost || $patron_checks->expired)) {
            $err = ref($err);
            $can_renew = 0;
            $err =~ s/Koha::Exceptions::Patron:://;
            $error = lc($err);
        }
        # END TODO

        return $c->render(status => 200, openapi => {
            renewable => Mojo::JSON->true, error => undef }) if $can_renew;
        return $c->render(status => 200, openapi => {
            renewable => Mojo::JSON->false, error => $error });
    }
    catch {
        unless ($checkout) {
            return $c->render( status => 404, openapi => {
                error => "Checkout doesn't exist"
            } );
        }
        Koha::Exceptions::rethrow_exception($_);
    };
}

sub listhistory {
    my $c = shift->openapi->valid_input or return;

    my $borrowernumber = $c->validation->param('borrowernumber');
    my $offset         = $c->validation->param('offset');
    my $limit          = $c->validation->param('limit');
    my $sort           = $c->validation->param('sort');
    my $order          = $c->validation->param('order');

    return try {
        my %attributes = ( itemnumber => { "!=", undef } );
        my $other_params = {};
        if ($borrowernumber) {
        return $c->render( status => 404, openapi => {
            error => "Patron doesn't exist"
        }) unless Koha::Patrons->find($borrowernumber);
            $attributes{borrowernumber} = $borrowernumber;
        }
        if (defined $offset) {
            $other_params->{offset} = $offset;
        }
        if (defined $limit) {
            $other_params->{rows} = $limit;
        }
        if (defined $order) {
            if ($order =~ /^desc/i) {
                $other_params->{order_by} = { '-desc' => 'issue_id' };
            }
            else {
                $other_params->{order_by} = { '-asc' => 'issue_id' };
            }
        }
        if (defined $sort) {
            my @columns = Koha::Old::Checkouts->columns;
            if (grep(/^$sort$/, @columns)) {
                if (keys %{$other_params->{'order_by'}}) {
                    foreach my $param (keys %{$other_params->{'order_by'}}) {
                        $other_params->{order_by}->{$param} = $sort;
                    }
                } else {
                    $other_params->{order_by}->{'-asc'} = $sort;
                }
            }
        }

        my $checkouts_count = Koha::Old::Checkouts->search(
          \%attributes,
        )->count;
        my $checkouts = Koha::Old::Checkouts->search(
          \%attributes,
          $other_params
        );

        return $c->render( status => 200, openapi => {
            total => $checkouts_count,
            records => $checkouts
        });
    }
    catch {
        Koha::Exceptions::rethrow_exception($_);
    };
}

sub gethistory {
    my $c = shift->openapi->valid_input or return;

    my $checkout_id = $c->validation->param('checkout_id');
    my $checkout = Koha::Old::Checkouts->find($checkout_id);

    if (!$checkout) {
        return $c->render( status => 404, openapi => {
            error => "Checkout doesn't exist"
        } );
    }

    return $c->render( status => 200, openapi => $checkout );
}

sub expanded {
    my $c = shift->openapi->valid_input or return;

    my $borrowernumber = $c->validation->param('borrowernumber');
    my $borrower = C4::Members::GetMember( borrowernumber => $borrowernumber )
      or return;
    my $user = $c->stash('koha.user');
    my $opac_renewability = _opac_renewal_allowed($user, $borrowernumber);
    my $checkouts = Koha::Checkouts->search({
        borrowernumber => $borrowernumber
    });
    my $checkouts_json = $checkouts->TO_JSON;

    foreach my $checkout (@{$checkouts_json}) {
        my $item         = Koha::Items->find($checkout->{itemnumber});
        my $branchcode   = C4::Circulation::_GetCircControlBranch( $item->unblessed,
                                                                   $borrower);
        my $issuing_rule = Koha::IssuingRules->get_effective_issuing_rule(
            {   categorycode => $borrower->{categorycode},
                itemtype     => $item->effective_itemtype,
                branchcode   => $branchcode,
                ccode        => $item->ccode,
                permanent_location => $item->permanent_location,
                sub_location => $item->sub_location,
                genre        => $item->genre,
                circulation_level => $item->circulation_level,
                reserve_level => $item->reserve_level,
            }
        );
        $checkout->{'max_renewals'} = $issuing_rule
                        ? 0+$issuing_rule->renewalsallowed : 0;
        my ($can_renew, $error);
        if ($opac_renewability) {
            ($can_renew, $error) = C4::Circulation::CanBookBeRenewed(
            $borrowernumber, $checkout->{'itemnumber'});
        }

        # TODO: Create Koha::Availability::Renew for checking renewability
        #       via Koha::Availability
        my $patron_checks = Koha::Availability::Checks::Patron->new(
            scalar Koha::Patrons->find($borrowernumber)
        );
        if (!$error && (my $err = $patron_checks->debt_renew_opac ||
            $patron_checks->debarred || $patron_checks->gonenoaddress ||
            $patron_checks->lost || $patron_checks->expired)) {
            $err = ref($err);
            $can_renew = 0;
            $err =~ s/Koha::Exceptions::Patron:://;
            $error = lc($err);
        }
        # END TODO

        $checkout->{'renewable'} = $can_renew
        ? Mojo::JSON->true : Mojo::JSON->false;
        $checkout->{'renewability_error'} = $error;
    }

    return $c->render( status => 200, openapi => $checkouts_json );
}

sub deletehistory {
    my $c = shift->openapi->valid_input or return;

    my $borrowernumber = $c->validation->param('borrowernumber');
    my $patron;
    return try {
        my $patrons = Koha::Patrons->search({
            'me.borrowernumber' => $borrowernumber
        });
        $patrons->anonymise_issue_history;
        $patron = $patrons->next;

        return $c->render( status => 200, openapi => {} );
    }
    catch {
        unless ($patron) {
            return $c->render( status => 404, openapi => {
                error => "Patron doesn't exist"
            });
        }
        Koha::Exceptions::rethrow_exception($_);
    };
}

sub _opac_renewal_allowed {
    my ($user, $borrowernumber) = @_;

    my $OpacRenewalAllowed;
    if ($user->borrowernumber == $borrowernumber) {
        $OpacRenewalAllowed = C4::Context->preference('OpacRenewalAllowed');
    }

    unless ($user && ($OpacRenewalAllowed || haspermission($user->userid,
                           { circulate => "circulate_remaining_permissions" }))) {
        return 0;
    }
    return 1;
}

1;
