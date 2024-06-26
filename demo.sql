MySQL 8.0 (或pgsql hive 等) CTE 递归查询
MySQL 8.0 引入CTE(Common Table Expression)功能，CTE除了替代派生表以外，还有一个重要的功能，实现递归查询。在CTE功能引入之前，MySQL很难在SQL语句层实现递归查询，一种间接的方式是通过创建存储过程，而引入CTE后，SQL语句级的递归查询将变得很容易，本文将简单介绍CTE递归查询的使用。

一、什么是CTE递归查询？

CTE递归查询可以看作是一个子查询在重复调用自己，它的使用场景如下：
生成序列
遍历层次或树形结构

CTE递归语法：
WITH RECURSIVE cte AS (
   initial_query    -- "seed" member
   UNION ALL
   recursive_query    -- recusive member that references to the same CTE name
)
SELECT * FROM cte;    -- main query

上述CTE递归语法中，RECURSIVE关键字是必不可少的，除此之外，还有两个必不可少的成员，一个是seed member，种子成员，它是一个初始化的查询，将在第一次迭代时被执行。另外一个是recusive member，递归成员，它是递归迭代的主要过程，它将会在主查询中生成所有后续的item。

整个递归过程在任何一次迭代不再返回记录时结束，这里要注意，避免由于迭代次数过多，导致内存耗尽。为递归成员设置一个结束条件是非常重要的，当然也可以通过设置递归深度、最大执行时间来限制递归执行，以便在超过限制时，能够强制结束递归CTE。

cte_max_recursion_depth 参数默认值为1000，限制CTE递归深度，超过阈值，将被强制终止。
max_execution_time 参数限制查询的最大执行时间，超过该时间，也将被强制终止。


二、CTE递归的简单使用案例

2.1 单层次的序列

目标：创建一个1到10的整数序列，如下：
WITH RECURSIVE natural_sequence AS
  ( SELECT 1 AS n       -- seed member: our sequence starts from 1
    UNION ALL
    SELECT n + 1 FROM natural_sequence    -- recursive member: reference to itself
    WHERE n < 10                          -- stop condition
  )
SELECT * FROM natural_sequence;           -- main query
+------+
| n    |
+------+
|    1 |
|    2 |
|    3 |
|    4 |
|    5 |
|    6 |
|    7 |
|    8 |
|    9 |
|   10 |
+------+

如果不加结束条件，由于递归深度超过1000，被强制终止，如下：

mysql> WITH RECURSIVE natural_sequence AS ( SELECT 1 AS n   UNION ALL SELECT n + 1 FROM natural_sequence   ) SELECT * FROM natural_sequence;
ERROR 3636 (HY000): Recursive query aborted after 1001 iterations. Try increasing @@cte_max_recursion_depth to a larger value.

另外一个阶乘的例子，如下：
mysql> WITH RECURSIVE factorial(n, fact) AS (
          SELECT 0, 1
          UNION ALL  
          SELECT n + 1, fact * (n+1)  
          FROM factorial
          WHERE n < 20 )
       SELECT * from factorial;
+------+---------------------+
| n    | fact                |
+------+---------------------+
|    0 |                   1 |
|    1 |                   1 |
|    2 |                   2 |
|    3 |                   6 |
|    4 |                  24 |
|    5 |                 120 |
|    6 |                 720 |
|    7 |                5040 |
|    8 |               40320 |
|    9 |              362880 |
|   10 |             3628800 |
|   11 |            39916800 |
|   12 |           479001600 |
|   13 |          6227020800 |
|   14 |         87178291200 |
|   15 |       1307674368000 |
|   16 |      20922789888000 |
|   17 |     355687428096000 |
|   18 |    6402373705728000 |
|   19 |  121645100408832000 |
|   20 | 2432902008176640000 |
+------+---------------------+

2.2 双层次的序列

实现一种序列，N+2的值由前两个值N+1与N计算而来，最典型的例子就是斐波那契数列，最开始的两个数是0，1，后面的数都是前两个数之和。使用递归CTE实现，如下：
mysql> WITH RECURSIVE fibonacci (n, fib_n, next_fib_n) AS (   
          SELECT 1, 0, 1   
          UNION ALL   
          SELECT n + 1, next_fib_n, fib_n + next_fib_n     
          FROM fibonacci
          WHERE n < 20 )
       SELECT * FROM fibonacci;
