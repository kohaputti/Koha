$DBversion = 'XXX';  # will be replaced by the RM
if( CheckVersion( $DBversion ) ) {
    my ( $SCOvalue ) = $dbh->selectrow_array(q|
        SELECT value FROM systempreferences WHERE variable = 'AllowItemsOnHoldCheckoutSCO'
    |);

    if ( $SCOvalue ) {
        $dbh->do("UPDATE systempreferences SET value = 1 WHERE variable = 'AllowItemsOnHoldCheckout'");
    }

    $dbh->do("DELETE FROM systempreferences WHERE variable = 'AllowItemsOnHoldCheckoutSCO'");

    SetVersion( $DBversion );
    print "Upgrade to $DBversion done (Bug 21572 - Allow checkout an item with reserve that is not yet in waiting state)\n";
}
