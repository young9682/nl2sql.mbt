CREATE TABLE tools (id INTEGER PRIMARY KEY, label TEXT NOT NULL UNIQUE,
  category TEXT NOT NULL, maker TEXT, listed_on TEXT NOT NULL, price INTEGER NOT NULL);
INSERT INTO tools VALUES
  (1,'Copper Finch','chisel','Elm Works','2025-03-01',12),
  (2,'Blue Loop','plane','Elm Works','2025-03-04',36),
  (3,'Red Notch','chisel','Cog Union','2025-03-03',12),
  (4,'Ash Wing','saw','Cog Union','2025-02-28',90),
  (5,'Quiet Pine','plane',NULL,'2025-03-06',48);