+------+-------+------------+
| n    | fib_n | next_fib_n |
+------+-------+------------+
|    1 |     0 |          1 |
|    2 |     1 |          1 |
|    3 |     1 |          2 |
|    4 |     2 |          3 |
|    5 |     3 |          5 |
|    6 |     5 |          8 |
|    7 |     8 |         13 |
|    8 |    13 |         21 |
|    9 |    21 |         34 |
|   10 |    34 |         55 |
|   11 |    55 |         89 |
|   12 |    89 |        144 |
|   13 |   144 |        233 |
|   14 |   233 |        377 |
|   15 |   377 |        610 |
|   16 |   610 |        987 |
|   17 |   987 |       1597 |
|   18 |  1597 |       2584 |
|   19 |  2584 |       4181 |
|   20 |  4181 |       6765 |
+------+-------+------------+


另外一个例子，日期序列。有一个需求，需要按天分组，查询每天的销售总额，传统查询方法，使用group by，如下：
SELECT order_date, SUM(price) AS sales
FROM sales
GROUP BY order_date;
+------------+---------+
| order_date | sales   |
+------------+---------+
| 2020-02-01 |  500.49 |
| 2020-02-02 | 1249.00 |
| 2020-02-04 | 1199.00 |
| 2020-02-06 | 1319.40 |
| 2020-02-07 |  609.00 |
+------------+---------+

这个方式有一个问题，假如有一天没有卖出商品，那么那天的记录就没有，比如上面2020-02-03，2020-02-05这两天就没有数据。

使用递归CTE，就不会有这个问题，如下：
WITH RECURSIVE dates(date) AS (
   SELECT '2020-02-01'
   UNION ALL
   SELECT date + INTERVAL 1 DAY
   FROM dates
   WHERE date < '2020-02-07' )
SELECT dates.date, COALESCE(SUM(price), 0) sales
FROM dates LEFT JOIN sales ON dates.date = sales.order_date
GROUP BY dates.date;
+------------+---------+
| date       | sales   |
+------------+---------+
| 2020-02-01 |  500.49 |
| 2020-02-02 | 1249.00 |
| 2020-02-03 |    0.00 |
| 2020-02-04 | 1199.00 |
| 2020-02-05 |    0.00 |
| 2020-02-06 | 1319.40 |
| 2020-02-07 |  609.00 |
+------------+---------+

2.3 层次数据遍历

公司的组织架构、文件夹目录、家族成员关系等等，都是层次关系的数据。以公司员工上下级关系为例，来说明使用递归CTE实现层次数据的遍历。原始数据如下：
# create the table
CREATE TABLE orgchart(
id INT PRIMARY KEY,
name VARCHAR(20),
role VARCHAR(20),
manager_id INT,
FOREIGN KEY (manager_id) REFERENCES orgchart(id));


# insert the rows
INSERT INTO orgchart VALUES(1,'Matthew','CEO',NULL),
(2,'Caroline','CFO',1),(3,'Tom','CTO',1),
(4,'Sam','Treasurer',2),(5,'Ann','Controller',2),
(6,'Anthony','Dev Director',3),(7,'Lousie','Sys Admin',3),
(8,'Travis','Senior DBA',3),(9,'John','Developer',6),
(10,'Jennifer','Developer',6),(11,'Maria','Junior DBA',8);


# let's see the table, The CEO has no manager, so the manager_id is set to NULL
SELECT * FROM orgchat;
+----+----------+--------------+------------+
| id | name     | role         | manager_id |
+----+----------+--------------+------------+
|  1 | Matthew  | CEO          |       NULL |
|  2 | Caroline | CFO          |          1 |
|  3 | Tom      | CTO          |          1 |
|  4 | Sam      | Treasurer    |          2 |
|  5 | Ann      | Controller   |          2 |
|  6 | Anthony  | Dev Director |          3 |
|  7 | Lousie   | Sys Admin    |          3 |
|  8 | Travis   | Senior DBA   |          3 |
|  9 | John     | Developer    |          6 |
| 10 | Jennifer | Developer    |          6 |
| 11 | Maria    | Junior DBA   |          8 |
+----+----------+--------------+------------+

使用CTE递归遍历这种层次结构，如下：
# find the reporting chain for all the employees
mysql> WITH RECURSIVE reporting_chain(id, name, path) AS (
          SELECT id, name, CAST(name AS CHAR(100))  
          FROM org_chart
          WHERE manager_id IS NULL
          UNION ALL
          SELECT oc.id, oc.name, CONCAT(rc.path,' -> ',oc.name)
          FROM reporting_chain rc JOIN org_chart oc ON rc.id=oc.manager_id)
       SELECT * FROM reporting_chain;
