PRAGMA foreign_keys = ON;

CREATE TABLE galleries (
  id INTEGER PRIMARY KEY,
  name TEXT NOT NULL UNIQUE,
  floor INTEGER NOT NULL
);

CREATE TABLE artworks (
  id INTEGER PRIMARY KEY,
  title TEXT NOT NULL UNIQUE,
  medium TEXT NOT NULL,
  insured_value INTEGER NOT NULL,
  acquired_year INTEGER NOT NULL,
  gallery_id INTEGER NOT NULL REFERENCES galleries(id),
  artist TEXT
);

CREATE TABLE exhibitions (
  id INTEGER PRIMARY KEY,
  title TEXT NOT NULL UNIQUE,
  gallery_id INTEGER NOT NULL REFERENCES galleries(id),
  opens_on TEXT NOT NULL,
  closes_on TEXT NOT NULL
);

CREATE TABLE loans (
  id INTEGER PRIMARY KEY,
  artwork_id INTEGER NOT NULL REFERENCES artworks(id),
  borrower TEXT NOT NULL,
  requested_on TEXT NOT NULL,
  returned_on TEXT
);

INSERT INTO galleries VALUES
  (1, 'Cedar Hall', 1),
  (2, 'East Loft', 2),
  (3, 'Paper Studio', 1),
  (4, 'North Annex', 3);

INSERT INTO artworks VALUES
  (101, 'Tide Marker', 'sculpture', 12000, 2018, 1, 'A. Reyes'),
  (102, 'Night Market', 'painting', 34000, 2021, 2, 'M. Chen'),
  (103, 'Folding Map', 'print', 5200, 2019, 3, NULL),
  (104, 'Glass Orchard', 'sculpture', 18000, 2022, 1, 'I. Novak'),
  (105, 'Rain Ledger', 'painting', 34000, 2017, 2, NULL),
  (106, 'River Loom', 'textile', 9600, 2023, 3, 'J. Mensah'),
  (107, 'Blue Index', 'print', 7600, 2022, 3, 'R. Singh'),
  (108, 'Amber Frame', 'photograph', 6800, 2020, 1, 'A. Reyes');

INSERT INTO exhibitions VALUES
  (201, 'Open Forms', 1, '2024-02-01', '2024-04-30'),
  (202, 'Ink Routes', 3, '2024-05-08', '2024-07-14'),
  (203, 'City After Dark', 2, '2023-11-18', '2024-02-09'),
  (204, 'Thread Lines', 1, '2025-01-10', '2025-03-22'),
  (205, 'New Neighbors', 4, '2024-10-05', '2024-12-01');

INSERT INTO loans VALUES
  (301, 102, 'Hill Library', '2024-01-09', '2024-04-06'),
  (302, 104, 'Harbor Museum', '2024-05-02', NULL),
  (303, 106, 'Hill Library', '2024-06-15', '2024-09-01'),
  (304, 103, 'West Archive', '2025-02-07', NULL),
  (305, 107, 'Harbor Museum', '2024-07-25', '2024-11-18');
