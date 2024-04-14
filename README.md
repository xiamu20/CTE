# CTE

WITH RECURSIVE cte AS (
   initial_query    -- "seed" member
   UNION ALL
   recursive_query    -- recusive member that references to the same CTE name
)
SELECT * FROM cte;    -- main query
