-- =========================================================
-- SEATLOCK: Seed data
-- Run AFTER 00_schema.sql
-- =========================================================

-- Users (10)
INSERT INTO app_user (name, email) VALUES
('Jordan Blake', 'jordan.blake@example.com'),
('Sana Malik', 'sana.malik@example.com'),
('Priya Anand', 'priya.anand@example.com'),
('Devon Ashby', 'devon.ashby@example.com'),
('Ahmed Raza', 'ahmed.raza@example.com'),
('Caleb Doyle', 'caleb.doyle@example.com'),
('Talia Novak', 'talia.novak@example.com'),
('Bilal Sheikh', 'bilal.sheikh@example.com'),
('Ezra Voss', 'ezra.voss@example.com'),
('Ayesha Farooq', 'ayesha.farooq@example.com');

-- Events (2)
INSERT INTO event (name, event_date, venue) VALUES
('DevCon Local 2026', '2026-11-14', 'Mississauga Convention Centre'),
('Backend Systems Summit', '2027-02-20', 'Toronto Tech Hub');

-- Sessions (2 per event = 4 total). Capacities kept modest on purpose,
-- so it's easy to exhaust seats quickly when testing concurrent booking.
INSERT INTO session (event_id, session_name, start_time, capacity) VALUES
((SELECT event_id FROM event WHERE name = 'DevCon Local 2026'), 'Intro to Database Concurrency', '2026-11-14 09:00:00', 5),
((SELECT event_id FROM event WHERE name = 'DevCon Local 2026'), 'Scaling Postgres in Production', '2026-11-14 11:00:00', 8),
((SELECT event_id FROM event WHERE name = 'Backend Systems Summit'), 'Designing for High Concurrency', '2027-02-20 10:00:00', 6),
((SELECT event_id FROM event WHERE name = 'Backend Systems Summit'), 'Transactions, Locks, and Isolation Levels', '2027-02-20 13:30:00', 10);

-- Seats -- generated per session to match its capacity (5+8+6+10 = 29 seats total)
INSERT INTO seat (session_id, seat_label)
SELECT session_id, 'Seat-' || gs
FROM session, generate_series(1, capacity) AS gs
WHERE session_name = 'Intro to Database Concurrency';

INSERT INTO seat (session_id, seat_label)
SELECT session_id, 'Seat-' || gs
FROM session, generate_series(1, capacity) AS gs
WHERE session_name = 'Scaling Postgres in Production';

INSERT INTO seat (session_id, seat_label)
SELECT session_id, 'Seat-' || gs
FROM session, generate_series(1, capacity) AS gs
WHERE session_name = 'Designing for High Concurrency';

INSERT INTO seat (session_id, seat_label)
SELECT session_id, 'Seat-' || gs
FROM session, generate_series(1, capacity) AS gs
WHERE session_name = 'Transactions, Locks, and Isolation Levels';

-- A handful of pre-existing bookings across different sessions,
-- so the dataset isn't empty and partial-capacity scenarios exist to test against.
INSERT INTO booking (seat_id, user_id, status) VALUES
((SELECT seat_id FROM seat WHERE seat_label = 'Seat-1' AND session_id = (SELECT session_id FROM session WHERE session_name = 'Intro to Database Concurrency')),
 (SELECT user_id FROM app_user WHERE name = 'Jordan Blake'), 'Confirmed'),

((SELECT seat_id FROM seat WHERE seat_label = 'Seat-2' AND session_id = (SELECT session_id FROM session WHERE session_name = 'Intro to Database Concurrency')),
 (SELECT user_id FROM app_user WHERE name = 'Sana Malik'), 'Confirmed'),

((SELECT seat_id FROM seat WHERE seat_label = 'Seat-1' AND session_id = (SELECT session_id FROM session WHERE session_name = 'Scaling Postgres in Production')),
 (SELECT user_id FROM app_user WHERE name = 'Priya Anand'), 'Confirmed'),

((SELECT seat_id FROM seat WHERE seat_label = 'Seat-3' AND session_id = (SELECT session_id FROM session WHERE session_name = 'Scaling Postgres in Production')),
 (SELECT user_id FROM app_user WHERE name = 'Devon Ashby'), 'Confirmed'),

((SELECT seat_id FROM seat WHERE seat_label = 'Seat-1' AND session_id = (SELECT session_id FROM session WHERE session_name = 'Designing for High Concurrency')),
 (SELECT user_id FROM app_user WHERE name = 'Ahmed Raza'), 'Confirmed'),

-- one cancelled booking, to exercise the partial-unique-index behavior on read
((SELECT seat_id FROM seat WHERE seat_label = 'Seat-2' AND session_id = (SELECT session_id FROM session WHERE session_name = 'Designing for High Concurrency')),
 (SELECT user_id FROM app_user WHERE name = 'Caleb Doyle'), 'Cancelled'),

((SELECT seat_id FROM seat WHERE seat_label = 'Seat-1' AND session_id = (SELECT session_id FROM session WHERE session_name = 'Transactions, Locks, and Isolation Levels')),
 (SELECT user_id FROM app_user WHERE name = 'Talia Novak'), 'Confirmed'),

((SELECT seat_id FROM seat WHERE seat_label = 'Seat-4' AND session_id = (SELECT session_id FROM session WHERE session_name = 'Transactions, Locks, and Isolation Levels')),
 (SELECT user_id FROM app_user WHERE name = 'Bilal Sheikh'), 'Confirmed');

-- update the previously-cancelled row's cancelled_at for realism
UPDATE booking SET cancelled_at = now()
WHERE status = 'Cancelled'
  AND seat_id = (SELECT seat_id FROM seat WHERE seat_label = 'Seat-2' AND session_id = (SELECT session_id FROM session WHERE session_name = 'Designing for High Concurrency'));
