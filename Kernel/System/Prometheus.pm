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
use Net::Prometheus::ProcessCollector::linux;

use Kernel::System::VariableCheck qw( IsHashRefWithData );
use Proc::Find qw(find_proc);

our @ObjectDependencies = (
    'Kernel::System::Prometheus::Helper',
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
            DestroyFlag => 0,
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
            Message  => 'Shared memory is empty. Creating new metrics...',
        );

        $Self->_RegisterDefaultMetrics;
        $Self->{Guard}->Store( Data => $Self->{Metrics} );
    }

    return $Self;
}

sub Change {
    my ( $Self, %Param ) = @_;

    $Self->{Guard}->Change( Callback => $Param{Callback} );
}

sub Render {
    my $Self = shift;

    $Self->_LoadSharedMetrics || return 'empty result';

    $Self->{PrometheusObject}->render;
}

sub NewProcessCollector {
    my ( $Self, %Param ) = @_;

    if ( !$Param{PID} ) {
        $Kernel::OM->Get('Kernel::System::Log')->Log(
            Priority => 'error',
            Message  => 'Didn\'t get PID to collect',
        );
    }

    $Self->Change(
        Callback => sub {
            my $Metrics = shift;
            $Metrics->{"ProcCollector$Param{PID}"} = Net::Prometheus::ProcessCollector->new(
                pid    => $Param{PID},
                labels => $Param{Labels},
                prefix => $Param{Prefix},
            );
        }
    );

    return 1;
}

sub UpdateMetrics {
    my ( $Self, %Param ) = @_;

    my $DBObject = $Kernel::OM->Get('Kernel::System::DB');

    # Get article total info
    my @ArticleInfo;

    return if !$DBObject->Prepare(
        SQL => 'SELECT queue.name, ticket_state.name, COUNT(*) FROM article
                JOIN ticket ON article.ticket_id = ticket.id
                JOIN queue ON ticket.queue_id = queue.id
                JOIN ticket_state ON ticket.ticket_state_id = ticket_state.id
                GROUP BY queue.name, ticket_state.name',
    );

    while ( my @Row = $DBObject->FetchrowArray ) {
        my ( $Queue, $Status, $Num ) = @Row;
        push @ArticleInfo, [ $Queue, $Status, $Num ];
    }

    # Get ticket info
    my @TicketInfo;

    return if !$DBObject->Prepare(
        SQL => 'SELECT queue.name, ticket_state.name, count(*) FROM ticket
                JOIN queue ON queue.id = ticket.queue_id
                JOIN ticket_state ON ticket_state.id = ticket.ticket_state_id
                GROUP BY queue.name, ticket_state.name',
    );

    while ( my @Row = $DBObject->FetchrowArray ) {
        my ( $Queue, $Status, $Num ) = @Row;
        push @TicketInfo, [ $Queue, $Status, $Num ];
    }

    # Get http processes pids
    my $ServerCMND = $Self->{Settings}{ServerCMND};
    my $ServerPids = find_proc( cmndline => $ServerCMND );

    # Record info as metrics
    my $Host = $Kernel::OM->Get('Kernel::System::Prometheus::Helper')->GetHost;

    $Self->Change(
        Callback => sub {
            my $Metrics = shift;

            for my $PID (@$ServerPids) {
                $Metrics->{"ProcessCollector$PID"} = Net::Prometheus::ProcessCollector->new(
                    pid    => $PID,
                    labels => [ host => $Host, worker => $PID ],
                    prefix => 'http_process',
                );
            }

            for my $Row (@ArticleInfo) {
                my ( $Queue, $Status, $Num ) = @$Row;
                $Metrics->{OTRSArticleTotal}->set( $Host, $Queue, $Status, $Num );
            }

            for my $Row (@TicketInfo) {
                my ( $Queue, $Status, $Num ) = @$Row;
                $Metrics->{OTRSTicketTotal}->set( $Host, $Queue, $Status, $Num );
            }
        }
    );


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

    # Initialize HTTP metric group
    $Self->{Metrics}{HTTPRequestDurationSeconds} = $HTTPMetricGroup->new_histogram(
        name    => 'request_duration_seconds',
        help    => 'The duration of the request in seconds',
        labels  => [qw( host worker method route )],
    );

    $Self->{Metrics}{HTTPResponseSizeBytes} = $HTTPMetricGroup->new_histogram(
        name    => 'response_size_bytes',
        help    => 'The size of the response in bytes',
        labels  => [qw( host worker)],
        buckets => [ 50, 100, 500, 1000, 5000, 10000, 25000, 50000, 100000, 1000000 ],
    );

    $Self->{Metrics}{HTTPRequestsTotal} = $HTTPMetricGroup->new_counter(
        name   => 'requests_total',
        help   => 'The total number of the HTTP requests',
        labels => [qw( host worker)],
    );


    # Initialize OTRS metric group
    $Self->{Metrics}{OTRSIncomeMailTotal} = $OTRSMetricGroup->new_counter(
        name   => 'income_mail_total',
        help   => 'The number of incoming mail',
        labels => [qw(host)],
    );

    $Self->{Metrics}{OTRSOutgoingMailTotal} = $OTRSMetricGroup->new_counter(
        name   => 'outgoing_mail_total',
        help   => 'The number of outgoing mail',
        labels => [qw(host)],
    );

    $Self->{Metrics}{OTRSTicketTotal} = $OTRSMetricGroup->new_gauge(
        name   => 'ticket_total',
        help   => 'The number of tickets',
        labels => [qw( host queue status )],
    );

    $Self->{Metrics}{OTRSLogsTotal} = $OTRSMetricGroup->new_counter(
        name   => 'logs_total',
        help   => 'The number of the logs',
        labels => [qw( host priority )],
    );

    $Self->{Metrics}{OTRSArticleTotal} = $OTRSMetricGroup->new_gauge(
        name   => 'article_total',
        help   => 'The number of the articles',
        labels => [qw( host queue status )],
    );

    return 1;
}

1
