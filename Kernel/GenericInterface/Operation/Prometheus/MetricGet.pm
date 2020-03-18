# --
# Copyright (C) 2001-2020 OTRS AG, https://otrs.com/
# --
# This software comes with ABSOLUTELY NO WARRANTY. For details, see
# the enclosed file COPYING for license information (GPL). If you
# did not receive this file, see https://www.gnu.org/licenses/gpl-3.0.txt.
# --

package Kernel::GenericInterface::Operation::Prometheus::MetricGet;

use strict;
use warnings;

our $ObjectManagerDisabled = 1;

our @ObjectDependencies = (
    'Kernel::System::Prometheus',
);

sub new {
    my ( $Type, %Param ) = @_;

    my $Self = {};
    bless( $Self, $Type );

    return $Self;
}

sub Run {
    my ( $Self, %Param ) = @_;

    my $Data = { Text => $Kernel::OM->Get('Kernel::System::Prometheus')->Render() };

    return {
        Success => 1,
        Data    => $Data,
    };
}

1
