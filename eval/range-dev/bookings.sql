CREATE TABLE bookings (
  id INTEGER PRIMARY KEY, customer TEXT NOT NULL, provider TEXT NOT NULL,
  booked_on TEXT NOT NULL, due_on TEXT NOT NULL
);
INSERT INTO bookings VALUES
  (1,'Iris Studio','Moss Hall','2025-03-09','2025-03-15'),
  (2,'Iris Studio','Moss Hall','2025-03-10','2025-03-18'),
  (3,'Iris Studio','Fern Club','2025-03-10','2025-03-20'),
  (4,'Iris Studio','Moss Hall','2025-03-14','2025-03-19'),
  (5,'Moss Hall','Iris Studio','2025-03-10','2025-03-16'),
  (6,'Fern Club','Iris Studio','2025-03-12','2025-03-19');
