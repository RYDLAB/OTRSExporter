#--
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
use List::Util qw(any);
use Kernel::System::VariableCheck qw( IsArrayRefWithData IsHashRefWithData );
use Scalar::Util qw(looks_like_number);

our @ObjectDependencies = (
    'Kernel::Config',
    'Kernel::System::DB',
    'Kernel::System::Log',
);

sub new {
    my ( $Type, %Param ) = @_;

    my $Self = {};
    bless( $Self, $Type );

    $Self->{_EnabledDefaultMetrics} = $Kernel::OM->Get('Kernel::Config')->Get('Prometheus::Metrics::Default::Enabled');

    return $Self;
}

sub IsMetricEnabled {
    my ( $Self, $MetricName ) = @_;

    return $Self->{_EnabledDefaultMetrics}{$MetricName};
}

sub IsCustomMetricsEnabled {
    my $Self = shift;
    return $Kernel::OM->Get('Kernel::Config')->Get('Prometheus::Metrics::Custom::IsEnabled');
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
        if (!ref $Param{$ComplexParameter}) {
            $Param{$ComplexParameter} = [ split /[\W]+/, $Param{$ComplexParameter} ];
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
            my @Row = $DBObject->FetchrowArray;
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

# TODO: write put metric method
=head1 DEVELOPMENT STAGE
sub PutMetric {
    my ( $Self, %Param ) = @_;

    my $DBObject  = $Kernel::OM->Get('Kernel::System::DB');
    my $LogObject = $Kernel::OM->Get('Kernel::System::Log');

    # get metric type id in database
    my $MetricTypeId = 0; 
    $Param{MetricType} = lc $Param{MetricType};

    # check for existing database
    return if !$DBObject->Prepare(
        SQL => 'SELECT id FROM prometheus_custom_metrics
                WHERE name = ?',
        Bind => [ $Param{MetricName} ],
    );

    if ( $DBObject->FetchrowArray ) {
        $LogObject->Log(
            Priority => 'Error',
            Message  => 'Metric already exists in database!',
        );

        return;
    }

    # Put metric in DB
    return if !$DBObject->Do(
        SQL => 'INSERT INTO prometheus_custom_metrics(name, help, metric_type_id, metric_namespace) VALUES 
                (?, ?, ?, ?)',
        Bind => [ $Param{MetricName}, $Param{MetricHelp}, $MetricTypeId, $Param{MetricNamespace} ],
    );

    unless ( $Param{MetricLabels} || $Param{MetricBuckets} || $Param{SQL} ) {
        return 1;
    }

    # get created metric's ID
    return if !$DBObject->Prepare(
        SQL  => 'SELECT id FROM prometheus_custom_metrics WHERE name = ?',
        Bind => [ $Param{MetricName} ],
    );
    
    my $CustomMetricId = $DBObject->FetchrowArray;

    # labels and buckets can be a string. fix it
    for my $ComplexParameter (qw( MetricLabels MetricBuckets )) {
        if (!ref $Param{$ComplexParameter}) {
            $Param{$ComplexParameter} = [ split /[\W]+/, $Param{$ComplexParameter} ];
        }
    }

    if ($Param{MetricLabels}) {
        for my $Label (@{ $Param{MetricLabels} }) {

            state $QueueNum = 0;

            return if !$DBObject->Do(
                SQL  => 'INSERT INTO prometheus_custom_metric_labels(name, custom_metric_id, queue_num)
                         VALUES ( ?, ?, ? )',
                Bind => [ $Label, $CustomMetricId, $QueueNum ],
            );

            $QueueNum++;
        }
    }

    if ($Param{MetricBuckets}) {
        for my $Bucket (@{ $Param{MetricBuckets} }) {
            return if !$DBObject->Do(
                SQL  => 'INSERT INTO prometheus_custom_metric_buckets(custom_metric_id, value)
                        VALUES (?, ?)',
                Bind => [ $CustomMetricId, $Bucket ],
            );
        }
    }

    if ( $Param{SQL} && $Param{UpdateMethod} ) {
        return if !$DBObject->Do(
            SQL => 'INSERT INTO prometheus_custom_metric_sql (query_text, custom_metric_id, update_method_id)
                    VALUES (?, ?, )',
        );
    }
}
=cut

sub CreateCustomMetrics {
    my $Self = shift;

    my $CustomMetricTemplates = $Kernel::OM->Get('Kernel::Config')->Get('Prometheus::Metrics::Custom::Configuration');

    return if !IsArrayRefWithData($CustomMetricTemplates);

    my $MetricMaker = Net::Prometheus->new;
    my $ValidMetricTypes = $Kernel::OM->Get('Kernel::Config')->Get('Prometheus::MetricTypes');

    my %CustomMetrics;

    for my $Template ( @{$CustomMetricTemplates} ) {
        next if !IsArrayRefWithData($Template->{Type});
        next if !IsArrayRefWithData($Template->{Name});
        next if !IsArrayRefWithData($Template->{Help});

        my $Type = lc $Template->{Type}[0];
        unless ( any { $_ eq $Type } @{$ValidMetricTypes} ) {
            next;
        }

        my $CreatingMethod = "new_$Type";
        my $Namespace = lc $Template->{Namespace}[0] if IsArrayRefWithData($Template->{Namespace});
        my $Name = lc $Template->{Name}[0];
        my $Help = $Template->{Help}[0];
        my $Labels = $Template->{Labels} if IsArrayRefWithData($Template->{Labels});
        my $Buckets = $Template->{Buckets} if IsArrayRefWithData($Template->{Buckets});

        $CustomMetrics{$Name} = $MetricMaker->$CreatingMethod(
            namespace => $Namespace // undef,
            name      => $Name,
            help      => $Help,
            labels    => $Labels    // undef,
            buckets   => $Buckets   // undef,
        );
    }

    return \%CustomMetrics;
}

sub CreateDefaultMetrics {
    my $Self = shift;

    my $Constructors = $Self->_GetDefaultMetricsConstructors;
    my $Metrics = {};

    for my $MetricName (keys %{ $Self->{_EnabledDefaultMetrics} }) {
        next if !$Constructors->{$MetricName};
        $Metrics->{$MetricName} = $Constructors->{$MetricName}();
    }

    return $Metrics;
}

sub _GetDefaultMetricsConstructors {
    my $Self = shift;

    my $MetricCreator = Net::Prometheus->new;
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

        CacheOperations => sub {
            $MetricCreator->new_counter(
                namespace => 'cache',
                name      => 'operations',
                help      => 'Number of calls methods to manipulate cache',
                labels    => [qw( host operation )],
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

#TODO: write database api to manage metrics
=head1 Database API for metrics

Development stage...

sub MetricTypesGet {
    my $Self = shift;

    my $DBObject = $Kernel::OM->Get('Kernel::System::DB');

    return if !$DBObject->Prepare( SQL => 'SELECT type_name, id FROM prometheus_metric_types' );

    my %Types;
    while ( my @Row = $DBObject->FetchrowArray ) {
        $Types{$Row[0]} = $Row[1];
    }

    return \%Types;
}

sub CustomMetricsGet {
    my ( $Self, %Param ) = @_;

    if (!$Param{MetricName}) {
        $Kernel::OM->Get('Kernel::System::Log')->Log(
            Priority => 'Error',
            Message  => 'Need metric name!',
        );
    }

    my $DBObject = $Kernel::OM->Get('Kernel::System::DB');

    return if !$DBObject->Prepare( SQL => 'SELECT' );
}
=cut

1
