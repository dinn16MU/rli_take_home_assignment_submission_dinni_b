{% macro generate_schema_name(custom_schema_name, node) -%}
    {#-
      Dev and prod use identical schema names (STAGING, MARTS, DQ, SEMANTIC).
      The target's database decides the environment: DEV_ANALYTICS or PROD_ANALYTICS.
      Overrides dbt's default, which would prefix names (e.g. STAGING_MARTS).
    -#}
    {%- if custom_schema_name is none -%}
        {{ target.schema }}
    {%- else -%}
        {{ custom_schema_name | trim | upper }}
    {%- endif -%}
{%- endmacro %}
