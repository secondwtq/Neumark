-- sqlite_workload.sql - deterministic SQLite benchmark workload.
--
-- Builds a two-table schema in :memory:, fills it with generated rows
-- (deterministic via WITH RECURSIVE), then runs a battery of queries:
-- aggregates, joins, ordering, LIKE filtering, grouping.
--
-- Run with: sqlite3 :memory: < sqlite_workload.sql

CREATE TABLE items(
  id    INTEGER PRIMARY KEY,
  cat   INTEGER NOT NULL,
  price INTEGER NOT NULL,
  name  TEXT NOT NULL
);
CREATE TABLE sales(
  id     INTEGER PRIMARY KEY,
  item   INTEGER NOT NULL,
  qty    INTEGER NOT NULL,
  amount INTEGER NOT NULL
);
CREATE INDEX idx_items_cat ON items(cat);
CREATE INDEX idx_sales_item ON sales(item);

-- 2,000,000 items with deterministic values
WITH RECURSIVE cnt(x) AS (
  SELECT 1 UNION ALL SELECT x+1 FROM cnt WHERE x < 4000000
)
INSERT INTO items
  SELECT x, (x * 2654435761) % 1000, (x * 40503) % 100000,
         'item-' || x FROM cnt;

-- 1,000,000 sales referencing items
WITH RECURSIVE cnt(x) AS (
  SELECT 1 UNION ALL SELECT x+1 FROM cnt WHERE x < 2000000
)
INSERT INTO sales
  SELECT x, (x * 40503) % 4000000 + 1, (x % 20) + 1,
         ((x * 2654435761) % 100000) FROM cnt;

.mode list
.separator ","
.output /dev/null

-- aggregate over all items
SELECT count(*), avg(price), sum(price), max(price) FROM items;
-- group by category
SELECT cat, count(*), avg(price) FROM items GROUP BY cat;
-- join sales to items
SELECT count(*), sum(s.amount) FROM sales s JOIN items i ON s.item = i.id;
-- join + group
SELECT i.cat, sum(s.qty), sum(s.amount)
  FROM sales s JOIN items i ON s.item = i.id
  GROUP BY i.cat;
-- range scan on the primary key
SELECT count(*) FROM items WHERE id BETWEEN 500000 AND 1500000;
-- LIKE filter
SELECT count(*) FROM items WHERE name LIKE 'item-12%';
-- order + limit
SELECT id, price FROM items ORDER BY price DESC LIMIT 1000;
-- aggregate join (category averages)
WITH catavg AS (SELECT cat, avg(price) AS a FROM items GROUP BY cat)
SELECT count(*) FROM items i JOIN catavg c ON i.cat = c.cat
  WHERE i.price > c.a;
-- update a slice + re-read
UPDATE items SET price = price + 1 WHERE id % 7 = 0;
SELECT count(*) FROM items WHERE price % 2 = 0;
-- delete a slice
DELETE FROM items WHERE id % 13 = 0;
SELECT count(*) FROM items;
