CREATE TABLE parcels (
  id INTEGER PRIMARY KEY, label TEXT NOT NULL, shape TEXT NOT NULL,
  carrier TEXT NOT NULL, mass_g INTEGER NOT NULL
);
INSERT INTO parcels VALUES
  (1, 'North Star', 'tube', 'Lime Freight', 420),
  (2, 'West Gate', 'tube', 'Oak Post', 420),
  (3, 'Drift Line', 'tube', 'Lime Freight', 630),
  (4, 'River Bell', 'crate', 'Oak Post', 420),
  (5, 'Swift Gull', 'crate', 'Lime Freight', 980),
  (6, 'Copper Leaf', 'pouch', 'Oak Post', 110);
