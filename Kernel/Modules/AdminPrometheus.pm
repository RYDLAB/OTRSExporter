# --
# Copyright (C) 2001-2020 OTRS AG, https://otrs.com/
# --
# This software comes with ABSOLUTELY NO WARRANTY. For details, see
# the enclosed file COPYING for license information (GPL). If you
# did not receive this file, see https://www.gnu.org/licenses/gpl-3.0.txt.
# --

package Kernel::Modules::AdminPrometheus;

use strict;
use warnings;

use Kernel::System::VariableCheck qw(IsArrayRefWithData);

our $ObjectManagerDisabled = 1;

sub new {
    my ( $Type, %Param ) = @_;

    # allocate new hash for object
    my $Self = {%Param};
    bless( $Self, $Type );

    return $Self;
}

# TODO for each subaction write function
sub Run {
    my ( $Self, %Param ) = @_;

    my $ConfigObject = $Kernel::OM->Get('Kernel::Config');
    my $LayoutObject = $Kernel::OM->Get('Kernel::Output::HTML::Layout');
    my $ParamObject = $Kernel::OM->Get('Kernel::System::Web::Request');
    my $MetricManager = $Kernel::OM->Get('Kernel::System::Prometheus::MetricManager');

    if ( !$ConfigObject->Get('SecureMode') ) {
        return $LayoutObject->SecureMode();
    }

    if ( $Self->{Subaction} eq 'CreateMetric' ) {
        my %Errors;

        $LayoutObject->ChallengeTokenCheck();

        # get params
        for my $Parameter (
            qw( MetricNamespace MetricName MetricHelp MetricType
                MetricLabels MetricBuckets SQL UpdateMethod )
            )
        {
            $Param{$Parameter} = $ParamObject->GetParam( Param => $Parameter ) || '';
        }

        # Check required params
        for my $Parameter (qw( MetricName MetricHelp MetricType )) {
            if (!$Param{$Parameter}) {
                $Errors{ErrorType} = $Parameter.'Required';
                $Errors{ErrorMessage} = 'One or more required fields are empty!';
                last;
            }
        }

        if ($Param{SQL}) {
            if( uc($Param{SQL}) !~ m{ \A \s* (?:SELECT|SHOW|DESC) }smx ) {
                $Errors{ErrorType}  = 'SQLIsNotSelect';
                $Errors{ErrorMessage} = 'Only SELECT statements are available here!';
            }
        }

        #TODO: types and update methods we should take from database via model!
        $Param{MetricTypeStrg} = $LayoutObject->BuildSelection(
            Name  => 'MetricType',
            Data  => [qw( counter gauge histogram summary )],
            Class => 'Modernize',
            SelectedValue => $Param{MetricType},
        );

        $Param{UpdateMethods} = $LayoutObject->BuildSelection(
            Name  => 'UpdateMethod',
            Data  => [qw( inc dec set observe )],
            Class => 'Modernize',
            SelectedValue => $Param{UpdateMethod},
        );

        $Param{CustomMetrics} = $MetricManager->AllCustomMetricsInfoGet();
        for my $Metric (@{ $Param{CustomMetrics} }) {
            $Metric->{Labels} = join ', ', @{ $Metric->{Labels} };
            $Metric->{Buckets} = join ', ', @{ $Metric->{Buckets} };
        }

        if (!%Errors) {

            my $TestMetricSuccess = $MetricManager->TryMetric(%Param);

            if ($TestMetricSuccess) {
                my $CreateMetricSuccess = $MetricManager->NewCustomMetric(%Param);

                if ($CreateMetricSuccess) {

                    my $Output = $LayoutObject->Header();
                    $Output .= $LayoutObject->NavigationBar();
                    $Output .= $LayoutObject->Notify(
                        Info => "Metric $Param{MetricName} successfully created!",
                    );
                    $Output .= $LayoutObject->Output(
                        TemplateFile => 'AdminPrometheus',
                        Data         => \%Param,
                    );
                    $Output .= $LayoutObject->Footer();

                    return $Output;
                }

                $Errors{ErrorType} = 'PutMetricError';
                $Errors{ErrorMessage} = $Kernel::OM->Get('Kernel::System::Log')->GetLogEntry(
                    Type     => 'Error',
                    What     => 'Message',
                );
            }

            else {
                $Errors{ErrorType} = 'CheckMetricError';
                $Errors{ErrorMessage} = $Kernel::OM->Get('Kernel::System::Log')->GetLogEntry(
                    Type => 'Error',
                    What => 'Message',
                );
            }
        }

        # Print page with errors info
        $LayoutObject->Block( Name => $Errors{ErrorType} . 'ServerError' );

        my $Output = $LayoutObject->Header;
        $Output .= $LayoutObject->NavigationBar;
        $Output .= $LayoutObject->Notify(
            Info => $Errors{ErrorMessage},
            Priority => 'Error',
        );
        $Output .= $LayoutObject->Output(
            TemplateFile => 'AdminPrometheus',
            Data => {
                %Param,
                %Errors,
            },
        );
        $Output .= $LayoutObject->Footer();

        return $Output;
    }
    
    elsif ( $Self->{Subaction} eq 'ChangeMetric' ) {
        $Param{MetricID} = $ParamObject->GetParam( Param => 'ID' );

        my $MetricInfo = $MetricManager->CustomMetricGet( MetricID => $Param{MetricID} );
        use Data::Dumper;
        warn Dumper $MetricInfo;
        $Param{MetricNamespace} = $MetricInfo->{Namespace};
        $Param{MetricName} = $MetricInfo->{Name};
        $Param{MetricHelp} = $MetricInfo->{Help};
        $Param{SQL} = $MetricInfo->{SQL};
        $Param{MetricLabels} = join ' ', @{ $MetricInfo->{Labels} };
        $Param{MetricBuckets} = join ' ', @{ $MetricInfo->{Buckets} };

        $Param{MetricTypeStrg} = $LayoutObject->BuildSelection(
            Name          => 'MetricType',
            Data          => [qw( counter gauge histogram summary )],
            Class         => 'Modernize',
            SelectedValue => $MetricInfo->{Type},
        );

        $Param{UpdateMethods} = $LayoutObject->BuildSelection(
            Name  => 'UpdateMethod',
            Data  => [qw( inc dec set observe )],
            Class => 'Modernize',
            SelectedValue => $MetricInfo->{UpdateMethod},
        );

        my $Output = $LayoutObject->Header();
        $Output .= $LayoutObject->NavigationBar();
        $Output .= $LayoutObject->Output(
            TemplateFile => 'AdminPrometheusChangeMetric',
            Data         => \%Param,
        );
        $Output .= $LayoutObject->Footer();

        return $Output;
    }

    elsif ( $Self->{Subaction} eq 'ChangeMetricAction' ) {
        my %Errors;

        $LayoutObject->ChallengeTokenCheck();

        # get params
        for my $Parameter (
            qw( MetricID MetricNamespace MetricName MetricHelp MetricType
                MetricLabels MetricBuckets SQL UpdateMethod )
            )
        {
            $Param{$Parameter} = $ParamObject->GetParam( Param => $Parameter ) || '';
        }

        # Check required params
        for my $Parameter (qw( MetricName MetricHelp MetricType )) {
            if (!$Param{$Parameter}) {
                $Errors{ErrorType} = $Parameter.'Required';
                $Errors{ErrorMessage} = 'One or more required fields are empty!';
                last;
            }
        }

        if ($Param{SQL}) {
            if( uc($Param{SQL}) !~ m{ \A \s* (?:SELECT|SHOW|DESC) }smx ) {
                $Errors{ErrorType}  = 'SQLIsNotSelect';
                $Errors{ErrorMessage} = 'Only SELECT statements are available here!';
            }
        }

        #TODO: types and update methods we should take from database via model!
        $Param{MetricTypeStrg} = $LayoutObject->BuildSelection(
            Name  => 'MetricType',
            Data  => [qw( counter gauge histogram summary )],
            Class => 'Modernize',
            SelectedValue => $Param{MetricType},
        );

        $Param{UpdateMethods} = $LayoutObject->BuildSelection(
            Name  => 'UpdateMethod',
            Data  => [qw( inc dec set observe )],
            Class => 'Modernize',
            SelectedValue => $Param{UpdateMethod},
        );

        if ( !%Errors ) {
            my $TestMetricSuccess = $MetricManager->TryMetric(%Param);

            if ($TestMetricSuccess) {
                my $UpdateMetricSuccess = $MetricManager->UpdateCustomMetricAllProps(%Param);

                if ($UpdateMetricSuccess) {

                    my $Output = $LayoutObject->Header();
                    $Output .= $LayoutObject->NavigationBar();
                    $Output .= $LayoutObject->Notify(
                        Info => "Metric successfully changed!"
                    );
                    $Output .= $LayoutObject->Output(
                        TemplateFile => 'AdminPrometheusChangeMetric',
                        Data         => \%Param,
                    );
                    $Output .= $LayoutObject->Footer();

                    return $Output;
                }

                $Errors{ErrorType} = 'ChangeMetricError';
                $Errors{ErrorMessage} = $Kernel::OM->Get('Kernel::System::Log')->GetLogEntry(
                    Type => 'Error',
                    What => 'Message',
                );
            }
            else {
                $Errors{ErrorType} = 'CheckMetricError';
                $Errors{ErrorMessage} = $Kernel::OM->Get('Kernel::System::Log')->GetLogEntry(
                    Type => 'Error',
                    What => 'Message',
                );
            }
        }

        # Print page with errors info
        $LayoutObject->Block( Name => $Errors{ErrorType} . 'ServerError' );

        my $Output = $LayoutObject->Header();
        $Output .= $LayoutObject->NavigationBar;
        $Output .= $LayoutObject->Notify(
            Info => $Errors{ErrorMessage},
            Priority => 'Error',
        );
        $Output .= $LayoutObject->Output(
            TemplateFile => 'AdminPrometheusChangeMetric',
            Data => {
                %Param,
                %Errors,
            },
        );
        $Output .= $LayoutObject->Footer();

        return $Output;
    }

    #TODO: types and update methods we should take from database via model!
    $Param{MetricTypeStrg} = $LayoutObject->BuildSelection(
        Name  => 'MetricType',
        Data  => [qw( counter gauge histogram summary )],
        Class => 'Modernize',
    );

    $Param{UpdateMethods} = $LayoutObject->BuildSelection(
        Name  => 'UpdateMethod',
        Data  => [qw( inc dec set observe )],
        Class => 'Modernize',
    );

    $Param{CustomMetrics} = $MetricManager->AllCustomMetricsInfoGet();
    for my $Metric (@{ $Param{CustomMetrics} }) {
        $Metric->{Labels} = join ', ', @{ $Metric->{Labels} };
        $Metric->{Buckets} = join ', ', @{ $Metric->{Buckets} };
    }

    my $Output = $LayoutObject->Header();
    $Output .= $LayoutObject->NavigationBar();
    $Output .= $LayoutObject->Output(
        TemplateFile => 'AdminPrometheus',
        Data         => \%Param,
    );
    $Output .= $LayoutObject->Footer();

    return $Output;
}

1
