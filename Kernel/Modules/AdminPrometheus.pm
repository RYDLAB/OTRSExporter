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

sub Run {
    my ( $Self, %Param ) = @_;

    my $ConfigObject = $Kernel::OM->Get('Kernel::Config');
    my $LayoutObject = $Kernel::OM->Get('Kernel::Output::HTML::Layout');
    my $ParamObject = $Kernel::OM->Get('Kernel::System::Web::Request');
    my $MetricManager = $Kernel::OM->Get('Kernel::System::Prometheus::MetricManager');

    if ( !$ConfigObject->Get('SecureMode') ) {
        return $LayoutObject->SecureMode();
    }

    if ( !$Kernel::OM->Get('Kernel::System::Prometheus')->IsAllCustomMetricsCreated ) {
        $Param{NotifyMessage} = 'Not all custom metrics are deployed! Please deploy them';
    }
 
    if( $Self->{Subaction} eq 'CreateMetric' ) {
        my $Output = $Self->_RenderCreateCustomMetricPage(%Param);

        return $Output;
    }

    elsif ( $Self->{Subaction} eq 'CreateMetricAction' ) {
        my %Errors;

        $LayoutObject->ChallengeTokenCheck();

        # get params
        for my $Parameter (
            qw( MetricNamespace MetricName MetricHelp MetricType
                MetricBuckets SQL UpdateMethod )
            )
        {
            $Param{$Parameter} = $ParamObject->GetParam( Param => $Parameter ) || '';
        }

        # Check required params
        for my $Parameter (qw( MetricName MetricHelp MetricType SQL UpdateMethod )) {
            if (!$Param{$Parameter}) {
                $Errors{ErrorMessage} = 'One or more required fields are empty!';
                last;
            }
        }

        if( uc($Param{SQL}) !~ m{ \A \s* (?:SELECT|SHOW|DESC) }smx ) {
            $Param{SQLErrorMessage} = 'Only SELECT statements are available here!';
            $Errors{ErrorMessage} = 'Only SELECT statements are available here!';
        }

        $Param{MetricLabels} = $MetricManager->GetLabelsFromSQL( SQL => $Param{SQL} );

        if (!%Errors) {
            my $TestMetricSuccess = $MetricManager->TryMetric(%Param);

            if ($TestMetricSuccess) {
                my $CreateMetricSuccess = $MetricManager->NewCustomMetric(%Param);

                if ($CreateMetricSuccess) {
                    $Param{NotifyMessage} = "Metric $Param{MetricName} successfully created!";

                    my $Output = $Self->_RenderCustomMetricsListPage(%Param);

                    return $Output;
                }

                $Errors{ErrorMessage} = $Kernel::OM->Get('Kernel::System::Log')->GetLogEntry(
                    Type     => 'Error',
                    What     => 'Message',
                );
            }

            else {
                $Errors{ErrorMessage} = $Kernel::OM->Get('Kernel::System::Log')->GetLogEntry(
                    Type => 'Error',
                    What => 'Message',
                );
            }
        }

        # Print page with errors info
        $Param{NotifyMessage} = $Errors{ErrorMessage};
        $Param{NotifyPriority} = 'Error';

        my $Output = $Self->_RenderCreateCustomMetricPage(%Param);

        return $Output;
    }
    
    elsif ( $Self->{Subaction} eq 'ChangeMetric' ) {
        $Param{MetricID} = $ParamObject->GetParam( Param => 'ID' );

        my $MetricInfo = $MetricManager->CustomMetricGet( MetricID => $Param{MetricID} );
        $Param{MetricNamespace} = $MetricInfo->{Namespace};
        $Param{MetricName} = $MetricInfo->{Name};
        $Param{MetricHelp} = $MetricInfo->{Help};
        $Param{SQL} = $MetricInfo->{SQL};
        $Param{MetricLabels} = join ' ', @{ $MetricInfo->{Labels} };
        $Param{MetricBuckets} = join ' ', @{ $MetricInfo->{Buckets} };

        my $Output = $Self->_RenderChangeCustomMetricPage(%Param);

        return $Output;
    }

    elsif ( $Self->{Subaction} eq 'ChangeMetricAction' ) {
        my %Errors;

        $LayoutObject->ChallengeTokenCheck();

        # get params
        for my $Parameter (
            qw( MetricID MetricNamespace MetricName MetricHelp MetricType
                MetricBuckets SQL UpdateMethod )
            )
        {
            $Param{$Parameter} = $ParamObject->GetParam( Param => $Parameter ) || '';
        }

        # Check required params
        for my $Parameter (qw( MetricName MetricHelp MetricType SQL UpdateMethod )) {
            if (!$Param{$Parameter}) {
                $Errors{ErrorMessage} = 'One or more required fields are empty!';
                last;
            }
        }

        if( uc($Param{SQL}) !~ m{ \A \s* (?:SELECT|SHOW|DESC) }smx ) {
            $Param{SQLErrorMessage} = 'Only SELECT statements are available here!';
            $Errors{ErrorMessage} = 'Only SELECT statements are available here!';
        }

        $Param{MetricLabels} = $MetricManager->GetLabelsFromSQL( SQL => $Param{SQL} );

        if ( !%Errors ) {
            my $TestMetricSuccess = $MetricManager->TryMetric(%Param);

            if ($TestMetricSuccess) {
                my $UpdateMetricSuccess = $MetricManager->UpdateCustomMetricAllProps(%Param);

                if ($UpdateMetricSuccess) {
                    $Param{NotifyMessage} = 'Metric Successfully changed!';

                    my $Output = $Self->_RenderCustomMetricsListPage(%Param);

                    return $Output;
                }

                $Errors{ErrorMessage} = $Kernel::OM->Get('Kernel::System::Log')->GetLogEntry(
                    Type => 'Error',
                    What => 'Message',
                );
            }

            else {
                $Errors{ErrorMessage} = $Kernel::OM->Get('Kernel::System::Log')->GetLogEntry(
                    Type => 'Error',
                    What => 'Message',
                );
            }
        }

        # Print page with errors info
        $Param{NotifyMessage} = $Errors{ErrorMessage};
        $Param{NotifyPriority} = 'Error';

        my $Output = $Self->_RenderChangeCustomMetricPage(%Param);

        return $Output;
    }

    elsif ( $Self->{Subaction} eq 'DeleteAction' ) { 
        $Param{MetricID} = $ParamObject->GetParam( Param => 'MetricID' );
        
        my $DeleteMetricSuccess = $MetricManager->DeleteMetric( MetricID => $Param{MetricID} );
 
        if ( $DeleteMetricSuccess ) {
            $Param{NotifyMessage} = 'Metric successfully deleted!';

            my $Output = $Self->_RenderCustomMetricsListPage(%Param);

            return $Output;
        }

        my $ErrorMessage = $Kernel::OM->Get('Kernel::System::Log')->GetLogEntry(
            Type => 'Error',
            What => 'Message',
        );

        $Param{NotifyMessage} = "An error has occured while deleting metric: $ErrorMessage";
        $Param{NotifyPriority} = 'error';

        my $Output = $Self->_RenderCustomMetricListPage(%Param);

        return $Output
    }

    elsif ( $Self->{Subaction} eq 'DeployMetrics' ) {
        my $MergeSuccess = $Kernel::OM->Get('Kernel::System::Prometheus')->MergeCustomMetrics;

        if ($MergeSuccess) {
            $Param{NotifyMessage} = 'Metrics successfully deployed!';

            my $Output = $Self->_RenderCustomMetricsListPage( NotifyMessage => $Param{NotifyMessage} );

            return $Output;
        }

        my $ErrorMessage = $Kernel::OM->Get('Kernel::System::Log')->GetLogEntry(
            Type => 'Error',
            What => 'Message',
        );

        $Param{NotifyMessage} = "An error has occured while deploying metric: $ErrorMessage";
        $Param{NotifyPriority} = 'error';

        my $Output = $Self->_RenderCustomMetricsListPage(%Param);

        return $Output;
    }

    elsif ( $Self->{Subaction} eq 'ClearMemory' ) {
        my $ClearSuccess = $Kernel::OM->Get('Kernel::System::Prometheus')->ClearMemory;

        if ($ClearSuccess) {
            $Param{NotifyMessage} = 'Shared memory successfully cleared';

            my $Output = $Self->_RenderCustomMetricsListPage(NotifyMessage => $Param{NotifyMessage});

            return $Output;
        }

        my $ErrorMessage = $Kernel::OM->Get('Kernel::System::Log')->GetLogEntry(
            Type => 'Error',
            What => 'Message',
        );

        $Param{NotifyMessage} = "An error has occured while clearing shared memory: $ErrorMessage";
        $Param{NotifyPriority} = 'error';

        my $Output = $Self->_RenderCustomMetricsListPage(%Param);
        
        return $Output;
    }

    my $Output = $Self->_RenderCustomMetricsListPage( NotifyMessage => $Param{NotifyMessage} );

    return $Output;
}

