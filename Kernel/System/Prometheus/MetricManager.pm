#Copyright (C) 2001-2020 OTRS AG, https://otrs.com/
#--
#This software comes with ABSOLUTELY NO WARRANTY. For details, see
#the enclosed file COPYING for license information (GPL). If you
#did not receive this file, see https://www.gnu.org/licenses/gpl-3.0.txt.
#--

package Kernel::System::Prometheus::MetricManager;

use strict;
use warnings;

use Net::Prometheus;
use Scalar::Util qw(looks_like_number);

our @ObjectDependencies = (
    'Kernel::Config',
    'Kernel::System::DB',
    'Kernel::System::Log',
);

=head1 NAME

    Kernel::System::Prometheus::MetricManager

=head1 DESCRIPTION

    Object to manipulate data of default and custom metrics.

=cut

sub new {
    my ( $Type, %Param ) = @_;

    my $Self = {};
    bless( $Self, $Type );

    my $Settings = $Kernel::OM->Get('Kernel::Config')->Get('Prometheus::Settings') // {};
    $Self->{_DefaultMetrics} = $Settings->{DefaultMetrics};

    return $Self;
}

sub IsMetricEnabled {
    my ( $Self, $MetricName ) = @_;

    return $Self->{_DefaultMetrics}{$MetricName} // 0;
}

sub IsCustomMetricsEnabled {
    my $Self = shift;

    return $Kernel::OM->Get('Kernel::Config')->Get('Prometheus::Settings')->{CustomMetrics};
}

sub TryMetric {
    my ( $Self, %Param ) = @_;

    my $LogObject = $Kernel::OM->Get('Kernel::System::Log');

    for my $Needed (qw( MetricName MetricHelp MetricType )) {
        if (!$Param{$Needed}) {
            $LogObject->Log(
                Priority => 'error',
                Message  => "Need $Needed to try create metric!",
            );
        }
    }

    my $MetricCreator = Net::Prometheus->new;
    my $CreatingMethod = 'new_' . lc $Param{MetricType};

    for my $ComplexParameter (qw( MetricLabels MetricBuckets )) {
        if ( ref $Param{$ComplexParameter} ne 'ARRAY' ) {
            $Param{$ComplexParameter} = [ split /\W+/, $Param{$ComplexParameter} ];
        }
    }

    if ($Param{MetricBuckets}) {
        for my $Bucket (@{ $Param{MetricBuckets} }) {
            if (!looks_like_number($Bucket)) {
                $LogObject->Log(
                    Priority => 'error',
                    Message  => 'One or more buckets are not number!',
                );

                return;
            }
        }
    }

    my $Metric = eval {
        $MetricCreator->$CreatingMethod(
            namespace => $Param{MetricNamespace},
            name      => $Param{MetricName},
            help      => $Param{MetricHelp},
            labels    => $Param{MetricLabels},
            buckets   => $Param{MetricBuckets},
        );
    };

    if (!$Metric) {
        $LogObject->Log(
            Priority => 'error',
            Message  => $@ || 'Something went wrong while trying to create metric',
        );

        return;
    }

    if ($Param{SQL}) {

        if (!$Param{UpdateMethod}) {
            $LogObject->Log(
                Priority => 'error',
                Message  => 'Need metric method with SQL!',
            );

            return;
        }

        my $DBObject = $Kernel::OM->Get('Kernel::System::DB');
        my $UpdateMethod = $Param{UpdateMethod};

        if (
            $DBObject->Prepare(
                SQL => $Param{SQL},
            )
            )
        {
            my @Row = $DBObject->FetchrowArray();
            unless( eval { $Metric->$UpdateMethod(@Row) } )
            {
                $LogObject->Log(
                    Priority => 'error',
                    Message  => $@ || 'Something went wrong while trying to update metric',
                );

                return;
            }
        }

        else { return }
    }

    return 1;
}

