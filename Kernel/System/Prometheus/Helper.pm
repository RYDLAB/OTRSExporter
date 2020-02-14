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

   $Self->{Host} = hostname;
   $Self->{Temp} = {};

   return $Self;
}

sub GetTempValue {
   my ( $Self, %Param ) = @_;

   return \$Self->{Temp}->{ $Param{ValueName} };
}

sub CreateTempValue {
   my ( $Self, %Param ) = @_;

   $Self->{Temp}->{ $Param{ValueName} } = $Param{Value};
}

sub GetHost {
   return shift->{Host};
}

sub StartCountdown {
   shift->{TimeStart} = [gettimeofday];
}

sub GetCountdown {
   my $Self = shift;

   if ($Self->{TimeStart}) {
       return tv_interval($Self->{TimeStart});
   }

   return 0;
}

1
