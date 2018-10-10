[% IF ( PAGE_NUMBERS ) %]<nav><ul class="pagination">
 [% IF hits_to_paginate < total %]<h6>[% hits_to_paginate %] of [% total %] results loaded, refine your search to view other records</h6>[% END %]
    [% IF ( previous_page_offset.defined ) %]
        <li><a href="/cgi-bin/koha/catalogue/search.pl?[% full_query |html %][% END %]">First</a></li>
        <!-- Row of numbers corresponding to search result pages -->
        <li><a href="/cgi-bin/koha/catalogue/search.pl?[% full_query | replace('offset=\d+&?', '') |html %]&amp;offset=[% previous_page_offset %][% END %]">&lt;&lt; Previous</a></li>
    [% END %]
    [% FOREACH PAGE_NUMBER IN PAGE_NUMBERS %]
        [% IF ( PAGE_NUMBER.highlight ) %]
            <li class="active"><span>[% PAGE_NUMBER.pg %]</span></li>
        [% ELSE %]
            <li><a href="/cgi-bin/koha/catalogue/search.pl?[% full_query |replace('offset=\d+&?', '') |html %]&amp;offset=[% PAGE_NUMBER.offset %][% END %]">[% PAGE_NUMBER.pg %]</a></li>
        [% END %]
    [% END %]
    [% IF ( next_page_offset ) %]
        <li><a href="/cgi-bin/koha/catalogue/search.pl?[% full_query |replace('offset=\d+&?', '') |html %]&amp;offset=[% next_page_offset %][% END %]">Next &gt;&gt;</a></li>
        <li><a href="/cgi-bin/koha/catalogue/search.pl?[% full_query |replace('offset=\d+&?', '') |html %]&amp;offset=[% last_page_offset %][% END %]">Last</a></li>
    [% END %]
</ul></nav>[% END %]