sub CreateCustomMetrics {
    my $Self = shift;

    my $CustomMetricsInfo = $Self->AllCustomMetricsInfoGet;

    my $MetricCreator = Net::Prometheus->new();

    my %CustomMetrics;
    for my $MetricInfo (@{ $CustomMetricsInfo }) {
        my $CreateMethod = 'new_' . lc $MetricInfo->{Type};

        $CustomMetrics{$MetricInfo->{Name}} = $MetricCreator->$CreateMethod(
            namespace => $MetricInfo->{Namespace},
            name      => $MetricInfo->{Name},
            help      => $MetricInfo->{Help},
            labels    => $MetricInfo->{Labels},
            buckets   => $MetricInfo->{Buckets},
        );
    }

    return \%CustomMetrics;
}

sub CreateDefaultMetrics {
    my $Self = shift;

    my $Constructors = $Self->_GetDefaultMetricsConstructors;
    my $Metrics = {};

    for my $MetricName (keys %{ $Self->{_DefaultMetrics} }) {
        if ($MetricName eq 'DaemonSubworkersMetrics') {
            $Metrics->{DaemonSubworkersTotal} = $Constructors->{DaemonSubworkersTotal}();
            $Metrics->{DaemonSubworkersLastExecutionTime} = $Constructors->{DaemonSubworkersLastExecutionTime}();
            next;
        }

        elsif ($MetricName eq 'RecurrentTasksMetrics') {
            $Metrics->{RecurrentTaskDuration} = $Constructors->{RecurrentTaskDuration}();
            $Metrics->{RecurrentTaskSuccess}  = $Constructors->{RecurrentTaskSuccess}();
            next;
        }

        next if !$Constructors->{$MetricName};
        $Metrics->{$MetricName} = $Constructors->{$MetricName}();
    }

    return $Metrics;
}

sub GetLabelsFromSQL {
    my ( $Self, %Param ) = @_;

    if ( !$Param{SQL} ) {
        $Kernel::OM->Get('Kernel::System::Log')->Log(
            Priority => 'Error',
            Message  => 'Need SQL!',
        );

        return;
    }

    my $DBObject = $Kernel::OM->Get('Kernel::System::DB');
    return if !$DBObject->Prepare( SQL => $Param{SQL} );

    my @Labels = $DBObject->GetColumnNames;

    # Pop last column ( it is value column )
    pop @Labels;

    return \@Labels;
}

