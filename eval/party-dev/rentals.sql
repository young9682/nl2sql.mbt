CREATE TABLE rentals (
  id INTEGER PRIMARY KEY, renter TEXT, owner TEXT NOT NULL,
  rented_on TEXT NOT NULL, item TEXT NOT NULL
);
INSERT INTO rentals VALUES
  (1,'Amber Guild','Cobalt Garage','2025-06-03','tripod'),
  (2,'Amber Guild','Cobalt Garage','2025-06-03','projector'),
  (3,'Amber Guild','Sable Club','2025-06-09','tripod'),
  (4,'Cobalt Garage','Amber Guild','2025-06-05','tripod'),
  (5,NULL,'Amber Guild','2025-06-07','screen'),
  (6,'Sable Club','Cobalt Garage','2025-06-05','screen');
