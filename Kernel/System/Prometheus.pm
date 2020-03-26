# --
# Copyright (C) 2001-2020 OTRS AG, https://otrs.com/ # --
# This software comes with ABSOLUTELY NO WARRANTY. For details, see
# the enclosed file COPYING for license information (GPL). If you
# did not receive this file, see https://www.gnu.org/licenses/gpl-3.0.txt.
# --

package Kernel::System::Prometheus;

use strict;
use warnings;

use Net::Prometheus;
use Net::Prometheus::ProcessCollector::linux;

use Kernel::System::VariableCheck qw( IsArrayRefWithData IsHashRefWithData );
use Proc::ProcessTable;
use Proc::Exists 'pexists';
use List::Util   'any';

our @ObjectDependencies = (
    'Kernel::System::Prometheus::MetricManager',
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

    if (!$Self->{Settings}) {
        $Kernel::OM->Get('Kernel::System::Log')->Log(
            Priority => 'error',
            Message  => 'Can\'t load prometheus settings! Did you create config file?',
        );

        return;
    }

    # Get guard type
    if ($Self->{Settings}{Guard}) {
        my $GenericModule = 'Kernel::System::Prometheus::Guard::' . ( $Self->{Settings}{Guard} // 'Cache' );
        return if !$Kernel::OM->Get('Kernel::System::Main')->Require($GenericModule);

        if ( $Self->{Settings}{Guard} eq 'SHM' ) {
            $Self->{Guard} = $Kernel::OM->Create(
                $GenericModule,
                ObjectParams => {
                    SharedMemoryKey => $Self->{Settings}{SharedMemoryKey},
                    DestroyFlag     => 0,
                },
            );
        }

        else {
            $Self->{Guard} = $Kernel::OM->Get($GenericModule);
        }
    }

    else {
        $Kernel::OM->Get('Kernel::System::Log')->Log(
            Priority => 'error',
            Message  => 'Can\'t load prometheus guard setting!',
        );

        return;
    }


    if (!$Self->{PrometheusObject}) {
        $Kernel::OM->Get('Kernel::System::Log')->Log(
            Priority => 'error',
            Message  => 'Can\'t create prometheus object!',
        );

        return;
    }

    if (!IsHashRefWithData( $Self->{Guard}->Fetch() )) {
        $Self->_CreateMetrics();
    }

    return $Self;
}

sub Change {
    my ( $Self, %Param ) = @_;

    $Self->{Guard}->Change( Callback => $Param{Callback} );
}

sub Render {
    my $Self = shift;

    $Self->RefreshMetrics();

    $Self->_LoadSharedMetrics() || return 'empty result';

    # Get http processes info
    my $MainProcPID = 0;
    my @ChildPIDs;

    if ( $Kernel::OM->Get('Kernel::System::Prometheus::MetricManager')->IsMetricEnabled('HTTPProcessCollector') ) {
        my $ServerCMND = $Self->{Settings}{ServerCMND};

        my $ProcessTable = Proc::ProcessTable->new();

        # get main proc
        for my $ProcessObject ( @{ $ProcessTable->table } ) {
            next if $ProcessObject->{cmndline} ne $ServerCMND;
            next if $ProcessObject->{pgrp} != $ProcessObject->{pid};

            $MainProcPID = $ProcessObject->{pid};
        }

        # get child pids
        if ($MainProcPID) {
            for my $ProcessObject ( @{ $ProcessTable->table } ) {
                next if $ProcessObject->{pgrp} != $MainProcPID;
                next if $ProcessObject->{pid} == $MainProcPID;

                push @ChildPIDs, $ProcessObject->{pid};
            }
        }
    }

    if ($MainProcPID) {
        my @ProcessCollectors;
        my $Host = $Kernel::OM->Get('Kernel::System::Prometheus::Helper')->GetHost();

        push @ProcessCollectors, Net::Prometheus::ProcessCollector->new(
            pid    => $MainProcPID,
            labels => [ host => $Host, level => 'parent', worker => $MainProcPID ],
            prefix => 'http_process',
        );

        for my $PID (@ChildPIDs) {
            push @ProcessCollectors, Net::Prometheus::ProcessCollector->new(
                pid    => $PID,
                labels => [ host => $Host, level => 'child', worker => $PID ],
                prefix => 'http_process',
            );
        }

        for my $ProcessCollector (@ProcessCollectors) {
            $Self->{PrometheusObject}->register( $ProcessCollector );
        }
    }

    # Init process-collector variables to avoid warnings about unitialized variables (e.g. $BOOTTIME)
    # Especially for daemon processes
    else {
        Net::Prometheus::ProcessCollector->new( pid => 1 );
    }

    $Self->{PrometheusObject}->render();
}

sub RefreshMetrics {
    my $Self = shift;

    # get running daemon cache
    my $NodeID = $Kernel::OM->Get('Kernel::Config')->Get('NodeID') || 1;
    return if !$Kernel::OM->Get('Kernel::System::Cache')->Get(
        Type => 'DaemonRunning',
        Key  => $NodeID,
    );

    my $MetricManager = $Kernel::OM->Get('Kernel::System::Prometheus::MetricManager');

    return if !$MetricManager->IsMetricEnabled('RecurrentTasksMetrics');

    # Refresh daemon recurrent tasks metrics
    my $RecurrentTasks = [];
    my $DaemonSummary  = $Kernel::OM->Get('Kernel::System::Prometheus::Helper')->GetDaemonTasksSummary();
    my $Host           = $Kernel::OM->Get('Kernel::System::Prometheus::Helper')->GetHost();

    for my $Summary (@$DaemonSummary) {
        next if $Summary->{Header} ne 'Recurrent cron tasks:';
        $RecurrentTasks = $Summary->{Data};
        last;
    }

    if (!IsArrayRefWithData($RecurrentTasks)) {
        $Kernel::OM->Get('Kernel::System::Log')->Log(
            Priority => 'error',
            Message  => 'Didn\'t get any data about recurrent tasks',
        );

        return;
    }

    $Self->Change(
        Callback => sub {
            my $Metrics = shift;

            for my $Task (@$RecurrentTasks) {
                my $WorkerRunningTime = ${^MATCH} if $Task->{LastWorkerRunningTime} =~ /\d+/p;

                $Metrics->{RecurrentTaskDuration}->set(
                    $Host, $Task->{Name}, $WorkerRunningTime // -1,
                );

                my $SuccessResult = -1;

                if ( $Task->{LastWorkerStatus} eq 'Success' ) {
                    $SuccessResult = 1;
                }
                elsif ( $Task->{LastWorkerStatus} eq 'Fail' ) {
                    $SuccessResult = 0;
                }

                $Metrics->{RecurrentTaskSuccess}->set(
                    $Host, $Task->{Name}, $SuccessResult,
                );
            }

            return 1;
        }
    );

    return 1;
}

sub NewProcessCollector {
    my ( $Self, %Param ) = @_;

    if ( !$Param{PID} ) {
        $Kernel::OM->Get('Kernel::System::Log')->Log(
            Priority => 'error',
            Message  => 'Didn\'t get PID to collect',
        );

        return 0;
    }

    $Self->Change(
        Callback => sub {
            my $Metrics = shift;
            $Metrics->{"ProcessCollector$Param{PID}"} = Net::Prometheus::ProcessCollector->new(
                pid    => $Param{PID},
                labels => $Param{Labels},
                prefix => $Param{Prefix},
            );
        }
    );

    return 1;
}

sub ClearValuesWithDiedPids {
    my ( $Self, %Param ) = @_;

    my $MetricManager = $Kernel::OM->Get('Kernel::System::Prometheus::MetricManager');

    my %ToDeleteKeys;
    my $MetricsCopy = $Self->{Guard}->Fetch();

    my $GetWorkerIndex = sub {
        my $MetricName = shift || return;
        for my $Index ( 0 .. scalar @{ $MetricsCopy->{$MetricName}{labels} } ) {
            if ($MetricsCopy->{$MetricName}{labels}[$Index] eq 'worker') {
                return $Index;
            }
        }

        return;
    };

    my $HaveToDelete;

    for my $MetricName (qw/ HTTPRequestsTotal HTTPResponseSizeBytes HTTPRequestDurationSeconds /) {
        next if !$MetricManager->IsMetricEnabled($MetricName);

        $ToDeleteKeys{$MetricName} = [];
        my $WorkerIndex = $GetWorkerIndex->($MetricName);

        for my $LabelValueKey (keys %{ $MetricsCopy->{$MetricName}{labelvalues} }) {
            my $PID = $MetricsCopy->{$MetricName}{labelvalues}{$LabelValueKey}[$WorkerIndex];
            next if pexists($PID);

            push @{ $ToDeleteKeys{$MetricName} }, $LabelValueKey;
            $HaveToDelete = 1;
        }
    }

    return if !%ToDeleteKeys;
    return if !$HaveToDelete;

    $Self->Change(
        Callback => sub {
            my $Metrics = shift;

            if ( IsArrayRefWithData($ToDeleteKeys{HTTPRequestsTotal}) ) {
                for my $ToDeleteKey (@{ $ToDeleteKeys{HTTPRequestsTotal} }) {
                    delete $Metrics->{HTTPRequestsTotal}{labelvalues}{$ToDeleteKey};
                    delete $Metrics->{HTTPRequestsTotal}{values}{$ToDeleteKey};
                }
            }

            for my $HistogramMetric (qw/ HTTPResponseSizeBytes HTTPRequestDurationSeconds /) {
                next if !IsArrayRefWithData($ToDeleteKeys{$HistogramMetric});
                for my $ToDeleteKey (@{ $ToDeleteKeys{$HistogramMetric} }) {
                    delete $Metrics->{$HistogramMetric}{bucketcounts}{$ToDeleteKey};
                    delete $Metrics->{$HistogramMetric}{labelvalues}{$ToDeleteKey};
                    delete $Metrics->{$HistogramMetric}{sums}{$ToDeleteKey};
                }
            }

            return 1;
        }
    );

    return 1;
}

sub ClearDiedProcessCollectors {
    my ( $Self, %Param ) = @_;

    my $Metrics = $Self->{Guard}->Fetch();

    my @DiedCollectors;
    for my $MetricName( keys %{ $Metrics } ) {
        next if $MetricName !~ /ProcessCollector\K\d+/p;
        my $PID = ${^MATCH};
        next if pexists($PID);
        push @DiedCollectors, "ProcessCollector$PID";
    }

    return 1 if !@DiedCollectors;

    $Self->Change( Callback => sub { delete $_[0]->{ $_ } for @DiedCollectors } );

    return 1;
}

sub UpdateDefaultMetrics {
    my ( $Self, %Param ) = @_;

    my $MetricManager        = $Kernel::OM->Get('Kernel::System::Prometheus::MetricManager');
    my $TicketMetricEnabled  = $MetricManager->IsMetricEnabled('OTRSTicketTotal');
    my $ArticleMetricEnabled = $MetricManager->IsMetricEnabled('OTRSArticleTotal');

    unless( $TicketMetricEnabled || $ArticleMetricEnabled ) {
        return;
    }

    my $DBObject = $Kernel::OM->Get('Kernel::System::DB');

    # Get article total info
    my @ArticleInfo;

    if ($ArticleMetricEnabled) {
        return if !$DBObject->Prepare(
            SQL => 'SELECT queue.name, ticket_state.name, COUNT(*) FROM article
                    JOIN ticket ON article.ticket_id = ticket.id
                    JOIN queue ON ticket.queue_id = queue.id
                    JOIN ticket_state ON ticket.ticket_state_id = ticket_state.id
                    GROUP BY queue.name, ticket_state.name',
        );

        while ( my @Row = $DBObject->FetchrowArray() ) {
            my ( $Queue, $Status, $Num ) = @Row;
            push @ArticleInfo, [ $Queue, $Status, $Num ];
        }
    }

    # Get ticket info
    my @TicketInfo;

    if($TicketMetricEnabled) {
        return if !$DBObject->Prepare(
            SQL => 'SELECT queue.name, ticket_state.name, count(*) FROM ticket
                    JOIN queue ON queue.id = ticket.queue_id
                    JOIN ticket_state ON ticket_state.id = ticket.ticket_state_id
                    GROUP BY queue.name, ticket_state.name',
        );

        while ( my @Row = $DBObject->FetchrowArray() ) {
            my ( $Queue, $Status, $Num ) = @Row;
            push @TicketInfo, [ $Queue, $Status, $Num ];
        }
    }

    # Record info as metrics
    my $Host = $Kernel::OM->Get('Kernel::System::Prometheus::Helper')->GetHost();

    $Self->Change(
        Callback => sub {
            my $Metrics = shift;

            if (@ArticleInfo) {
                for my $Row (@ArticleInfo) {
                    my ( $Queue, $Status, $Num ) = @$Row;
                    $Metrics->{OTRSArticleTotal}->set( $Host, $Queue, $Status, $Num );
                }
            }

            if (@TicketInfo) {
                for my $Row (@TicketInfo) {
                    my ( $Queue, $Status, $Num ) = @$Row;
                    $Metrics->{OTRSTicketTotal}->set( $Host, $Queue, $Status, $Num );
                }
            }

            return 1;
        }
    );

    return 1;
}

sub UpdateCustomSQLMetrics {
    my $Self = shift;

    my $MetricManager = $Kernel::OM->Get('Kernel::System::Prometheus::MetricManager');

    return if !$MetricManager->IsCustomMetricsEnabled();

    my $CustomMetricsSQLInfo = $MetricManager->CustomMetricsSQLInfoGet();

    return if !$CustomMetricsSQLInfo;

    my $DBObject = $Kernel::OM->Get('Kernel::System::DB');

    my %SQLQueryResults;
    for my $MetricName ( keys %{ $CustomMetricsSQLInfo } ) {
        return if !$DBObject->Prepare(
            SQL => $CustomMetricsSQLInfo->{ $MetricName }{SQL},
        );

        my @Rows;

        while ( my @Row = $DBObject->FetchrowArray() ) {
            push @Rows, \@Row;
        }

        $SQLQueryResults{ $MetricName } = \@Rows;
    }

    $Self->Change (
        Callback => sub {
            my $Metrics = shift;

            for my $MetricName ( keys %SQLQueryResults ) {
                my $UpdateMethod = $CustomMetricsSQLInfo->{ $MetricName }{Method};
                my $QueryResult  = $SQLQueryResults{ $MetricName };

                for my $RowRef (@{ $QueryResult }) {
                    $Metrics->{ $MetricName }->$UpdateMethod(@$RowRef);
                }
            }

            return 1;
        },
    );

    return 1;
}

sub IsAllCustomMetricsCreated {
    my ( $Self, %Param ) = @_;

    my $MetricManager = $Kernel::OM->Get('Kernel::System::Prometheus::MetricManager');

    my $CustomMetricNames = $MetricManager->AllCustomMetricsNamesGet();

    my @CreatedMetricNames = keys %{ $Self->{Guard}->Fetch() || {} };

    for my $CustomMetricName ( @$CustomMetricNames ) {
        if ( !any { $_ eq $CustomMetricName } @CreatedMetricNames ) {
            return;
        }
    }

    return 1;
}

sub MergeCustomMetrics {
    my $Self = shift;

    my $MetricManager = $Kernel::OM->Get('Kernel::System::Prometheus::MetricManager');

    return if !$MetricManager->IsCustomMetricsEnabled();

    my $CustomMetrics = $MetricManager->CreateCustomMetrics();

    $Self->Change(
        Callback => sub {
            my $Metrics = shift;

            for my $CustomMetricName ( keys %$CustomMetrics ) {
                $Metrics->{ $CustomMetricName } //= $CustomMetrics->{ $CustomMetricName };
            }

            return 1;
        }
    );

    return 1;
}

sub ClearMemory {
    my $Self = shift;

    $Self->Change( Callback => sub { $_[0] = {} } );
    $Self->_CreateMetrics();
}

sub _LoadSharedMetrics {
    my $Self = shift;

    my $SharedMetrics = $Self->{Guard}->Fetch();

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

sub _CreateMetrics {
    my $Self = shift;

    my $MetricManager = $Kernel::OM->Get('Kernel::System::Prometheus::MetricManager');

    my $Metrics = $MetricManager->CreateDefaultMetrics();

    if ($MetricManager->IsCustomMetricsEnabled()) {
        my $CustomMetrics = $MetricManager->CreateCustomMetrics();
        for my $CustomMetricName ( keys %$CustomMetrics ) {
            $Metrics->{$CustomMetricName} = $CustomMetrics->{$CustomMetricName};
        }
    }

    $Self->{Guard}->Store( Data => $Metrics );

    return 1;
}

1