sub _RenderCustomMetricsListPage {
    my ( $Self, %Param ) = @_;

    # get custom metrics list
    $Param{CustomMetrics} = $Kernel::OM->Get('Kernel::System::Prometheus::MetricManager')->AllCustomMetricsInfoGet();
    
    # make labels and buckets string
    for my $Metric (@{ $Param{CustomMetrics} }) {
        $Metric->{Labels} = join ' ', @{ $Metric->{Labels} };
        $Metric->{Buckets} = join ' ', @{ $Metric->{Buckets} };
    }

    my $LayoutObject = $Kernel::OM->Get('Kernel::Output::HTML::Layout');

    my $Output = $LayoutObject->Header();
    $Output .= $LayoutObject->NavigationBar();
    if ( $Param{NotifyMessage} ) {
        $Output .= $LayoutObject->Notify(
            Priority => $Param{NotifyPriority},
            Info     => $Param{NotifyMessage},
        );
    }
    $Output .= $LayoutObject->Output(
        TemplateFile => 'AdminPrometheus',
        Data         => \%Param,
    );
    $Output .= $LayoutObject->Footer();

    return $Output;
}

sub _RenderChangeCustomMetricPage {
    my ( $Self, %Param ) = @_;

    my $LayoutObject = $Kernel::OM->Get('Kernel::Output::HTML::Layout');

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

    my $Output = $LayoutObject->Header();
    $Output .= $LayoutObject->NavigationBar;
    if ($Param{NotifyMessage}) {
        $Output .= $LayoutObject->Notify(
            Priority => $Param{NotifyPriority},
            Info     => $Param{NotifyMessage},
        );
    }
    $Output .= $LayoutObject->Output(
        TemplateFile => 'AdminPrometheusChangeMetric',
        Data     => \%Param,
    );

    $Output .= $LayoutObject->Footer();

    return $Output;
}

sub _RenderCreateCustomMetricPage {
    my ( $Self, %Param ) = @_;
    
    my $LayoutObject = $Kernel::OM->Get('Kernel::Output::HTML::Layout');

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

    my $Output = $LayoutObject->Header();
    $Output .= $LayoutObject->NavigationBar;
    if ($Param{NotifyMessage}) {
        $Output .= $LayoutObject->Notify(
            Priority => $Param{NotifyPriority},
            Info     => $Param{NotifyMessage}, 
        ) 
    }
    $Output .= $LayoutObject->Output(
        TemplateFile => 'AdminPrometheusCreateMetric',
        Data     => \%Param,
    );
    $Output .= $LayoutObject->Footer;

    return $Output;
}

1