sub _GetDefaultMetricsConstructors {
    my $Self = shift;

    my $MetricCreator = Net::Prometheus->new();
    my $HTTPMetricGroup = $MetricCreator->new_metricgroup(namespace => 'http');
    my $OTRSMetricGroup = $MetricCreator->new_metricgroup(namespace  => 'otrs');
    my $RecurrentTasksMetricGroup = $MetricCreator->new_metricgroup(namespace => 'recurrent_task');

    return {
        HTTPRequestDurationSeconds => sub {
            $HTTPMetricGroup->new_histogram(
                name    => 'request_duration_seconds',
                help    => 'The duration of the request in seconds',
                labels  => [qw( host worker method route )],
            );
        },

        HTTPResponseSizeBytes => sub {
            $HTTPMetricGroup->new_histogram(
                name    => 'response_size_bytes',
                help    => 'The size of the response in bytes',
                labels  => [qw( host worker)],
                buckets => [ 50, 100, 500, 1000, 5000, 10000, 25000, 50000, 100000, 1000000 ],
            );
        },

        HTTPRequestsTotal => sub {
            $HTTPMetricGroup->new_counter(
                name   => 'requests_total',
                help   => 'The total number of the HTTP requests',
                labels => [qw( host worker)],
            );
        },

        OTRSIncomeMailTotal => sub {
            $OTRSMetricGroup->new_counter(
                name   => 'income_mail_total',
                help   => 'The number of incoming mail',
                labels => [qw(host)],
            );
        },

        OTRSOutgoingMailTotal => sub {
            $OTRSMetricGroup->new_counter(
                name   => 'outgoing_mail_total',
                help   => 'The number of outgoing mail',
                labels => [qw(host)],
            );
        },

        OTRSReallySendedMailTotal => sub {
            $OTRSMetricGroup->new_counter(
                name   => 'really_sended_mail_total',
                help   => 'The number of really sended mail',
                labels => [qw(host)],
            );
        },

        OTRSTicketTotal => sub {
            $OTRSMetricGroup->new_gauge(
                name   => 'ticket_total',
                help   => 'The number of tickets',
                labels => [qw( host queue status )],
            );
        },

        OTRSArticleTotal => sub {
            $OTRSMetricGroup->new_gauge(
                name   => 'article_total',
                help   => 'The number of the articles',
                labels => [qw( host queue status )],
            );
        },

        OTRSLogsTotal => sub {
            $OTRSMetricGroup->new_counter(
                name   => 'logs_total',
                help   => 'The number of the logs',
                labels => [qw( host priority prefix module )],
            );
        },

        CacheOperations => sub {
            $MetricCreator->new_counter(
                namespace => 'cache',
                name      => 'operations',
                help      => 'Number of calls methods to manipulate cache',
                labels    => [qw( host operation )],
            );
        },

        DaemonSubworkersTotal => sub {
            $MetricCreator->new_counter(
                namespace => 'daemon_subworkers',
                name      => 'total',
                help      => 'Number of workers, executing in Kernel::System::Daemon::DaemonModules::SchedulerTaskWorker',
                labels    => [qw( host task_handler_module task_name )],
            );
        },

        DaemonSubworkersLastExecutionTime => sub {
            $MetricCreator->new_gauge(
                namespace => 'daemon_subworkers',
                name      => 'task_last_execution_time',
                help      => 'Last execution time for each daemon task',
                labels    => [qw( host task_handler_module task_name )],
            );
        },

        RecurrentTaskDuration => sub {
            $RecurrentTasksMetricGroup->new_gauge(
                name      => 'duration',
                help      => 'Duration of the recurrent daemon tasks',
                labels    => [qw( host name )],
                buckets   => [ 1, 2, 3, 4, 5, 6, 7, 9, 10, 15, 20, 40, 60, 120 ],
            );
        },

        RecurrentTaskSuccess => sub {
            $RecurrentTasksMetricGroup->new_gauge(
                name      => 'success',
                help      => 'Last recurrent task worker result',
                labels    => [qw( host name )],
            );
        },
    };
}

=head1 Database API for metrics

=cut

sub MetricTypesGet {
    my $Self = shift;

    my $DBObject = $Kernel::OM->Get('Kernel::System::DB');

    return if !$DBObject->Prepare( SQL => 'SELECT type_name, id FROM metric_types' );

    my %Types;
    while ( my @Row = $DBObject->FetchrowArray() ) {
        $Types{$Row[0]} = $Row[1];
    }

    return \%Types;
}

sub AllCustomMetricsNamesGet {
    my ( $Self, %Param ) = @_;

    my $DBObject = $Kernel::OM->Get('Kernel::System::DB');

    return if !$DBObject->Prepare(SQL => 'SELECT name FROM custom_metrics');

    my @Names;

    while ( my @Row = $DBObject->FetchrowArray() ) {
        push @Names, $Row[0];
    }

    return \@Names;
}

