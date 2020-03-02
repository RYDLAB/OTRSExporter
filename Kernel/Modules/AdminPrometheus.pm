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

our $ObjectManagerDisabled = 1;

sub new {
    my ( $Type, %Param ) = @_;

    # allocate new hash for object
    my $Self = {%Param};
    bless( $Self, $Type );

    return $Self;
}

sub Run {
    my ( $Self, %Param ) = @_;

    my $ConfigObject = $Kernel::OM->Get('Kernel::Config');
    my $LayoutObject = $Kernel::OM->Get('Kernel::Output::HTML::Layout');

    if ( !$ConfigObject->Get('SecureMode') ) {
        return $LayoutObject->SecureMode();
    }

    $Param{MetricTypeStrg} = $LayoutObject->BuildSelection(
        Name  => 'MetricType',
        Data  => [qw( Counter Gauge Histogram Summary )],
        Class => 'Modernize',
    );

    my $ParamObject = $Kernel::OM->Get('Kernel::System::Web::Request');

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

        if (!%Errors) {
            my $MetricManager = $Kernel::OM->Get('Kernel::System::Prometheus::MetricManager');

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
