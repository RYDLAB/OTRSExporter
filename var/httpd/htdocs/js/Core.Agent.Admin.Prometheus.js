// --
// Copyright (C) 2001-2020 OTRS AG, https://otrs.com/
// --
// This software comes with ABSOLUTELY NO WARRANTY. For details, see
// the enclosed file COPYING for license information (GPL). If you
// did not receive this file, see https://www.gnu.org/licenses/gpl-3.0.txt.
// --

"use strict";

var Core = Core || {};
Core.Agent = Core.Agent || {};
Core.Agent.Admin = Core.Agent.Admin || {};

/**
 * @namespace Core.Agent.Admin.Prometheus
 * @memberof Core.Agent.Admin
 * @author OTRS AG
 * @description
 *      This namespace contains the special module function for AdminPrometheus.
 */
 Core.Agent.Admin.Prometheus = (function (TargetNS) {

    /*
    * @name Init
    * @memberof Core.Agent.Admin.Prometheus
    * @function
    * @description
    *      This function initializes the module functionality.
    */
    function UpdateMetricTypeConformity() {
        var ValueSelected = $('select#MetricType').val();
        $('select#UpdateMethod').empty();
        switch (ValueSelected) {
            case 'counter':
                $('select#UpdateMethod').append($('<option value="inc">inc</option>'))
                $('#MetricBuckets').prop('disabled', true);
                break;
            case 'gauge':
                $('select#UpdateMethod').append($('<option value="set">set</option>'))
                $('select#UpdateMethod').append($('<option value="dec">dec</option>'))
                $('select#UpdateMethod').append($('<option value="inc">inc</option>'))
                $('#MetricBuckets').prop('disabled', true);
                break;
            case 'histogram':
                $('select#UpdateMethod').append($('<option value="observe">observe</option>'))
                $('#MetricBuckets').prop('disabled', false);
                break;
            case 'summary':
                $('select#UpdateMethod').append($('<option value="observe">observe</option>'))
                $('#MetricBuckets').prop('disabled', false);
                break;
        }

        return 1;
    }

    TargetNS.Init = function () {
        Core.UI.Table.InitTableFilter($('#FilterResults'), $('#CustomMetrics'));
        if ( $('select#MetricType').length ) { UpdateMetricTypeConformity() }
    };

    $('select#MetricType').on('change', UpdateMetricTypeConformity);
    Core.Init.RegisterNamespace(TargetNS, 'APP_MODULE');

    return TargetNS;
}(Core.Agent.Admin.Prometheus || {}));