sub AllCustomMetricsInfoGet {
    my $Self = shift;

    my $DBObject = $Kernel::OM->Get('Kernel::System::DB');

    my @CustomMetrics;

    return if !$DBObject->Prepare(
        SQL => 'SELECT metr.id, metr.namespace, metr.name, metr.help, types.type_name, sqls.query_text, methods.name
                FROM custom_metrics metr
                JOIN metric_types types ON metr.metric_type_id = types.id
                LEFT JOIN custom_metric_sql sqls ON metr.id = sqls.custom_metric_id
                LEFT JOIN metric_update_methods methods ON sqls.update_method_id = methods.id
                ORDER BY metr.name'
    );

    # get main info about custom_metric
    while ( my @Row = $DBObject->FetchrowArray() ) {

        my $Metric = {
            Id           => $Row[0],
            Namespace    => $Row[1],
            Name         => $Row[2],
            Help         => $Row[3],
            Type         => $Row[4],
            SQL          => $Row[5],
            UpdateMethod => $Row[6],
        };

        push @CustomMetrics, $Metric;
    }

    for my $Metric ( @CustomMetrics ) {

        # get labels info
        return if !$DBObject->Prepare(
            SQL  => 'SELECT labels.name FROM custom_metrics metr
                     JOIN custom_metric_labels labels ON labels.custom_metric_id = metr.id
                     WHERE metr.id = ?
                     ORDER BY queue_num',
            Bind => [\($Metric->{Id})],
        );

        my @Labels;
        while ( my @Row = $DBObject->FetchrowArray() ) {
            push @Labels, $Row[0];
        }

        $Metric->{Labels} = \@Labels;

        # get buckets info
        return if !$DBObject->Prepare(
            SQL  => 'SELECT buckets.value FROM custom_metrics metr
                     JOIN custom_metric_buckets buckets ON buckets.custom_metric_id = metr.id
                     WHERE metr.id = ?',
            Bind => [\($Metric->{Id})],
        );

        my @Buckets;
        while ( my @Row = $DBObject->FetchrowArray() ) {
            push @Buckets, $Row[0];
        }

        $Metric->{Buckets} = \@Buckets;
    }

    return \@CustomMetrics;
}

sub CustomMetricsSQLInfoGet {
    my $Self = shift;

    my $DBObject = $Kernel::OM->Get('Kernel::System::DB');

    return if !$DBObject->Prepare(
        SQL => 'SELECT metr.name, sql.query_text, method.name
                FROM custom_metrics metr
                JOIN custom_metric_sql sql ON metr.id = sql.custom_metric_id
                JOIN metric_update_methods method ON sql.update_method_id = method.id',
    );

    my %MetricsSQLInfo;

    while ( my @Row = $DBObject->FetchrowArray() ) {
        my ( $MetricName, $SQL, $Method ) = @Row;
        $MetricsSQLInfo{ $MetricName } = { SQL => $SQL, Method => $Method };
    }

    return \%MetricsSQLInfo;
}

sub UpdateMethodsGet {
    my ( $Self, %Param ) = @_;

    if (!$Param{MetricTypeId}) {

        if (!$Param{MetricType}) {
            $Kernel::OM->Get('Kernel::System::Log')->Log(
                Priority => 'Error',
                Message  => 'Need metric type to find update methods!',
            );

            return;
        }

        my $MetricTypes = $Self->MetricTypesGet;

        unless ( $Param{MetricTypeId} = $MetricTypes->{ lc $Param{MetricType} } ) {
            $Kernel::OM->Get('Kernel::System::Log')->Log(
                Priority => 'error',
                Message  => 'Wrong metric type!',
            );

            return;
        }
    }

    my $DBObject = $Kernel::OM->Get('Kernel::System::DB');

    return if !$DBObject->Prepare(
        SQL  => 'SELECT name, id FROM metric_update_methods
                 WHERE metric_type_id = ?',
        Bind => [ \$Param{MetricTypeId} ],
    );

    my %UpdateMethods;
    while ( my @Row = $DBObject->FetchrowArray() ) {
        $UpdateMethods{$Row[0]} = $Row[1];
    }

    return \%UpdateMethods;
}

