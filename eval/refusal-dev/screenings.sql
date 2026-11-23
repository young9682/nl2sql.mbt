CREATE TABLE screenings (id INTEGER PRIMARY KEY, venue TEXT NOT NULL, screened_on TEXT NOT NULL,
  title TEXT NOT NULL, seats INTEGER NOT NULL);
INSERT INTO screenings VALUES
  (1,'Larch Theater','2025-09-04','Dunes',120),
  (2,'Larch Theater','2025-09-06','Rain',75),
  (3,'Reed Cinema','2025-09-06','Stars',180);
