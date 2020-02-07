# --
# Copyright (C) 2001-2020 OTRS AG, https://otrs.com/
# --
# This software comes with ABSOLUTELY NO WARRANTY. For details, see
# the enclosed file COPYING for license information (GPL). If you
# did not receive this file, see https://www.gnu.org/licenses/gpl-3.0.txt.
# --

package Kernel::System::Prometheus;

use strict;
use warnings;

use Net::Prometheus;
use Time::HiRes qw( gettimeofday tv_interval );
use Kernel::System::VariableCheck qw( IsHashRefWithData );

our @ObjectDependencies = (
    'Kernel::System::Prometheus::ProcessInformer::Linux::Apache2',
    'Kernel::System::Prometheus::Guard',
    'Kernel::System::DB',
    'Kernel::Config',
);

sub new {
    my ( $Type, %Param ) = @_;

    my $Self = {};
    bless( $Self, $Type );
    
    $Self->{PrometheusObject} = Net::Prometheus->new( disable_process_collector => 1 );

    $Self->{Settings} = $Kernel::OM->Get('Kernel::Config')->Get('Prometheus::Settings');

    $Self->{Guard} = $Kernel::OM->Create(
        'Kernel::System::Prometheus::Guard',
        ObjectParams => {
            SHAREDKEY   => $Self->{Settings}{SharedMemoryKey},
        }
    );

    if (!$Self->{PrometheusObject}) {
        $Kernel::OM->Get('Kernel::System::Log')->Log(
            Priority => 'error',
            Message  => 'Can\'t create prometheus object!',
        )
    }

    if (!$Self->{Settings}) {
        $Kernel::OM->Get('Kernel::System::Log')->Log(
            Priority => 'error',
            Message  => 'Can\'t load prometheus settings! Did you create config file?',
        );
    }

    if ( !$Self->{Guard}->Fetch ) {

        $Kernel::OM->Get('Kernel::System::Log')->Log(
            Priority => 'info',
            Message  => 'Shared memory is clear. Creating new metrics...',
        );

        $Self->_RegisterDefaultMetrics;
        $Self->{Guard}->Store(Data => $Self->{Metrics});
    }

    return $Self;
}

=head2 Change

    Change prometheus data

=cut

sub Change {
    my ( $Self, %Param ) = @_;
    
    $Self->{Guard}->Change(Callback => $Param{Callback});
}


sub StartCountdown {
    shift->{_TimeStart} = [gettimeofday];
}

sub GetCountdown {
    my $Self = shift;

    if ($Self->{_TimeStart}) {
        return tv_interval($Self->{_TimeStart}); 
    }

    return 0;
}

sub Render {
    my $Self = shift;

    $Self->_LoadSharedMetrics || return 'empty result';

    $Self->{PrometheusObject}->render;
}

