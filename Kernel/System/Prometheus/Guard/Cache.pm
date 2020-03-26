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

sub Change {
    my ( $Self, %Param ) = @_;

    if ( !$Param{Callback} ) {
        $Kernel::OM->Get('Kernel::System::Log')->Log(
            Priority      => 'error',
            Message       => 'Callback is empty!',
        );

        return;
    }

    my $DataToChange = $Self->Fetch();

    if (!$DataToChange) {
        $Kernel::OM->Get('Kernel::System::Log')->Log(
            Priority      => 'error',
            Message       => 'Guard can not change empty data',
        );

        return;
    }

    $Param{Callback}->($DataToChange);

    $Self->Store( Data => $DataToChange );

    return 0;
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
        Key            => 'Metrics',
        Value          => $Param{Data},
        CacheInMemory  => 0,
    );

    return 1;
}

sub Fetch {
    my ( $Self, %Param ) = @_;

    return $Kernel::OM->Get('Kernel::System::Cache')->Get(
        Type           => 'PrometheusCache',
        Key            => 'Metrics',
        CacheInMemory  => 0,
    );
}

1
