-- =========================================================
-- SEATLOCK: Booking logic (row-locking based)
-- Run AFTER 00_schema.sql and 01_seed_data.sql
-- =========================================================

-- ---------------------------------------------------------
-- book_seat(seat_id, user_id)
--
-- This is the core of the whole project. It attempts to book a seat
-- safely under concurrent access, using SELECT ... FOR UPDATE to lock
-- the seat's existing booking rows before deciding whether it's free.
--
-- Why this works:
--   Without locking, two concurrent transactions could both check
--   "is this seat free?", both see "yes", and both insert a Confirmed
--   booking -- a classic race condition. FOR UPDATE forces the second
--   transaction to wait until the first one commits or rolls back,
--   so it sees the TRUE up-to-date state before deciding.
--
--   The partial unique index (idx_one_confirmed_booking_per_seat) is
--   a second, independent safety net: even if this function had a bug,
--   Postgres itself would still reject a duplicate Confirmed booking
--   for the same seat at the database level.
-- ---------------------------------------------------------

CREATE OR REPLACE FUNCTION book_seat(p_seat_id INT, p_user_id INT)
RETURNS TABLE (success BOOLEAN, message TEXT, booking_id INT) AS $$
DECLARE
    v_existing_booking_id INT;
    v_new_booking_id INT;
BEGIN
    -- Lock any existing CONFIRMED booking row for this seat, if one exists.
    -- Any other transaction trying to book/lock the same seat will now
    -- wait here until this transaction commits or rolls back.
    SELECT b.booking_id INTO v_existing_booking_id
    FROM booking b
    WHERE b.seat_id = p_seat_id AND b.status = 'Confirmed'
    FOR UPDATE;

    IF v_existing_booking_id IS NOT NULL THEN
        RETURN QUERY SELECT FALSE, 'Seat already booked'::TEXT, v_existing_booking_id;
        RETURN;
    END IF;

    -- No confirmed booking found (and we're holding the lock on this seat's
    -- row set), so it's genuinely safe to insert a new one.
    INSERT INTO booking (seat_id, user_id, status)
    VALUES (p_seat_id, p_user_id, 'Confirmed')
    RETURNING booking.booking_id INTO v_new_booking_id;

    RETURN QUERY SELECT TRUE, 'Booking confirmed'::TEXT, v_new_booking_id;
END;
$$ LANGUAGE plpgsql;


-- ---------------------------------------------------------
-- cancel_booking(booking_id)
-- Frees the seat back up by marking the booking Cancelled.
-- Because the unique index only applies to status = 'Confirmed' rows,
-- this immediately makes the seat bookable again.
-- ---------------------------------------------------------
CREATE OR REPLACE FUNCTION cancel_booking(p_booking_id INT)
RETURNS TABLE (success BOOLEAN, message TEXT) AS $$
BEGIN
    UPDATE booking
    SET status = 'Cancelled', cancelled_at = now()
    WHERE booking_id = p_booking_id AND status = 'Confirmed';

    IF FOUND THEN
        RETURN QUERY SELECT TRUE, 'Booking cancelled'::TEXT;
    ELSE
        RETURN QUERY SELECT FALSE, 'Booking not found or already cancelled'::TEXT;
    END IF;
END;
$$ LANGUAGE plpgsql;


-- ---------------------------------------------------------
-- Quick manual test (run these one at a time to see it work):
--
-- SELECT * FROM book_seat(
--     (SELECT seat_id FROM seat WHERE seat_label = 'Seat-3'
--      AND session_id = (SELECT session_id FROM session WHERE session_name = 'Intro to Database Concurrency')),
--     (SELECT user_id FROM app_user WHERE name = 'Ezra Voss')
-- );
-- -- run it again with the same seat -> should return success = false, 'Seat already booked'
-- ---------------------------------------------------------
