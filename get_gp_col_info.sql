select
                x.table_name
        ||'|'|| x.column_id :: character varying
        ||'|'|| x.column_name
        ||'|'|| x.data_type_full
        ||'|'|| x.data_type_org
        ||'|'|| x.data_type_alias
        ||'|'|| x.data_length_full
        ||'|'|| x.data_length
        ||'|'|| case when x.data_scale = '' then '0' else x.data_scale end
        ||'|'|| case when x.data_type_org = 'numeric'                       then cast(cast(case when x.data_length = '' then '0' else x.data_length end as int) + 2 as text)
                     when x.data_type_org = 'timestamp without time zone'   then cast('23' as text) 
                                                                            else x.data_length 
                 end
        ||'|'|| x.pk_yn
        ||'|'|| x.null_yn
        ||'|'|| x.dk_yn as gp_col_info
  from  (
          select  
                  c.relname                                                     as table_name
                , row_number() over (partition by c.relname order by a.attnum)  as column_id
                , a.attname                                                     as column_name
                , pg_catalog.format_type(a.atttypid, a.atttypmod)               as data_type_full
                , split_part(pg_catalog.format_type(a.atttypid, a.atttypmod), '(', 1) as data_type_org
                , split_part(replace(replace(pg_catalog.format_type(a.atttypid, a.atttypmod), 'character varying', 'varchar'), 'timestamp without time zone', 'timestamp'), '(', 1) as data_type_alias
                , case when pg_catalog.format_type(a.atttypid, a.atttypmod) in ('timestamp without time zone', 'integer') then '' 
                       else '('|| split_part(pg_catalog.format_type(a.atttypid, a.atttypmod), '(', 2) 
                  end as data_length_full
                , split_part(replace(split_part(pg_catalog.format_type(a.atttypid, a.atttypmod), '(', 2), ')', ''), ',', 1) as data_length
                , split_part(replace(split_part(pg_catalog.format_type(a.atttypid, a.atttypmod), '(', 2), ')', ''), ',', 2) as data_scale
                , case when a.attnum = ANY(con.conkey) then 'Y' else 'N' end                                  as pk_yn
                , case when a.attnotnull or (t.typtype = 'd'::"char" and t.typnotnull) then 'N' else 'Y' end  as null_yn
                , case when d.attrnums is not null then 'Y' else 'N' end                                      as dk_yn
            from
                  pg_class      c
            join  pg_namespace  n on c.relnamespace = n.oid
            join  pg_attribute  a on c.oid = a.attrelid and a.attnum >= 0
            join  pg_type       t on a.atttypid = t.oid
            left  outer join pg_partition_rule      pr  on c.oid = pr.parchildrelid
            left  outer join gp_distribution_policy d   on c.oid = d.localoid and a.attnum = ANY (d.attrnums)
            left  outer join pg_constraint          con on c.oid = con.conrelid
           where
                  c.relkind   = 'r'
             and  pr.parchildrelid is null
             and  n.nspname   in ('edw_dda', 'edw_dw', 'edw_meta')
             and  ( con.contype = 'p' or con.contype is null)
        ) x
order by 
        x.table_name
      , x.column_id
