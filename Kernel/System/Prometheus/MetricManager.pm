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

our @ObjectDependencies = (
    'Kernel::Config',
);

sub new {
    my ( $Type, %Param ) = @_;

    my $Self = {};
    bless( $Self, $Type );

    $Self->{EnabledMetricNames} = $Kernel::OM->Get('Kernel::Config')->Get('Prometheus::Metrics::Default::Enabled');

    return $Self;
}

sub IsMetricEnabled {
    my ( $Self, $MetricName ) = @_;

    if ( any { $_ eq $MetricName } @{ $Self->{EnabledMetricNames} } ) {
        return 1;
    }

    return 0;
}

sub IsCustomMetricsEnabled {
    my $Self = shift;
    return $Kernel::OM->Get('Kernel::Config')->Get('Prometheus::Metrics::Custom::IsEnabled');
}

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

    for my $MetricName (@{ $Self->{EnabledMetricNames} }) {
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

1
