CREATE TABLE releases (
  id INTEGER PRIMARY KEY, label TEXT NOT NULL UNIQUE,
  published_on TEXT NOT NULL, archived_on TEXT
);
INSERT INTO releases VALUES
  (1,'Saffron Kite','2025-02-14','2025-04-20'),
  (2,'Lunar Cable','2025-04-20',NULL),
  (3,'June Parade','2025-02-14','2025-07-03'),
  (4,'2025-02-14','2025-08-19',NULL);
CREATE TABLE meetups (
  id INTEGER PRIMARY KEY, name TEXT NOT NULL, venue TEXT NOT NULL, held_on TEXT NOT NULL
);
INSERT INTO meetups VALUES
  (1,'Cloud Circle','Union Yard','2024-06-09'),
  (2,'Signal Walk','Juniper Hall','2024-08-12'),
  (3,'Cable Night','Union Yard','2024-07-11');