sub CustomMetricGet {
    my ( $Self, %Param ) = @_;

    unless ( $Param{MetricName} || $Param{MetricID} ) {
        $Kernel::OM->Get('Kernel::System::Log')->Log(
            Priority => 'Error',
            Message  => 'Need metric name or ID!',
        );

        return;
    }

    my $DBObject = $Kernel::OM->Get('Kernel::System::DB');

    if (!$Param{MetricID}) {
        return if !$DBObject->Prepare(
            SQL   => 'SELECT metr.id FROM custom_metrics metr WHERE metr.name = ?',
            Bind  => [\$Param{MetricName}],
            Limit => 1,
        );

        while ( my @Row = $DBObject->FetchrowArray() ) {
            $Param{MetricID} = $Row[0];
        }
    }

    return if !$DBObject->Prepare(
        SQL   => 'SELECT metr.id, metr.namespace, metr.name, metr.help, types.type_name, sqls.query_text, methods.name
                  FROM custom_metrics metr
                  JOIN metric_types types ON metr.metric_type_id = types.id
                  LEFT JOIN custom_metric_sql sqls ON metr.id = sqls.custom_metric_id
                  LEFT JOIN metric_update_methods methods ON sqls.update_method_id = methods.id
                  WHERE metr.id = ?',
        Bind  => [\$Param{MetricID}],
        Limit => 1,
    );

    my %CustomMetric;
    while ( my @Row = $DBObject->FetchrowArray() ) {
        %CustomMetric = (
            Id           => $Row[0],
            Namespace    => $Row[1],
            Name         => $Row[2],
            Help         => $Row[3],
            Type         => $Row[4],
            SQL          => $Row[5],
            UpdateMethod => $Row[6],
        );
    }

    return if !%CustomMetric;

    # get labels info
    return if !$DBObject->Prepare(
        SQL  => 'SELECT labels.name FROM custom_metrics metr
                 JOIN custom_metric_labels labels ON labels.custom_metric_id = metr.id
                 WHERE metr.id = ?
                 ORDER BY queue_num',
        Bind => [\($CustomMetric{Id})],
    );

    my @Labels;
    while ( my @Row = $DBObject->FetchrowArray() ) {
        push @Labels, $Row[0];
    }

    $CustomMetric{Labels} = \@Labels;

    # get buckets info
    return if !$DBObject->Prepare(
        SQL  => 'SELECT buckets.value FROM custom_metrics metr
                 JOIN custom_metric_buckets buckets ON buckets.custom_metric_id = metr.id
                 WHERE metr.id = ?',
        Bind => [\($CustomMetric{Id})],
    );

    my @Buckets;
    while ( my @Row = $DBObject->FetchrowArray() ) {
        push @Buckets, $Row[0];
    }

    $CustomMetric{Buckets} = \@Buckets;


    return \%CustomMetric;
}

