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
