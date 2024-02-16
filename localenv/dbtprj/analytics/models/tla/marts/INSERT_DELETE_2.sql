{{ config(
    materialized='incremental',
    incremental_strategy = 'merge',
    partition_by={
        "field": "ts_create_utc",
        "data_type": "timestamp",
        "granularity": "hour"
    },
    cluster_by = ['dt_create_utc'],
    incremental_predicates = ["DBT_INTERNAL_DEST.dt_create_utc >= DATE_SUB('2024-01-02', INTERVAL 1 DAY)"],
    post_hook = [
        "delete from {{ this }} where dt_create_utc = '2024-01-01'"
    ]
    )
}}

select
 *
from
    {{ source('TLA__TRVANALYT_RAW', 'TLA__CRYPTO_CANDLES_MINUTE_2') }}