+------+----------+---------------------------------------+
| id   | name     | path                                  |
+------+----------+---------------------------------------+
|    1 | Matthew  | Matthew                               |
|    2 | Caroline | Matthew -> Caroline                   |
|    3 | Tom      | Matthew -> Tom                        |
|    4 | Sam      | Matthew -> Caroline -> Sam            |
|    5 | Ann      | Matthew -> Caroline -> Ann            |
|    6 | Anthony  | Matthew -> Tom -> Anthony             |
|    7 | Lousie   | Matthew -> Tom -> Lousie              |
|    8 | Travis   | Matthew -> Tom -> Travis              |
|    9 | John     | Matthew -> Tom -> Anthony -> John     |
|   10 | Jennifer | Matthew -> Tom -> Anthony -> Jennifer |
|   11 | Maria    | Matthew -> Tom -> Travis -> Maria     |
+------+----------+---------------------------------------+

这里比较关键的一点是使用了 CAST 函数在CTE的种子成员里，如果不使用CAST函数，则会报错，如下：
mysql> WITH RECURSIVE reporting_chain(id, name, path) AS (
          SELECT id, name, name
          FROM org_chart
          WHERE manager_id IS NULL
          UNION ALL
          SELECT oc.id, oc.name, CONCAT(rc.path,' -> ',oc.name)
          FROM reporting_chain rc JOIN org_chart oc ON rc.id=oc.manager_id)
       SELECT * FROM reporting_chain;
ERROR 1406 (22001): Data too long for column 'path' at row 1
上面这个SQL语法上是正确的，但是问题在于path字段的类型由非递归的SELECT决定，所以它是CHAR(7)，也就是字符串Matthew的长度，所以在CTE递归调用中，将会导致一个字符串截断的报错。

更进一步，我们打印层级的深度level，如下：
mysql> WITH RECURSIVE reporting_chain(id, name, path, level) AS (
          SELECT id, name, CAST(name AS CHAR(100)), 1  
          FROM org_chart
          WHERE manager_id IS NULL
          UNION ALL
          SELECT oc.id, oc.name, CONCAT(rc.path,' -> ',oc.name), rc.level+1
          FROM reporting_chain rc JOIN org_chart oc ON rc.id=oc.manager_id)
       SELECT * FROM reporting_chain ORDER BY level;
+------+----------+---------------------------------------+-------+
| id   | name     | path                                  | level |
+------+----------+---------------------------------------+-------+
|    1 | Matthew  | Matthew                               |     1 |
|    2 | Caroline | Matthew -> Caroline                   |     2 |
|    3 | Tom      | Matthew -> Tom                        |     2 |
|    4 | Sam      | Matthew -> Caroline -> Sam            |     3 |
|    5 | Ann      | Matthew -> Caroline -> Ann            |     3 |
|    6 | Anthony  | Matthew -> Tom -> Anthony             |     3 |
|    7 | Lousie   | Matthew -> Tom -> Lousie              |     3 |
|    8 | Travis   | Matthew -> Tom -> Travis              |     3 |
|    9 | John     | Matthew -> Tom -> Anthony -> John     |     4 |
|   10 | Jennifer | Matthew -> Tom -> Anthony -> Jennifer |     4 |
|   11 | Maria    | Matthew -> Tom -> Travis -> Maria     |     4 |
+------+----------+---------------------------------------+-------+


来看一个更复杂的树形结构，家谱。数据中包含祖父母、父母和孩子，原始数据如下。
CREATE TABLE genealogy(
id INT PRIMARY KEY,
name VARCHAR(20),
father_id INT,
mother_id INT,
FOREIGN KEY(father_id) REFERENCES genealogy(id),
FOREIGN KEY(mother_id) REFERENCES genealogy(id));


# populate the table
INSERT INTO genealogy VALUES(1,'Maria',NULL,NULL),
(2,'Tom',NULL,NULL),(3,'Robert',NULL,NULL),
(4,'Claire',NULL,NULL),(5,'John',2,1),
(6,'Jennifer',2,1),(7,'Sam',3,4),
(8,'James',7,6);


SELECT * FROM genealogy;
+----+----------+-----------+-----------+
| id | name     | father_id | mother_id |
+----+----------+-----------+-----------+
|  1 | Maria    |      NULL |      NULL |
|  2 | Tom      |      NULL |      NULL |
|  3 | Robert   |      NULL |      NULL |
|  4 | Claire   |      NULL |      NULL |
|  5 | John     |         2 |         1 |
|  6 | Jennifer |         2 |         1 |
|  7 | Sam      |         3 |         4 |
|  8 | James    |         7 |         6 |
+----+----------+-----------+-----------+

