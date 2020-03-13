BEGIN; 

CREATE TABLE prometheus_metric_types (
    id        SMALLINT PRIMARY KEY GENERATED ALWAYS AS IDENTITY,
    type_name TEXT     NOT NULL UNIQUE
);

INSERT INTO prometheus_metric_types(type_name) VALUES
    ('counter'),('gauge'),('histogram'),('summary');


CREATE TABLE prometheus_metric_update_methods (
    id             SMALLINT PRIMARY KEY GENERATED ALWAYS AS IDENTITY,
    metric_type_id SMALLINT REFERENCES prometheus_metric_types(id),
    name           TEXT     NOT NULL
);

INSERT INTO prometheus_metric_update_methods(metric_type_id, name) VALUES
    (1, 'inc'),
    (2, 'inc'), (2, 'set'), (2, 'dec'),
    (3, 'observe'),
    (4, 'observe');

CREATE TABLE prometheus_custom_metrics (
    id BIGINT PRIMARY KEY GENERATED ALWAYS AS IDENTITY,
    namespace TEXT,
    name TEXT NOT NULL UNIQUE,
    help TEXT NOT NULL,
    metric_type_id SMALLINT REFERENCES prometheus_metric_types(id)
);

CREATE TABLE prometheus_custom_metric_labels (
    id BIGINT PRIMARY KEY GENERATED ALWAYS AS IDENTITY,
    name TEXT NOT NULL,
    custom_metric_id BIGINT REFERENCES prometheus_custom_metrics(id),
    queue_num INT NOT NULL
);

CREATE TABLE prometheus_custom_metric_buckets (
    id  BIGINT PRIMARY KEY GENERATED ALWAYS AS IDENTITY,
    custom_metric_id BIGINT REFERENCES prometheus_custom_metrics(id),
    value BIGINT NOT NULL
);

CREATE TABLE prometheus_custom_metric_sql (
    id BIGINT PRIMARY KEY GENERATED ALWAYS AS IDENTITY,
    query_text TEXT NOT NULL,
    custom_metric_id BIGINT REFERENCES prometheus_custom_metrics(id),
    update_method_id SMALLINT REFERENCES prometheus_metric_update_methods(id)
);

END;
