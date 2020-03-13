BEGIN;

ALTER TABLE prometheus_metric_types OWNER TO otrs;
ALTER TABLE prometheus_metric_update_methods OWNER TO otrs;
ALTER TABLE prometheus_custom_metrics OWNER TO otrs;
ALTER TABLE prometheus_custom_metric_labels OWNER TO otrs;
ALTER TABLE prometheus_custom_metric_buckets OWNER TO otrs;
ALTER TABLE prometheus_custom_metric_sql OWNER TO otrs;

END;