sub NewCustomMetric {
    my ( $Self, %Param ) = @_;

    for my $RequiredParam (qw( MetricName MetricHelp MetricType )) {
        if (!$Param{$RequiredParam}) {
            $Kernel::OM->Get('Kernel::System::Log')->Log(
                Priority => 'Error',
                Message  => "Need $RequiredParam!",
            );
            return;
        }
    }

    if ( eval { $Self->CustomMetricGet( MetricName => $Param{MetricName} )->{Id} } ) {
        $Kernel::OM->Get('Kernel::System::Log')->Log(
            Priority => 'Error',
            Message  => 'Metric with this name already exists!',
        );

        return;
    }

    my $MetricTypes = $Self->MetricTypesGet;

    $Param{MetricType} = lc $Param{MetricType};
    $Param{MetricNamespace} //= '';

    unless ( $MetricTypes->{$Param{MetricType}} ) {
        $Kernel::OM->Get('Kernel::System::Log')->Log(
            Priority => 'Error',
            Message  => 'Wrong metric type!',
        );

        return;
    }

    my $DBObject = $Kernel::OM->Get('Kernel::System::DB');

    return if !$DBObject->Do(
        SQL  => 'INSERT INTO custom_metrics(name, help, namespace, metric_type_id)
                 VALUES ( ?, ?, ?, ? )',
        Bind => [\( @Param{qw/ MetricName MetricHelp MetricNamespace /}, $MetricTypes->{$Param{MetricType}} )],
    );

    my $CustomMetricId = $Self->CustomMetricGet( MetricName => $Param{MetricName} )->{Id};

    # labels and buckets can be a one string. fix it
    for my $ComplexParameter (qw( MetricLabels MetricBuckets )) {
        if ($Param{$ComplexParameter} && !ref $Param{$ComplexParameter}) {
            $Param{$ComplexParameter} = [ split /[, ]/, $Param{$ComplexParameter} ];
        }
    }

    if ($Param{MetricLabels}) {
        my $QueueNum = 0;
        for my $Label (@{ $Param{MetricLabels} }) {

            return if !$DBObject->Do(
                SQL  => 'INSERT INTO custom_metric_labels( name, custom_metric_id, queue_num )
                         VALUES ( ?, ?, ? )',
                Bind => [\( $Label, $CustomMetricId, $QueueNum )],
            );

            $QueueNum++;
        }
    }

    if ($Param{MetricBuckets}) {
        for my $Bucket (@{ $Param{MetricBuckets} }) {
            return if !$DBObject->Do(
                SQL  => 'INSERT INTO custom_metric_buckets(custom_metric_id, value)
                         VALUES ( ?, ? )',
                Bind => [\($CustomMetricId, $Bucket)],
            );
        }
    }

    if ( $Param{SQL} || $Param{UpdateMethod} ) {
        my $MetricUpdateMethods = $Self->UpdateMethodsGet( MetricTypeId => $MetricTypes->{ $Param{MetricType} } );

        if (!$MetricUpdateMethods) {
            $Kernel::OM->Get('Kernel::System::Log')->Log(
                Priority => 'Error',
                Message  => 'Cant locate update-methods for this metric type!',
            );

            return;
        }

        return if !$DBObject->Do(
            SQL  => 'INSERT INTO custom_metric_sql(query_text, custom_metric_id, update_method_id)
                     VALUES ( ?, ?, ? )',
            Bind => [\($Param{SQL}, $CustomMetricId, $MetricUpdateMethods->{ $Param{UpdateMethod} }) ],
        );
    }

    return 1;
}

