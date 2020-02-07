# --
# Copyright (C) 2001-2020 OTRS AG, https://otrs.com/
# --
# This software comes with ABSOLUTELY NO WARRANTY. For details, see
# the enclosed file COPYING for license information (GPL). If you
# did not receive this file, see https://www.gnu.org/licenses/gpl-3.0.txt.
# --

package Kernel::System::Prometheus::ProcessInformer::Linux;

use strict;
use warnings;

use parent qw(Kernel::System::Prometheus::ProcessInformer);

use Kernel::System::VariableCheck qw( IsArrayRefWithData IsHashRefWithData );
use Kernel::System::ObjectManager;
use Proc::Find qw( find_proc );
use Proc::Stat;

our @ObjectDependencies = (
    'Kernel::System::Log',
);

use constant {
    TICKS_PER_SEC => 100,
    BYTES_PER_PAGE => 4096,
};

sub GetDaemonProcessStats {
    my $Self = shift;

    return $Self->GetStatsForProcByCMND(
        cmndline => qr/.*otrs\.Daemon\.pl/,
    );
}

sub GetStatsForProcByCMND {
    my ( $Self, %Param ) = @_;

    my $PIDs = find_proc( cmndline => $Param{cmndline} );

    if (!IsArrayRefWithData($PIDs)) {
        $Kernel::OM->Get('Kernel::System::Log')->Log(
            Priority => 'error',
            Message  => "ProcessInformer can not locate processes for $Param{cmndline}",
        );
        return;
    }

    my $Stats = Proc::Stat->new->stat(@$PIDs)->{curstat};

    if (!IsHashRefWithData($Stats)) {
        $Kernel::OM->Get('Kernel::System::Log')->Log(
            Priority => 'error',
            Message  => "Proc::Stat can not get stats for processes $Param{cmndline}",
        );
    }

    my %ProcessStats;

    for my $PID ( keys %{$Stats} ) {
        my $UTime = $Stats->{$PID}[13] / TICKS_PER_SEC;
        my $STime = $Stats->{$PID}[14] / TICKS_PER_SEC;
        my $RSS   = $Stats->{$PID}[23] * BYTES_PER_PAGE;

        $ProcessStats{$PID} = {
            UTime     => $UTime,
            STime     => $STime,
            TotalTime => ( $UTime + $STime ),
            RSS       => $RSS,
        };
    }

    return \%ProcessStats;

}

1
