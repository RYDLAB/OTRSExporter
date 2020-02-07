# --
# Copyright (C) 2001-2020 OTRS AG, https://otrs.com/
# --
# This software comes with ABSOLUTELY NO WARRANTY. For details, see
# the enclosed file COPYING for license information (GPL). If you
# did not receive this file, see https://www.gnu.org/licenses/gpl-3.0.txt.
# --

package Kernel::System::Prometheus::ProcessInformer;

use strict;
use warnings;

use Kernel::System::ObjectManager;

our @ObjectDependencies = ();

# TODO: Add autodetection for system
sub new {
    my ( $Type, %Param ) = @_;

    my $Self = {};
    bless( $Self, $Type );

    return $Self;
}

sub GetDaemonProcessStats {
    undef;
}

sub GetServerProcessStats {
    undef;
}

1
