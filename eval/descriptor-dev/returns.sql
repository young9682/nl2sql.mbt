CREATE TABLE returns_log (id INTEGER PRIMARY KEY, category TEXT NOT NULL,
  label TEXT NOT NULL, received_on TEXT NOT NULL);
INSERT INTO returns_log VALUES
  (1,'cables','Mica Loop','2025-10-01'),
  (2,'cables','Mica Arch','2025-10-01'),
  (3,'cable','Slate Coil','2025-10-02'),
  (4,'category adapters','North Amber','2025-10-03'),
  (5,'adapters','North Ash','2025-10-04'),
  (6,'cases','category cables','2025-10-05'),
  (7,'metal clips','Red Glint','2025-10-06');
