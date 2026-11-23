CREATE TABLE scores (id INTEGER PRIMARY KEY, title TEXT NOT NULL);
CREATE TABLE checkouts (
  id INTEGER PRIMARY KEY, score_id INTEGER NOT NULL REFERENCES scores(id),
  renter TEXT, lender TEXT NOT NULL
);
INSERT INTO scores VALUES
  (11,'Fir Waltz'), (12,'Rain Canon'), (13,'Open String'),
  (14,'Dawn Chorus'), (15,'Fir Waltz'), (16,'Silent Fugue');
INSERT INTO checkouts VALUES
  (101,11,'Cedar Choir','Lake Ensemble'),
  (102,12,'Cedar Choir','Wind Studio'),
  (103,15,'Cedar Choir','Lake Ensemble'),
  (104,13,NULL,'Cedar Choir'),
  (105,14,'Wind Studio','Cedar Choir');
