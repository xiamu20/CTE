# CTE

WITH RECURSIVE cte AS (
   initial_query    -- "seed" member
   UNION ALL
   recursive_query    -- recusive member that references to the same CTE name
)
SELECT * FROM cte;    -- main query


 WITH RECURSIVE reporting_chain(id, name, path, level) AS (
          SELECT id, 
          name, 
          CAST(name AS varchar), 
          1 level
          ,0 manager_id
          FROM orgchart
          WHERE manager_id IS NULL
          UNION ALL
          SELECT oc.id, 
          oc.name, 
          CONCAT(rc.path,' -> ',oc.name), 
          rc.level+1,oc.manager_id
          FROM reporting_chain rc 
          JOIN orgchart oc 
          ON rc.id=oc.manager_id)
       SELECT * FROM reporting_chain ORDER BY level;
