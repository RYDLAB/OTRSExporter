# --
# Copyright (C) 2001-2020 OTRS AG, https://otrs.com/
# --
# This software comes with ABSOLUTELY NO WARRANTY. For details, see
# the enclosed file COPYING for license information (GPL). If you
# did not receive this file, see https://www.gnu.org/licenses/gpl-3.0.txt.
# --

package Kernel::System::Prometheus::Guard::Cache;

use strict;
use warnings;

use parent 'Kernel::System::Prometheus::Guard';

our @ObjectDependencies = (
    'Kernel::System::Log',
    'Kernel::System::Cache',
);

sub new {
    my ( $Type, %Param ) = @_;

    my $Self = {};
    bless( $Self, $Type );

    return $Self;
}

sub Change {
    my ( $Self, %Param ) = @_;

    if ( !$Param{Callback} ) {
        $Kernel::OM->Get('Kernel::System::Log')->Log(
            Priority      => 'error',
            Message       => 'Callback is empty!',
        );

        return;
    }

    my $DataToChange = $Self->Fetch() // {};

    if (!$DataToChange) {
        $Kernel::OM->Get('Kernel::System::Log')->Log(
            Priority => 'error',
            Message  => 'Data to change is empty',
        );

        return;
    }

    $Param{Callback}->($DataToChange);

    $Self->Store( Data => $DataToChange );

    return 1;
}

sub Store {
    my ( $Self, %Param ) = @_;

    if ( !$Param{Data} ) {
        $Kernel::OM->Get('Kernel::System::Log')->Log(
            Priority => 'Error',
            Message  => 'Data to store is empty! Check params!'
        );

        return;
    }

    $Kernel::OM->Get('Kernel::System::Cache')->Set(
        Type           => 'PrometheusCache',
        Key            => 'StoredData',
        Value          => $Param{Data},
        CacheInMemory  => 0,
    );

    return 1;
}

sub Fetch {
    my ( $Self, %Param ) = @_;

    return $Kernel::OM->Get('Kernel::System::Cache')->Get(
        Type           => 'PrometheusCache',
        Key            => 'StoredData',
        CacheInMemory  => 0,
    );
}



1