sub UpdateCustomMetricAllProps {
    my ( $Self, %Param ) = @_;

    # check required params
    for my $RequiredParameter (qw( MetricID MetricName MetricHelp MetricType )) {
        if ( !$Param{ $RequiredParameter } ) {
            $Kernel::OM->Get('Kernel::System::Log')->Log(
                Priority => 'Error',
                Message  => "Need $RequiredParameter",
            );

            return;
        }
    }

    # get metric_type_id
    my $MetricTypes = $Self->MetricTypesGet;
    $Param{MetricTypeID} = $MetricTypes->{ lc $Param{MetricType} };

    # update custom_metrics table
    my $DBObject = $Kernel::OM->Get('Kernel::System::DB');
    return if !$DBObject->Do(
        SQL  => 'UPDATE custom_metrics SET namespace = ?, name = ?, help = ?, metric_type_id = ?
                 WHERE id = ?',
        Bind => [\@Param{qw( MetricNamespace MetricName MetricHelp MetricTypeID MetricID )}],
    );

    # update custom_metric_sql

    # delete previous sql if exists
    return if !$DBObject->Do(
        SQL  => 'DELETE FROM custom_metric_sql WHERE custom_metric_id = ?',
        Bind => [\$Param{MetricID}],
    );
    # insert new value if exists
    if ( $Param{SQL} ) {
        if ( !$Param{UpdateMethod} ) {
            $Kernel::OM->Get('Kernel::System::Log')->Log(
                Priority => 'Error',
                Message  => 'Need UpdateMethod to insert SQL query!',
            );

            return;
        }

        # get update method id
        my $UpdateMethods = $Self->UpdateMethodsGet( MetricType => $Param{MetricType} );
        $Param{UpdateMethodID} = $UpdateMethods->{ lc $Param{UpdateMethod} };

        # insert new sql
        return if !$DBObject->Do(
            SQL  => 'INSERT INTO custom_metric_sql( query_text, custom_metric_id, update_method_id )
                     VALUES ( ?, ?, ? )',
            Bind => [\( @Param{qw( SQL MetricID UpdateMethodID )} )],
        );
    }

    # split buckets and labels if not array
    for my $ComplexParameter (qw( MetricLabels MetricBuckets )) {
        if ( ref $Param{ $ComplexParameter } ne 'ARRAY' ) {
            $Param{ $ComplexParameter }  = [ split /[, ]+/, $Param{ $ComplexParameter } ];
        }
    }

    # update custom_metric_buckets

    # delete previous buckets
    return if !$DBObject->Do(
        SQL  => 'DELETE FROM custom_metric_buckets WHERE custom_metric_id = ?',
        Bind => [ \$Param{MetricID} ],
    );

    # insert new buckets
    for my $Bucket (@{ $Param{MetricBuckets} }) {
        return if !$DBObject->Do(
            SQL  => 'INSERT INTO custom_metric_buckets( custom_metric_id, value )
                     VALUES ( ?, ? )',
            Bind => [ \$Param{MetricID}, \$Bucket ],
        );
    }

    # update custom_metric_labels

    # delete previous labels
    return if !$DBObject->Do(
        SQL  => 'DELETE FROM custom_metric_labels WHERE custom_metric_id = ?',
        Bind => [ \$Param{MetricID} ],
    );

    # insert new labels
    my $QueueNum = 0;
    for my $Label (@{ $Param{MetricLabels} }) {
        return if !$DBObject->Do(
            SQL  => 'INSERT INTO custom_metric_labels(name, custom_metric_id, queue_num)
                     VALUES ( ?, ?, ? )',
            Bind => [\( $Label, $Param{MetricID}, $QueueNum )],
        );
        $QueueNum++;
    }

    return 1;
}

sub UpdateCustomMetricNamespace {
    my ( $Self, %Param ) = @_;

    unless ( $Param{MetricNamespace} && $Param{MetricID} ) {
        $Kernel::OM->Get('Kernel::System::Log')->Log(
            Priority => 'error',
            Message  => 'Need MetricNamespace or MetricID !',
        );

        return;
    }

    return if !$Kernel::OM->Get('Kernel::System::DB')->Do(
        SQL  => 'UPDATE custom_metrics SET namespace = ? WHERE id = ?',
        Bind => [\(@Param{qw( MetricNamespace MetricID )})],
    );

    return 1;
}

sub UpdateCustomMetricName {
    my ( $Self, %Param ) = @_;

    unless ( $Param{MetricName} && $Param{MetricID} ) {
        $Kernel::OM->Get('Kernel::System::Log')->Log(
            Priority => 'error',
            Message  => 'Need MetricName or MetricID !',
        );

        return;
    }

    if ( eval { $Self->CustomMetricGet->{Id} } ) {
        $Kernel::OM->Get('Kernel::System::Log')->Log(
            Priority => 'error',
            Message  => 'Metric with this name already exists',
        );
    }

    return if !$Kernel::OM->Get('Kernel::System::DB')->Do(
        SQL  => 'UPDATE custom_metrics SET name = ? WHERE id = ?',
        Bind => [\(@Param{qw( MetricName MetricID )})],
    );

    return 1;
}

sub UpdateCustomMetricHelp {
    my ( $Self, %Param ) = @_;

    unless ( $Param{MetricHelp} && $Param{MetricID} ) {
        $Kernel::OM->Get('Kernel::System::Log')->Log(
            Priority => 'error',
            Message  => 'Need MetricHelp or MetricID !',
        );

        return;
    }

    return if !$Kernel::OM->Get('Kernel::System::DB')->Do(
        SQL  => 'UPDATE custom_metrics SET help = ? where id =?',
        Bind => [\(@Param{qw( MetricHelp MetricID )})],
    );

    return 1;
}

