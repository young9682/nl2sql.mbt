PRAGMA foreign_keys = ON;
CREATE TABLE bays (id INTEGER PRIMARY KEY, code TEXT NOT NULL, zone TEXT NOT NULL);
CREATE TABLE crates (id INTEGER PRIMARY KEY, tag TEXT NOT NULL, bay_id INTEGER REFERENCES bays(id), mass INTEGER NOT NULL);
CREATE TABLE scans (id INTEGER PRIMARY KEY, crate_id INTEGER NOT NULL REFERENCES crates(id), reader TEXT NOT NULL);
CREATE TABLE shifts (id INTEGER PRIMARY KEY, bay_id INTEGER NOT NULL REFERENCES bays(id), crew TEXT NOT NULL);

INSERT INTO bays VALUES (1, 'A17', 'west'), (2, 'B29', 'east'), (3, 'C14', 'west');
INSERT INTO crates VALUES (1, 'cedar', 1, 18), (2, 'ash', 1, 24), (3, 'elm', 2, 18), (4, 'oak', NULL, 9);
INSERT INTO scans VALUES (1, 1, 'R7'), (2, 1, 'S3'), (3, 3, 'R7');
INSERT INTO shifts VALUES (1, 1, 'Blue'), (2, 1, 'Red'), (3, 2, 'Blue');
