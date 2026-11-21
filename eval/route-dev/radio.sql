PRAGMA foreign_keys=ON;
CREATE TABLE studios (id INTEGER PRIMARY KEY, callsign TEXT NOT NULL UNIQUE);
CREATE TABLE shows (id INTEGER PRIMARY KEY, title TEXT NOT NULL, studio_id INTEGER REFERENCES studios(id));
CREATE TABLE episodes (id INTEGER PRIMARY KEY, caption TEXT NOT NULL, show_id INTEGER NOT NULL REFERENCES shows(id));
CREATE TABLE bookings (id INTEGER PRIMARY KEY, guest TEXT NOT NULL, studio_id INTEGER NOT NULL REFERENCES studios(id));

INSERT INTO studios VALUES (10,'KITE'),(20,'WAVE'),(30,'MOSS');
INSERT INTO shows VALUES (1,'Crosswind',10),(2,'Low Tide',20),(3,'Lullaby',10),(4,'Untethered',NULL);
INSERT INTO episodes VALUES (7,'Granite',1),(8,'Copper',1),(9,'Granite',3),(11,'Rain',2),(12,'Solitude',4);
INSERT INTO bookings VALUES (1,'Rhea',10),(2,'Fern',10),(3,'Brook',20);
