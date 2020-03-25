# OTRS exporter

## Description

OTRS exporter - is OTRS module for monitoring system 'Prometheus'. With this module
you can track your system activity and OTRS performance.

The following metrics are now available:

*  web
    *  http_request_duration_seconds{host, worker, method, route}
    *  http_response_size_bytes{host, worker}
    *  http_requests_total{host, worker}
*  otrs
    *  otrs_income_mail_total{host}
    *  otrs_outgoing_mail_total{host}
    *  otrs_ticket_total{host, queue, status}
    *  otrs_article_total{host, queue, status}
    *  otrs_logs_total{host, priority, prefix, module}
    *  cache_operations{host, operation}
    *  daemon_subworkers_total{host, task_handler_module, task_name}
    *  daemon_subworkers_task_last_execution_time{host, task_handler_module, task_name}
    *  recurrent_task_success{host, name}
    *  recurrent_task_duration{host, name}
*  system
    *  http_process_resident_memory_bytes{host, level, worker}
    *  http_prcoess_virtual_memory_bytes{host, level, worker}
    *  http_process_cpu_seconds_total{host, level, worker}
    *  http_process_cpu_system_seconds_total{host, level, worker}
    *  http_process_cpu_user_seconds_total{host, level, worker}
    *  http_process_max_fds{host, level, worker}
    *  daemon_process_resident_memory_bytes{host, worker, name}
    *  daemon_prcoess_virtual_memory_bytes{host, worker, name}
    *  daemon_process_cpu_seconds_total{host, worker, name}
    *  daemon_process_cpu_system_seconds_total{host, worker, name}
    *  daemon_process_cpu_user_seconds_total{host, worker, name}
    *  daemon_process_max_fds{host, worker, name}

OTRS Exporter supports creating for custom metrics which can update via database.
To manage custom metrics in OTRS was created a web-page.

## Installation

### Creating OPM file

If you don't have an .opm file you should create him.

`/opt/otrs/bin/otrs.Console.pl Dev::Package::Build --module-directory /path/to/exporter/directory /path/to/otrs-exporter.somp ./`

### Installing package
Before installing you should install following packages from cpan:
*  Net::Prometheus
*  Time::HiRes
*  List::Util 
*  Scalar::Util
*  Proc::ProcessTable
*  Proc::Exists
*  IPC::ShareLite
*  Sereal

Installation for cpan-packages using cpanminus:
`sudo cpanm Net::Prometheus Time::HiRes List::Util Scalar::Util Proc::ProcessTable Proc::Exists IPC::ShareLite Sereal`

To install package you can use web-interface.
Go to http://localhost/otrs/index.pl?Action=AdminPackageManager or to another url for AdminPackageManger in your OTRS.
In block 'actions' load OTRS-Exporter.opm file and then click 'Install package'. Follow instructions.

### System configuration

After installing OPM package, we should set few options in OTRS system configuration.
Go to OTRS system configuration page (http://localhost/otrs/index.pl?Action=AdminSystemConfiguration).
In search box enter 'Prometheus::Settings'. Set the value of ServerCMND to yours. This value you can find using ps command. ServerCMND is name of your main http process.

Also you can set the 'Guard' option to choose, which object will used to save metrics. Guard::Cache usually used for distributed OTRS-system (more than 1 machine/virtual-machine) but it is 
as a rule slower, than Guard::SHM. Guard::SHM using shared memory, so your operating system must support SysV IPC (shared memory and semaphores).

### Creating Web-service for Prometheus

Now it's time to create new web service in OTRS for Prometheus monitoring system.
Go to http://localhost/otrs/index.pl?Action=AdminGenericInterfaceWebservice and add new web service.
Enter some name('Prometheus' for example), and in block OTRS as provider as network transport choose HTTP::SendText. Save web-service.
Now add new operation for Prometheus::MetricGet. Insert name, save and finish. Then configure network transport: for created operation add route by which prometheus will come. Save
and finish.

The URL with metrics will looks like this: http://host/otrs/nph-genericinterface.pl/Webservice/$WebserviceName/$OperationRoute.

## Uninstall module

### Warning!

After uninstalling you should restart your web-server

### Uninstall package

Go to your package manager (http://localhost/otrs/index.pl?Action=AdminPackageManager). In table find OTRS exporter and press on "uninstall" option.
Wait while OTRS uninstalling package. Restart your web-server

If you want to delete early created web-service, go to your web-service manager (http://localhost/otrs/index.pl?Action=AdminGenericInterfaceWebservice),
find your created web-service and click on his name. Then at the block 'Actions' click on 'Delete web-service' button'.

## Custom metrics

### Add new metric

Before creating new metrics, please, read Prometheus documetation about metrics https://prometheus.io/docs/concepts/metric_types/

After installing OTRS Exporter you can find item for managing custom metrics at Admin page.
If you want to add new metric go to http://localhost/otrs/index.pl?Action=AdminPrometheus and click 'Add new metric'.
Fill in required fields. At Cron SQL specify SQL-query by which the metric will be updated. Remember, that
last column is always value to update metric. All columns before is labels for metric and they will named automatically.

### Change metric

To change metric you can go to http://localhost/otrs/index.pl?Action=AdminPrometheus and click at name of metric to change.
You also can delete this metric using actions block and changing-page

### Deploy metrics

After creating new metric you should deploy all new metrics. You can do this using action 'Deploy metric'. If you dont,
the new metric will not appear at web-service operation page.

### Clear shared memory

You can clear shared memory to reset all metrics. Be careful, because metrics about daemon processes will be able to update only after
otrs.Daemon restart

## Console commands

There are several new console commands:

*  `Maint::Prometheus::ClearMemory`                 - Same as clear shared memory at custom-metrics-web-page
*  `Maint::Prometheus::DeleteDiedProcessCollectors` - Delete collectors for died processes
*  `Maint::Prometheus::DeleteValuesWithDiedPIDs`    - Delete the metric values with died workers as label
*  `Maint::Prometheus::MergeCustomMetrics`          - Merge custom metrics to shared memory (same as deploy)


# Prometheus

## Configuration

Download prometheus at https://prometheus.io/download/ if you didnt.

This example configuration for job is very simple:


```
scrape_configs:
  - job_name: 'otrs'

    metrics_path: '/otrs/nph-genericinterface.pl/Webservice/Prometheus/metrics'

    static_configs:
    - targets: ['localhost:80']
```


As metric path you should speciify the route to our operation.
As target you should specify host for otrs

## Basic auth

In your web-server for OTRS you can specify auth for metrics route using documetation for your server.

If you did it, you can add to Prometheus configuration file option for basic auth:

```
basic_auth:
  [ username: <string> ]
  [ password: <secret> ]
  [ password_file: <string> ]
```


## Grafana dashboards

With package were installed example dasbhoards for grafana to $OTRS_HOME/doc/GrafanaExamples/

You can import them to your grafana-server
