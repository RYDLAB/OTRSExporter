# --
# Copyright (C) 2001-2020 OTRS AG, https://otrs.com/
# --
# This software comes with ABSOLUTELY NO WARRANTY. For details, see
# the enclosed file COPYING for license information (GPL). If you
# did not receive this file, see https://www.gnu.org/licenses/gpl-3.0.txt.
# --

package Kernel::System::Prometheus::Guard;

use strict;
use warnings;

our @ObjectDependencies = ();

sub new {
    my ( $Type, %Param ) = @_;

    my $Self = {};
    bless( $Self, $Type );

    return $Self;
}

sub Change {
    my ( $Self, %Param ) = @_;

    return 0;
}

sub Store {
    my ( $Self, %Param ) = @_;

    return 0;
}

sub Fetch {
    my ( $Self, %Param ) = @_;
    
    return 0;
}

1
