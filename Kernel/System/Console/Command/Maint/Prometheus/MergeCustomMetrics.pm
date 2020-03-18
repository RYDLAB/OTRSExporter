# --
# Copyright (C) 2001-2020 OTRS AG, https://otrs.com/
# --
# This software comes with ABSOLUTELY NO WARRANTY. For details, see
# the enclosed file COPYING for license information (GPL). If you
# did not receive this file, see https://www.gnu.org/licenses/gpl-3.0.txt.
# --

package Kernel::System::Console::Command::Maint::Prometheus::MergeCustomMetrics;

use strict;
use warnings;

use parent qw(Kernel::System::Console::BaseCommand);

our @ObjectDependencies = (
    'Kernel::System::Prometheus',
);

sub Configure {
    my ( $Self, %Param ) = @_;

    $Self->Description("Merge custom metrics to shared memory");

    return;
}

sub Run {
    my ( $Self, %Param ) = @_;

    $Self->Print("<yellow>Merging custom metric...</yellow>\n");

    $Kernel::OM->Get('Kernel::System::Prometheus')->MergeCustomMetrics();

    $Self->Print("<green>Done.</green>\n");
    return $Self->ExitCodeOk();
}

1;