sub UpdateCustomMetricType {
    my ( $Self, %Param ) = @_;

    unless ( $Param{MetricType} && $Param{MetricID} ) {
        $Kernel::OM->Get('Kernel::System::Log')->Log(
            Priority => 'error',
            Message  => 'Need MetricType of MetricID',
        );

        return;
    }

    my $MetricTypes = $Self->MetricTypesGet;

    $Param{MetricTypeID} = $MetricTypes->{ $Param{MetricType} };

    if (!$Param{MetricTypeID}) {
        $Kernel::OM->Get('Kernel::System::Log')->Log(
            Priority => 'error',
            Message  => 'Wrong MetricType!',
        );

        return;
    }

    return if !$Kernel::OM->Get('Kernel::System::DB')->Do(
        SQL  => 'UPDATE custom_metrics SET metric_type_id = ? WHERE id = ?',
        Bind => [\(@Param{qw( MetricTypeID MetricID )})],
    );

    return 1;
}

sub UpdateCustomMetricSQL {
    my ( $Self, %Param ) = @_;

    unless ( $Param{SQL} && $Param{MetricID} ) {
        $Kernel::OM->Get('Kernel::System::Log')->Log(
            Priority => 'error',
            Message  => 'Need SQL or MetricID !',
        );

        return;
    }

    return if !$Kernel::OM->Get('Kernel::System::DB')->Do(
        SQL  => 'UPDATE custom_metric_sql SET query_text = ? WHERE custom_metric_id = ?',
        Bind => [\(@Param{qw( SQL MetricID )})],
    );

    return 1;
}

sub UpdateCustomMetricUpdateMethod {
    my ( $Self, %Param ) = @_;

    unless ( $Param{MetricType} && $Param{UpdateMethod} && $Param{MetricID} ) {
        $Kernel::OM->Get('Kernel::System::Log')->Log(
            Priority => 'error',
            Message  => 'Need UpdateMethod or MetricID',
        );

        return;
    }

    my $UpdateMethods = $Self->UpdateMethodsGet;
    $Param{UpdateMethodID} = $UpdateMethods->{ $Param{MetricType} };
    if (!$Param{UpdateMethodID}) {
        $Kernel::OM->Get('Kernel:System::Log')->Log(
            Priority => 'error',
            Message  => 'Wrong MetricType or UpdateMethod!',
        );

        return;
    }

    return if !$Kernel::OM->Get('Kernel::System::DB')->Do(
        SQL  => 'UPDATE custom_metric_sql SET update_method_id = ? WHERE custom_metric_id = ?',
        Bind => [\(@Param{qw( UpdateMethodID MetricID )})],
    );

    return 1;
}

sub DeleteMetric {
    my ( $Self, %Param ) = @_;

    if ( !$Param{MetricID} ) {
        $Kernel::OM->Get('Kernel::System::Log')->Log(
            Priority => 'Error',
            Message  => 'Need MetricID!',
        );

        return;
    }

    my $DBObject = $Kernel::OM->Get('Kernel::System::DB');

    # delete labels
    return if !$DBObject->Do(
        SQL  => 'DELETE FROM custom_metric_labels WHERE custom_metric_id = ?',
        Bind => [\$Param{MetricID}],
    );
    # delete buckets
    return if !$DBObject->Do(
        SQL  => 'DELETE FROM custom_metric_buckets WHERE custom_metric_id = ?',
        Bind => [\$Param{MetricID}],
    );
    # delete sql
    return if !$DBObject->Do(
        SQL  => 'DELETE FROM custom_metric_sql WHERE custom_metric_id = ?',
        Bind => [\$Param{MetricID}],
    );
    # delete metric
    return if !$DBObject->Do(
        SQL  => 'DELETE FROM custom_metrics WHERE id = ?',
        Bind => [\$Param{MetricID}],
    );

    return 1;
}

1
