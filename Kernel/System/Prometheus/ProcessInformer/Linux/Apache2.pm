# --
# Copyright (C) 2001-2020 OTRS AG, https://otrs.com/
# --
# This software comes with ABSOLUTELY NO WARRANTY. For details, see
# the enclosed file COPYING for license information (GPL). If you
# did not receive this file, see https://www.gnu.org/licenses/gpl-3.0.txt.
# --

package Kernel::System::Prometheus::ProcessInformer::Linux::Apache2;

use strict;
use warnings;

use parent qw(Kernel::System::Prometheus::ProcessInformer::Linux);

use Kernel::System::ObjectManager;

our @ObjectDependencies = ();

sub GetServerProcessStats {
    my $Self = shift;

    return $Self->GetStatsForProcByCMND(
        cmndline => qr/.*apache2.*|.*httpd.*/, 
    );
}

1
