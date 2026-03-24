select
  type,
  name,
  tbl_name,
  sql
from sqlite_schema
where type in ('table', 'view', 'index')
  and name not like 'sqlite_%'
order by type, name
limit 200;
