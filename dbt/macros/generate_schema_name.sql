{#- The custom schema name is the namespace as it is: tpch_staging, not
    <target schema>_tpch_staging (spec 2026-10-30-dbt-elt, section 6.5). -#}
{% macro generate_schema_name(custom_schema_name, node) -%}
  {%- if custom_schema_name is none -%}
    {{ target.schema }}
  {%- else -%}
    {{ custom_schema_name | trim }}
  {%- endif -%}
{%- endmacro %}
