CREATE TABLE inspections (id INTEGER PRIMARY KEY, kind TEXT NOT NULL,
  label TEXT NOT NULL, checked_on TEXT NOT NULL, reading INTEGER NOT NULL);
INSERT INTO inspections VALUES
  (1,'gasket','Moss Bells','2025-08-01',10),
  (2,'gasket','Moss Bells','2025-08-01',10),
  (3,'gasket','Moss Bell','2025-08-02',20),
  (4,'wrench','Shale Harbor','2025-08-04',30),
  (5,'brush','Copper Plain','2025-08-05',40),
  (6,'brushes','Oak Crest','2025-08-06',50),
  (7,'plates','Red Plain','2025-08-07',60),
  (8,'plate','Blue Plain','2025-08-08',70);
