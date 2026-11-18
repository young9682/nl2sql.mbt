PRAGMA foreign_keys = ON;

CREATE TABLE users (
  id INTEGER PRIMARY KEY,
  name TEXT NOT NULL
);

CREATE TABLE orders (
  id INTEGER PRIMARY KEY,
  user_id INTEGER NOT NULL REFERENCES users(id),
  amount REAL NOT NULL,
  note TEXT,
  receipt BLOB NOT NULL
);

INSERT INTO users VALUES (1, '林'), (2, 'Sam');
INSERT INTO orders VALUES
  (1, 1, 7.5, 'first', X'0100FF'),
  (2, 2, 20.0, 'shipped', X'01'),
  (9007199254740993, 1, 42.5, NULL, X'');

CREATE TABLE products (
  region TEXT NOT NULL,
  sku TEXT NOT NULL,
  title TEXT NOT NULL,
  PRIMARY KEY (region, sku)
) WITHOUT ROWID;

CREATE TABLE stock (
  region TEXT NOT NULL,
  sku TEXT NOT NULL,
  available INTEGER NOT NULL,
  FOREIGN KEY (region, sku) REFERENCES products
);

INSERT INTO products VALUES ('east', 'A', 'Tea'), ('west', 'A', 'Coffee');
INSERT INTO stock VALUES ('east', 'A', 5), ('west', 'A', 16);

CREATE VIEW order_totals AS SELECT user_id, SUM(amount) AS total FROM orders GROUP BY user_id;