sub UpdateMetrics {
    my ( $Self, %Param ) = @_;

    my $DBObject = $Kernel::OM->Get('Kernel::System::DB');
    my $ProcessInformerObject = $Kernel::OM->Get('Kernel::System::Prometheus::ProcessInformer::Linux::Apache2');

    # Update article total metric
    return if !$DBObject->Prepare(
        SQL => 'SELECT queue.name, ticket_state.name, COUNT(*) FROM article
                JOIN ticket ON article.ticket_id = ticket.id
                JOIN queue ON ticket.queue_id = queue.id
                JOIN ticket_state ON ticket.ticket_state_id = ticket_state.id
                GROUP BY queue.name, ticket_state.name',
    );

    while ( my @Row = $DBObject->FetchrowArray ) {
        my ( $Queue, $Status, $Num ) = @Row;
        $Self->Change(
            Callback => sub {
                my $Metrics = shift;
                $Metrics->{OTRSArticleTotal}->set( $Queue, $Status, $Num );
            },
        );
    }

    # Update ticket total metric
    return if !$DBObject->Prepare(
        SQL => 'SELECT queue.name, ticket_state.name, count(*) FROM ticket
                JOIN queue ON queue.id = ticket.queue_id
                JOIN ticket_state ON ticket_state.id = ticket.ticket_state_id
                GROUP BY queue.name, ticket_state.name',
    );

    while ( my @Row = $DBObject->FetchrowArray ) {
        my ( $Queue, $Status, $Num ) = @Row;
        $Self->Change(
            Callback => sub {
                my $Metrics = shift;
                $Metrics->{OTRSTicketTotal}->set( $Queue, $Status, $Num );
            },
        );
    }
 
    # Update daemon process metrics
    my $DaemonProcessStats = $ProcessInformerObject->GetDaemonProcessStats; 

    if (IsHashRefWithData($DaemonProcessStats)) {
        for my $PID ( keys %{$DaemonProcessStats} ) {
            $Self->Change(
                Callback => sub {
                    my $Metrics = shift;
                    $Metrics->{DaemonProcessResidentMemoryBytes}->set(
                        $PID, $DaemonProcessStats->{$PID}{RSS},
                    );
                    $Metrics->{DaemonProcessCPUSecondsTotal}->set(
                        $PID, $DaemonProcessStats->{$PID}{TotalTime},
                    );
                    $Metrics->{DaemonProcessCPUUserSecondsTotal}->set(
                        $PID, $DaemonProcessStats->{$PID}{UTime},
                    );
                    $Metrics->{DaemonProcessCPUSystemSecondsTotal}->set(
                        $PID, $DaemonProcessStats->{$PID}{STime},
                    );
                },
            );
        }
    }

    # Update http-server process metrics
    my $HTTPProcessStats = $ProcessInformerObject->GetServerProcessStats;

    if (IsHashRefWithData($HTTPProcessStats)) {
        for my $PID ( keys %{$HTTPProcessStats} ) {
            $Self->Change(
                Callback => sub {
                    my $Metrics = shift;

                    $Metrics->{HTTPProcessResidentMemoryBytes}->set(
                        $PID, $HTTPProcessStats->{$PID}{RSS},
                    );
                    $Metrics->{HTTPProcessCPUSecondsTotal}->set(
                        $PID, $HTTPProcessStats->{$PID}{TotalTime},
                    );
                    $Metrics->{HTTPProcessCPUUserSecondsTotal}->set(
                        $PID, $HTTPProcessStats->{$PID}{UTime},
                    );
                    $Metrics->{HTTPProcessCPUSystemSecondsTotal}->set(
                        $PID, $HTTPProcessStats->{$PID}{STime},
                    );
                },
            );   
        }
    }

    return 1;
}

sub _LoadSharedMetrics {
    my $Self = shift;

    my $SharedMetrics = $Self->{Guard}->Fetch;

    if (!$SharedMetrics) {
        $Kernel::OM->Get('Kernel::System::Log')->Log(
            Priority => 'error',
            Message  => 'Prometheus can not load metrics from shared memory. It\'s empty!',
        );
        
        return;
    }

    for my $MetricName ( keys %{$SharedMetrics} ) {
        $Self->{PrometheusObject}->register($SharedMetrics->{$MetricName});
    }

    return 1;
}