通过CTE递归，我们可以查询某一个人的祖先及与他的关系，如下：
mysql> WITH RECURSIVE ancestors AS (
          SELECT *, CAST('son' AS CHAR(20)) AS relationship, 0 level
          FROM genealogy  
          WHERE name='James'
          UNION ALL
          SELECT g.*, CASE WHEN g.id=a.father_id AND level=0 THEN 'father'
                           WHEN g.id=a.mother_id AND level=0 THEN 'mother'
                           WHEN g.id=a.father_id AND level=1 THEN 'grandfather'
                           WHEN g.id=a.mother_id AND level=1 THEN 'grandmother'
                       END,
                       level+1
           FROM genealogy g, ancestors a
           WHERE g.id=a.father_id OR g.id=a.mother_id)
        SELECT * FROM ancestors;
+------+----------+-----------+-----------+--------------+-------+
| id   | name     | father_id | mother_id | relationship | level |
+------+----------+-----------+-----------+--------------+-------+
|    8 | James    |         7 |         6 | son          |     0 |
|    6 | Jennifer |         2 |         1 | mother       |     1 |
|    7 | Sam      |         3 |         4 | father       |     1 |
|    1 | Maria    |      NULL |      NULL | grandmother  |     2 |
|    2 | Tom      |      NULL |      NULL | grandfather  |     2 |
|    3 | Robert   |      NULL |      NULL | grandfather  |     2 |
|    4 | Claire   |      NULL |      NULL | grandmother  |     2 |
+------+----------+-----------+-----------+--------------+-------+

2.4 图结构遍历

看一个交通线路的例子，创建一个表，包含各个站点之间的线路，以及它们之间的距离，原始数据如下：
CREATE TABLE train_route(
id INT PRIMARY KEY,
origin VARCHAR(20),
destination VARCHAR(20),
distance INT);


# populate the table
INSERT INTO train_route VALUES(1,'MILAN','TURIN',150),
(2,'TURIN','MILAN',150),(3,'MILAN','VENICE',250),
(4,'VENICE','MILAN',250),(5,'MILAN','GENOA',200),
(6,'MILAN','ROME',600),(7,'ROME','MILAN',600),
(8,'MILAN','FLORENCE',380),(9,'TURIN','GENOA',160),
(10,'GENOA','TURIN',160),(11,'FLORENCE','VENICE',550),
(12,'FLORENCE','ROME',220),(13,'ROME','FLORENCE',220),
(14,'GENOA','ROME',500),(15,'ROME','NAPLES',210),
(16,'NAPLES','VENICE',800);


SELECT * FROM train_route;
+----+----------+-------------+----------+
| id | origin   | destination | distance |
+----+----------+-------------+----------+
|  1 | MILAN    | TURIN       |      150 |
|  2 | TURIN    | MILAN       |      150 |
|  3 | MILAN    | VENICE      |      250 |
|  4 | VENICE   | MILAN       |      250 |
|  5 | MILAN    | GENOA       |      200 |
|  6 | MILAN    | ROME        |      600 |
|  7 | ROME     | MILAN       |      600 |
|  8 | MILAN    | FLORENCE    |      380 |
|  9 | TURIN    | GENOA       |      160 |
| 10 | GENOA    | TURIN       |      160 |
| 11 | FLORENCE | VENICE      |      550 |
| 12 | FLORENCE | ROME        |      220 |
| 13 | ROME     | FLORENCE    |      220 |
| 14 | GENOA    | ROME        |      500 |
| 15 | ROME     | NAPLES      |      210 |
| 16 | NAPLES   | VENICE      |      800 |
+----+----------+-------------+----------+

返回起点为 Milan，可到达的所有目的地，如下：
mysql> WITH RECURSIVE train_destination AS (
          SELECT origin AS dest
          FROM train_route
          WHERE origin='MILAN'  
          UNION  
          SELECT tr.destination
          FROM train_route tr
          JOIN train_destination td ON td.dest=tr.origin)
       SELECT * from train_destination;
+----------+
| dest     |
+----------+
| MILAN    |
| TURIN    |
| VENICE   |
| GENOA    |
| ROME     |
| FLORENCE |
| NAPLES   |
+----------+

从一个地点出发，到达另外一个地点可以有多条路径，比如起点为Milan，终点任意，我们看下有多少条路线，每条路线的距离是多少，如下：
mysql> WITH RECURSIVE paths (cur_path, cur_dest, tot_distance) AS (     
          SELECT CAST(origin AS CHAR(100)), CAST(origin AS CHAR(100)), 0
          FROM train_route
          WHERE origin='MILAN'   
          UNION     
          SELECT CONCAT(paths.cur_path, ' -> ', train_route.destination), train_route.destination, paths.tot_distance+train_route.distance        
          FROM paths, train_route        
          WHERE paths.cur_dest = train_route.origin
           AND  NOT FIND_IN_SET(train_route.destination, REPLACE(paths.cur_path,' -> ',',') ) )
       SELECT * FROM paths;
