select
  name,
  sql
from sqlite_schema
where type = 'table'
  and name = 'replace_me'
limit 1;
