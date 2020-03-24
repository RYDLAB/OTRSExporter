#--
#Copyright (C) 2001-2020 OTRS AG, https://otrs.com/
#--
#This software comes with ABSOLUTELY NO WARRANTY. For details, see
#the enclosed file COPYING for license information (GPL). If you
#did not receive this file, see https://www.gnu.org/licenses/gpl-3.0.txt.
#--

package Kernel::System::Prometheus::Helper;

use strict;
use warnings;

use Time::HiRes qw( gettimeofday tv_interval );
use Sys::Hostname;

our @ObjectDependencies = ();

sub new {
   my ( $Type, %Param ) = @_;

   my $Self = {};
   bless( $Self, $Type );

   $Self->{Host} = hostname();
   $Self->{Temp} = {};

   return $Self;
}

sub GetHost {
   return $_[0]->{Host};
}

sub StartCountdown {
   $_[0]->{TimeStart} = [gettimeofday];
}

sub GetCountdown {
   if ($_[0]->{TimeStart}) {
       return tv_interval($_[0]->{TimeStart});
   }

   return;
}

sub GetDaemonTasksSummary {
    my $DaemonModuleConfig = $Kernel::OM->Get('Kernel::Config')->Get('DaemonModules') || {};

    my @DaemonSummary;

    for my $Module ( keys %{$DaemonModuleConfig} ) {

        # skip not well configured modules
        next if !$Module;
        next if !$DaemonModuleConfig->{$Module};
        next if ref $DaemonModuleConfig->{$Module} ne 'HASH';
        next if !$DaemonModuleConfig->{$Module}->{Module};

        my $DaemonObject;

        # create daemon object
        eval {
            $DaemonObject = $Kernel::OM->Get( $DaemonModuleConfig->{$Module}->{Module} );
        };

        # skip module if object could not be created or does not provide Summary()
        next if !$DaemonObject;
        next if !$DaemonObject->can('Summary');

        # execute Summary
        my @Summary;
        eval {
            @Summary = $DaemonObject->Summary();
        };

        # skip if the result is empty or in a wrong format;
        next if !@Summary;
        next if ref $Summary[0] ne 'HASH';

        for my $SummaryItem (@Summary) {
            push @DaemonSummary, $SummaryItem;
        }

    }

    return \@DaemonSummary;
}

1
