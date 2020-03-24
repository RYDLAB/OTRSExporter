BEGIN;

ALTER TABLE metric_types OWNER TO otrs;
ALTER TABLE metric_update_methods OWNER TO otrs;
ALTER TABLE custom_metrics OWNER TO otrs;
ALTER TABLE custom_metric_labels OWNER TO otrs;
ALTER TABLE custom_metric_buckets OWNER TO otrs;
ALTER TABLE custom_metric_sql OWNER TO otrs;

END;
