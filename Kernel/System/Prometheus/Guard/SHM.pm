# --
# Copyright (C) 2001-2020 OTRS AG, https://otrs.com/
# --
# This software comes with ABSOLUTELY NO WARRANTY. For details, see
# the enclosed file COPYING for license information (GPL). If you
# did not receive this file, see https://www.gnu.org/licenses/gpl-3.0.txt.
# --

package Kernel::System::Prometheus::Guard::SHM;

use strict;
use warnings;

use parent 'Kernel::System::Prometheus::Guard';

use IPC::ShareLite qw(:lock);
use Sereal qw( get_sereal_decoder get_sereal_encoder );

use constant {
    DEFAULT_SHARED_MEMORY_KEY => 1999,
    DEFAULT_CREATE_FLAG       => 1,
    DEFAULT_DESTROY_FLAG      => 0,
    DEFAULT_ACCESS_MODE       => 0666,
    DEFAULT_SIZE              => 65536,
};

our @ObjectDependencies = (
    'Kernel::System::Log',
);

sub new {
    my ( $Type, %Param ) = @_;

    my $Self = {};
    bless( $Self, $Type );

    $Self->{DECODER} = get_sereal_decoder();
    $Self->{ENCODER} = get_sereal_encoder();

    $Self->{SharedMem} = IPC::ShareLite->new(
        -key     => $Param{SHAREDKEY}   // DEFAULT_SHARED_MEMORY_KEY,
        -create  => $Param{CreateFlag}  // DEFAULT_CREATE_FLAG,
        -destroy => $Param{DestroyFlag} // DEFAULT_DESTROY_FLAG,
        -mode    => $Param{Mode}        // DEFAULT_ACCESS_MODE,
        -size    => $Param{Size}        // DEFAULT_SIZE,
    );

    for my $Needed ( qw( DECODER ENCODER SharedMem ) ) {
        if (!$Self->{$Needed}) {
            $Kernel::OM->Get('Kernel::System::Log')->Log(
                PrometheusLog => 1,
                Priority => 'error',
                Message  => "Prometheus::Guard can not to create object $Needed",
            );

            return;
        }

    }

    return $Self;
}

sub Change {
    my ( $Self, %Param ) = @_;

    if (!$Param{Callback}) {
        $Kernel::OM->Get('Kernel::System::Log')->Log(
            PrometheusLog => 1,
            Priority => 'error',
            Message  => 'Callback is empty!',
        );

        return;
    }

    return if !$Self->_LockMemory( LockFlag => LOCK_EX|LOCK_NB );

    my $Data = $Self->Fetch();

    if (!$Data) {
        $Kernel::OM->Get('Kernel::System::Log')->Log(
            PrometheusLog => 1,
            Priority => 'error',
            Message  => 'Guard can not change empty data!',
        );

        $Self->_UnlockMemory;
        return;
    }

    $Param{Callback}->($Data);

    $Self->Store(Data => $Data);

    $Self->_UnlockMemory;

    return 1;
}

sub Store {
    my ( $Self, %Param ) = @_;

    if ( !$Param{Data} ) {
        $Kernel::OM->Get('Kernel::System::Log')->Log(
            PrometheusLog => 1,
            Priority => 'error',
            Message  => 'Data to store is empty! Please check param.',
        );

        return;
    }

    my $EncodedData = $Self->{ENCODER}->encode($Param{Data});
    $Self->{SharedMem}->store($EncodedData);

    return 1;
}

sub Fetch {
    my ( $Self, %Param ) = @_;

    my $EncodedData = $Self->{SharedMem}->fetch();
    return unless $EncodedData;

    my $Data = $Self->{DECODER}->decode($EncodedData);

    return $Data;
}

sub _LockMemory {
    my ( $Self, %Param ) = @_;

    $Self->{SharedMem}->lock( $Param{LockFlag} // LOCK_EX );
}

sub _UnlockMemory {
    $_[0]->{SharedMem}->unlock();
}

1