+-------------------------------------------------------+----------+--------------+
| cur_path                                              | cur_dest | tot_distance |
+-------------------------------------------------------+----------+--------------+
| MILAN                                                 | MILAN    |            0 |
| MILAN -> TURIN                                        | TURIN    |          150 |
| MILAN -> VENICE                                       | VENICE   |          250 |
| MILAN -> GENOA                                        | GENOA    |          200 |
| MILAN -> ROME                                         | ROME     |          600 |
| MILAN -> FLORENCE                                     | FLORENCE |          380 |
| MILAN -> TURIN -> GENOA                               | GENOA    |          310 |
| MILAN -> GENOA -> TURIN                               | TURIN    |          360 |
| MILAN -> GENOA -> ROME                                | ROME     |          700 |
| MILAN -> ROME -> FLORENCE                             | FLORENCE |          820 |
| MILAN -> ROME -> NAPLES                               | NAPLES   |          810 |
| MILAN -> FLORENCE -> VENICE                           | VENICE   |          930 |
| MILAN -> FLORENCE -> ROME                             | ROME     |          600 |
| MILAN -> TURIN -> GENOA -> ROME                       | ROME     |          810 |
| MILAN -> GENOA -> ROME -> FLORENCE                    | FLORENCE |          920 |
| MILAN -> GENOA -> ROME -> NAPLES                      | NAPLES   |          910 |
| MILAN -> ROME -> FLORENCE -> VENICE                   | VENICE   |         1370 |
| MILAN -> ROME -> NAPLES -> VENICE                     | VENICE   |         1610 |
| MILAN -> FLORENCE -> ROME -> NAPLES                   | NAPLES   |          810 |
| MILAN -> TURIN -> GENOA -> ROME -> FLORENCE           | FLORENCE |         1030 |
| MILAN -> TURIN -> GENOA -> ROME -> NAPLES             | NAPLES   |         1020 |
| MILAN -> GENOA -> ROME -> FLORENCE -> VENICE          | VENICE   |         1470 |
| MILAN -> GENOA -> ROME -> NAPLES -> VENICE            | VENICE   |         1710 |
| MILAN -> FLORENCE -> ROME -> NAPLES -> VENICE         | VENICE   |         1610 |
| MILAN -> TURIN -> GENOA -> ROME -> FLORENCE -> VENICE | VENICE   |         1580 |
| MILAN -> TURIN -> GENOA -> ROME -> NAPLES -> VENICE   | VENICE   |         1820 |
+-------------------------------------------------------+----------+--------------+

也可以找出一个起点与一个终点之间的最短路径，比如起点为MILAN，终点为NAPLES，如下：
# shortest path from MILAN to NAPLES
mysql> WITH RECURSIVE paths (cur_path, cur_dest, tot_distance) AS (     
          SELECT CAST(origin AS CHAR(100)), CAST(origin AS CHAR(100)), 0 FROM train_route WHERE origin='MILAN'   
          UNION     
          SELECT CONCAT(paths.cur_path, ' -> ', train_route.destination), train_route.destination, paths.tot_distance+train_route.distance        
          FROM paths, train_route        
          WHERE paths.cur_dest = train_route.origin AND NOT FIND_IN_SET(train_route.destination, REPLACE(paths.cur_path,' -> ',',') ) )
       SELECT * FROM paths
       WHERE cur_dest='NAPLES'
       ORDER BY tot_distance ASC LIMIT 1
+-------------------------+----------+--------------+
| cur_path                | cur_dest | tot_distance |
+-------------------------+----------+--------------+
| MILAN -> ROME -> NAPLES | NAPLES   |          810 |
+-------------------------+----------+--------------+


三、递归CTE使用限制

之间提到过，CTE递归有递归深度和执行时间的限制，除此之外，递归CTE的SELECT不能包含如下语句：
聚合函数，如SUM
group by
order by
distinct
窗口函数
这些限制只针对递归CTE，如果是非递归的CTE查询，则没有这些限制。

四、总结

CTE递归查询是MySQL 8.0 增加的非常有用的一个特性，以往使用存储过程实现递归的方式完全可以使用递归CTE代替，并且更加简单，相对于存储过程需要额外的授权，递归CTE就像普通的SQL一样，并不需要额外权限。当然，递归CTE相对于非递归CTE确实更加复杂，不仅在语法上，逻辑上也不易理解，需要仔细想想清楚。
 
