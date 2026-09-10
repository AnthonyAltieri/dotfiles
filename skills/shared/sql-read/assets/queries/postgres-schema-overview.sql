select
  table_schema,
  table_name,
  table_type
from information_schema.tables
where table_schema not in ('pg_catalog', 'information_schema')
order by table_schema, table_name
limit 200;
