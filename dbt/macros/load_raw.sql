{% macro load_raw() %}
    {#-
      Loads staged source files into RAW with COPY INTO.
      * Target decides the environment: prod -> PROD_RAW, otherwise DEV_RAW.
      * Runs on RLI_LOAD_WH (load cost separate from transform cost), then
        switches back to the target warehouse.
      * Safe to re-run: Snowflake load history skips files already loaded.
      Usage: dbt run-operation load_raw [--target prod]
    -#}

    {%- set raw_db = 'PROD_RAW' if target.name == 'prod' else 'DEV_RAW' -%}
    {%- set schema = raw_db ~ '.INSURANCE' -%}
    {%- set stage  = '@' ~ schema ~ '.RAW_STAGE' -%}

    {%- set csv_loads = [
        {'table': 'CUSTOMERS', 'file': 'customers.csv',
         'cols': ['CUSTOMER_ID', 'CUSTOMER_NAME', 'STATE', 'INDUSTRY']},
        {'table': 'POLICIES',  'file': 'policies.csv',
         'cols': ['POLICY_ID', 'CUSTOMER_ID', 'POLICY_TYPE', 'EFFECTIVE_DATE', 'EXPIRATION_DATE', 'PREMIUM']},
        {'table': 'CLAIMS',    'file': 'claims.csv',
         'cols': ['CLAIM_ID', 'POLICY_ID', 'CLAIM_DATE', 'CLAIM_AMOUNT', 'CLAIM_STATUS']},
        {'table': 'PAYMENTS',  'file': 'payments.csv',
         'cols': ['PAYMENT_ID', 'POLICY_ID', 'PAYMENT_DATE', 'PAYMENT_AMOUNT']},
    ] -%}

    {{ log('Loading RAW into ' ~ schema ~ ' (target: ' ~ target.name ~ ')', info=True) }}
    {% do run_query('USE WAREHOUSE RLI_LOAD_WH') %}

    {#- ---------- CSV files ---------- -#}
    {% for load in csv_loads %}
        {%- set positional = [] -%}
        {%- for i in range(1, load.cols | length + 1) -%}
            {%- do positional.append('$' ~ i) -%}
        {%- endfor -%}

        {% set sql %}
            COPY INTO {{ schema }}.{{ load.table }}
                ({{ load.cols | join(', ') }}, _FILE_NAME, _FILE_ROW_NUMBER)
            FROM (
                SELECT {{ positional | join(', ') }}, METADATA$FILENAME, METADATA$FILE_ROW_NUMBER
                FROM {{ stage }}
            )
            FILES       = ('{{ load.file }}')
            FILE_FORMAT = (FORMAT_NAME = '{{ schema }}.FF_CSV')
            ON_ERROR    = ABORT_STATEMENT
        {% endset %}

        {% set result = run_query(sql) %}
        {% for row in result.rows %}
            {{ log(load.table ~ ': ' ~ (row.values() | join(' | ')), info=True) }}
        {% endfor %}
    {% endfor %}

    {#- ---------- JSON file ---------- -#}
    {% set json_sql %}
        COPY INTO {{ schema }}.ENDORSEMENTS (RAW_DATA, _FILE_NAME, _FILE_ROW_NUMBER)
        FROM (
            SELECT $1, METADATA$FILENAME, METADATA$FILE_ROW_NUMBER
            FROM {{ stage }}
        )
        FILES       = ('endorsements.json')
        FILE_FORMAT = (FORMAT_NAME = '{{ schema }}.FF_JSON')
        ON_ERROR    = ABORT_STATEMENT
    {% endset %}

    {% set result = run_query(json_sql) %}
    {% for row in result.rows %}
        {{ log('ENDORSEMENTS: ' ~ (row.values() | join(' | ')), info=True) }}
    {% endfor %}

    {% do run_query('USE WAREHOUSE ' ~ target.warehouse) %}
    {{ log('RAW load complete.', info=True) }}
{% endmacro %}
