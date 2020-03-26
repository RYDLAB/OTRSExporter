# --
# This software comes with ABSOLUTELY NO WARRANTY. For details, see
# the enclosed file COPYING for license information (GPL). If you
# did not receive this file, see https://www.gnu.org/licenses/gpl-3.0.txt.
# --

package Kernel::Language::ru_AdminPrometheus;

use strict;
use warnings;
use utf8;

=head1 NAME

    Kernel::Language::ru_AdminPrometheus

=head2 DESCRIPTION

    Russian language module for Prometheus frontend-module (AdminPrometheus)

=cut

sub Data {
    my $Self = shift;

    # $$START$$
    # possible charsets
    $Self->{Translation}{'Custom metrics'} = 'Пользовательские метрики';
    $Self->{Translation}{'Manage prometheuses custom metrics'} =  'Управление метриками для Prometheus';
    $Self->{Translation}{'Filter for metrics'} = 'Фильтр для метрик';
    $Self->{Translation}{'Add new metric'} = 'Добавить новую метрику';
    $Self->{Translation}{'Deploy metrics'} = 'Разместить метрики';
    $Self->{Translation}{'Clear memory'} = 'Очистить память';
    $Self->{Translation}{'Memory successfully cleared'} = 'Память успешно очищена';
    $Self->{Translation}{'Labels'} = 'Подписи';
    $Self->{Translation}{'Buckets'} = 'Ведра';
    $Self->{Translation}{'Here you can see table with created custom metrics. Also you can edit them or create new'}
    = 'Здесь вы можете увидеть таблицу с уже созданными метриками.
    Так же вы можете изменить их или создать новую
    ';
    $Self->{Translation}{'Here you can create new custom metrics for Prometheus.'} = 'Здесь вы можете создать новые пользовательские метрики для Prometheus';
    $Self->{Translation}{'To let your metric to be updated automatically through the database, you can specify the SQL-query and update method according to the following pattern:'}
    = 'Чтобы ваша метрика обновлялась автоматически через базу данных, вы можете указать SQL-запрос и метод обновления в соответствии со следующими шаблоном:';
    $Self->{Translation}{'Where label1 .. labelN are labels in your metric and update_value is value to update metric'} = 'Где label1 .. labelN это подписи к вашей метрике, а update_value это значение на которое нужно обновить метрику';
    $Self->{Translation}{'You can check your SQL query in '} = 'Вы можете проверить ваш SQL-запрос в ';
    $Self->{Translation}{'Metric type'} = 'Тип метрики';
    $Self->{Translation}{'Buckets for histogramm or summary, separated by space. For example: 0.1 0.5 1 2 5 10 100'} = 'Ведра для метрик типа histogram или summary, разделенные пробелом. Например: 0.1 0.5 1 2 5 10 100';
    $Self->{Translation}{'Cron SQL'} = 'Крон-SQL';
    $Self->{Translation}{'Metric will updating via database using this SQL query. The last column is always value to update. Other columns are labels and they will takes automatically'}
    = 'Метрика будет обновляться через базу данных, используя этот SQL-запрос. Последняя колнока - это всегда значение, на которое обновлять. Остальные колонки - это подписи и они будут взяты автоматически';
    $Self->{Translation}{'Method to be used for update'} = 'Метод, используя который будем обновляться метрика';
    $Self->{Translation}{'inc - increment, dec -decrement, set - set value, observe - observe using buckets'} = 'inc - увеличение, dec - уменьшение,  set - установить значение, observe - обзор значение с использованием ведер';
    $Self->{Translation}{'Update method'} = 'Метод';
    $Self->{Translation}{'inc - increment, dec -decrement, set - set value, observe - observe using buckets'} = 'inc - увеличение, dec - уменьшение,  set - установить значение, observe - обзор значение с использованием ведер';
    $Self->{Translation}{'Create metric'} = 'Создать метрику';
    $Self->{Translation}{'Creating form'} = 'Форма создания';
    $Self->{Translation}{'Prefix for metric like here: \'namespace_name{labels} value\''} = 'Префикс для метрик, как тут: \'префикс_название{подписи} значение';
    $Self->{Translation}{'Description for metric'} = 'Описание метрики';
    $Self->{Translation}{'Metric with this name already exists!'} = 'Метрика с таким именем уже существует';
    $Self->{Translation}{'Here you can change custom metrics for Prometheus.'} = 'Здесь вы можете изменить метрику для Prometheus';
    $Self->{Translation}{'Change metric'} = 'Изменить метрику';
    $Self->{Translation}{'Change custom metric'} = 'Изменить пользовательскую метрику';
    $Self->{Translation}{'Delete metric'} = 'Удалить метрику';
    $Self->{Translation}{'Metric successfully deleted!'} = 'Метрика успешно удалена!';
    $Self->{Translation}{'Metrics successfully deployed!'} = 'Метрики успешно размещены!';
    $Self->{Translation}{'Method'} = 'Метод';
    $Self->{Translation}{'Only SELECT statements are available here!'} = 'Здесь доступны только SELECT запросы!';
    $Self->{Translation}{'Something wrong with metric type'} = 'Что-то не так с типом метрики';
    $Self->{Translation}{'Settings for OTRS exporter'} = 'Настройки для модуля OTRS exporter';
    $Self->{Translation}{'Update default metrics from database'} = 'Обновление стандартных метрик из базы данных';
    $Self->{Translation}{'Update custom metrics from database'} = 'Обновление пользовательских метрик из базы данных';
    $Self->{Translation}{'Delete process collectors for died processes.'} = 'Удалить процесс-сборщиков для умерших процессов';
    $Self->{Translation}{'Delete values with died workers as label'} = 'Удалить значения метрик с идентификаторами умерших процессов в качестве подписей';
    $Self->{Translation}{'Not all custom metrics are deployed! Please deploy them'} = 'Не все пользовательские метрики размещены! Разместите их';

    # $$STOP$$
    return;
}

1;