sub _RegisterDefaultMetrics {
    my $Self = shift;

    my $HTTPMetricGroup   = $Self->{PrometheusObject}->new_metricgroup(namespace => 'http');
    my $OTRSMetricGroup   = $Self->{PrometheusObject}->new_metricgroup(namespace => 'otrs');
    my $SystemMetricGroup = $Self->{PrometheusObject}->new_metricgroup(namespace => 'sys');


    # Initialize HTTP metric group
    $Self->{Metrics}{HTTPRequestDurationSeconds} = $HTTPMetricGroup->new_histogram(
        name    => 'request_duration_seconds',
        help    => 'The duration of the request in seconds',
        labels  => [qw( worker method route )],
    );

    $Self->{Metrics}{HTTPResponseSizeBytes} = $HTTPMetricGroup->new_histogram(
        name    => 'response_size_bytes',
        help    => 'The size of the response in bytes',
        labels  => [qw(worker)],
        buckets => [ 50, 100, 500, 1000, 5000, 10000, 25000, 50000, 100000, 1000000 ],
    );

    $Self->{Metrics}{HTTPRequestsTotal} = $HTTPMetricGroup->new_counter(
        name   => 'requests_total',
        help   => 'The total number of the HTTP requests',
        labels => [qw(worker)],
    );


    # Initialize OTRS metric group
    $Self->{Metrics}{OTRSIncomeMailTotal} = $OTRSMetricGroup->new_counter(
        name   => 'income_mail_total',
        help   => 'The number of incoming mail',
    );

    $Self->{Metrics}{OTRSOutgoingMailTotal} = $OTRSMetricGroup->new_counter(
        name   => 'outgoing_mail_total',
        help   => 'The number of outgoing mail',
    );

    $Self->{Metrics}{OTRSTicketTotal} = $OTRSMetricGroup->new_gauge(
        name   => 'ticket_total',
        help   => 'The number of tickets',
        labels => [qw( queue status )],
    );

    $Self->{Metrics}{OTRSLogsTotal} = $OTRSMetricGroup->new_counter(
        name   => 'logs_total',
        help   => 'The number of the logs',
        labels => [qw(priority)],
    );

    $Self->{Metrics}{OTRSArticleTotal} = $OTRSMetricGroup->new_gauge(
        name   => 'article_total',
        help   => 'The number of the articles',
        labels => [qw( queue status )],
    );


    #Initialize system daemon metric group
    $Self->{Metrics}{DaemonProcessResidentMemoryBytes} = $SystemMetricGroup->new_gauge(
        name   => 'daemon_process_resident_memory_bytes',
        help   => 'Resident memory in bytes for daemon processes',
        labels => [qw(worker)],
    );

    $Self->{Metrics}{DaemonProcessCPUSecondsTotal} = $SystemMetricGroup->new_gauge(
        name   => 'daemon_process_cpu_seconds_total',
        help   => 'Total daemon user and system CPU time spent in seconds',
        labels => [qw(worker)],
    );

    $Self->{Metrics}{DaemonProcessCPUUserSecondsTotal} = $SystemMetricGroup->new_gauge(
        name   => 'daemon_process_cpu_user_seconds_total',
        help   => 'Total daemon user CPU time spent in seconds',
        labels => [qw(worker)],
    );

    $Self->{Metrics}{DaemonProcessCPUSystemSecondsTotal} = $SystemMetricGroup->new_gauge(
        name   => 'daemon_process_cpu_system_seconds_total',
        help   => 'Total daemon system CPU time spent in seconds',
        labels => [qw(worker)],
    );


    #Initialize system http metric group
    $Self->{Metrics}{HTTPProcessResidentMemoryBytes} = $SystemMetricGroup->new_gauge(
        name   => 'http_process_resident_memory_bytes',
        help   => 'Resident memory in bytes for http-server processes',
        labels => [qw(worker)]
    );
    $Self->{Metrics}{HTTPProcessCPUSecondsTotal} = $SystemMetricGroup->new_gauge(
        name   => 'http_process_cpu_seconds_total',
        help   => 'Total http-server user and system CPU time spent in seconds',
        labels => [qw(worker)],
    );
    $Self->{Metrics}{HTTPProcessCPUUserSecondsTotal} = $SystemMetricGroup->new_gauge(
        name   => 'http_process_cpu_user_seconds_total',
        help   => 'Total http-server user CPU time spent in seconds',
        labels => [qw(worker)],
    );
    $Self->{Metrics}{HTTPProcessCPUSystemSecondsTotal} = $SystemMetricGroup->new_gauge(
        name   => 'http_process_cpu_system_seconds_total',
        help   => 'Total http-server system CPU time spent in seconds',
        labels => [qw(worker)],
    );

    return 1;
}

1
