package Koha::Filter::MARC::AddISILToLink;

#
# This file is part of Koha.
#
# Koha is free software; you can redistribute it and/or modify it
# under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 3 of the License, or
# (at your option) any later version.
#
# Koha is distributed in the hope that it will be useful, but
# WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with Koha; if not, see <http://www.gnu.org/licenses>.

=head1 NAME

Koha::Filter::MARC::AddISILToLink - Adds organization's ISIL to the 773w field

=head1 SYNOPSIS


=head1 DESCRIPTION

Add ISIL to 773w field

=cut

use strict;
use warnings;
use Carp;

use base qw(Koha::RecordProcessor::Base);
our $NAME = 'AddISILToLink';

use Koha::Logger;
my $logger = Koha::Logger->get({category => __PACKAGE__});


=head2 filter

    my $newrecord = $filter->filter($record);
    my $newrecords = $filter->filter(\@records);

Embed see from headings into the specified record(s) and return the result.
In order to differentiate added headings from actual headings, a 'z' is
put in the first indicator.

=cut
sub filter {
    my $self = shift;
    my $record = shift;
    my $newrecord;

    return unless defined $record;

    if (ref $record eq 'ARRAY') {
        my @recarray;
        foreach my $thisrec (@$record) {
            push @recarray, _processrecord($thisrec);
        }
        $newrecord = \@recarray;
    } elsif (ref $record eq 'MARC::Record') {
        $newrecord = _processrecord($record);
    }

    return $newrecord;
}

sub _processrecord {
    my $record = shift;

    my $biblionumber = $record->subfield('999', 'c');

    foreach my $field ( $record->field('773') ) {
        my @subfields = $field->subfield( 'w' );

        next if !@subfields;

        if ($#subfields > 0) {
            $logger->error("ERROR: multiple subfields in biblionumber: $biblionumber\n") ;
            next;
        }

        if ($subfields[0] =~ /^\d+$/) {
            $field->update( 'w' => '(FI-J)' . $subfields[0] );
            $logger->info('New subfield for $biblionumber: (FI-J)' . $subfields[0] . "\n");
        } else {
            $logger->info("Skipped $biblionumber because subfield ". $subfields[0] . "\n");
        }
    }
    return $record;
}
