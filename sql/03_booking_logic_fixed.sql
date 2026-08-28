-- =========================================================
-- SEATLOCK: Booking logic — FIXED VERSION
-- Replaces the book_seat() function from 02_booking_logic.sql.
--
-- BUG FOUND DURING TESTING:
-- The original version used `SELECT ... FROM booking ... FOR UPDATE`
-- to lock the seat's existing confirmed booking, if any. But FOR
-- UPDATE only locks rows that already exist -- on a seat with ZERO
-- prior bookings, there's nothing to lock, so concurrent transactions
-- could all pass the "is it free?" check at once and race to INSERT.
-- The partial unique index still caught the collision (no double
-- booking occurred), but as a fallback, not the intended mechanism --
-- and it surfaced as a raw Postgres error instead of the clean
-- "Seat already booked" message.
--
-- FIX: lock the SEAT row itself, not the booking row. A seat row
-- always exists once seeded, regardless of whether it's been booked
-- yet, so FOR UPDATE always has something real to lock -- forcing
-- concurrent transactions to queue up and check availability one at
-- a time, in order, rather than racing.
-- =========================================================

CREATE OR REPLACE FUNCTION book_seat(p_seat_id INT, p_user_id INT)
RETURNS TABLE (success BOOLEAN, message TEXT, booking_id INT) AS $$
DECLARE
    v_existing_booking_id INT;
    v_new_booking_id INT;
BEGIN
    -- Lock the SEAT row (always exists). Any other transaction trying
    -- to book the same seat now waits here, in order, until this
    -- transaction commits or rolls back.
    PERFORM 1 FROM seat WHERE seat_id = p_seat_id FOR UPDATE;

    -- Now that we hold the lock, it's safe to check the true current state.
    SELECT b.booking_id INTO v_existing_booking_id
    FROM booking b
    WHERE b.seat_id = p_seat_id AND b.status = 'Confirmed';

    IF v_existing_booking_id IS NOT NULL THEN
        RETURN QUERY SELECT FALSE, 'Seat already booked'::TEXT, v_existing_booking_id;
        RETURN;
    END IF;

    INSERT INTO booking (seat_id, user_id, status)
    VALUES (p_seat_id, p_user_id, 'Confirmed')
    RETURNING booking.booking_id INTO v_new_booking_id;

    RETURN QUERY SELECT TRUE, 'Booking confirmed'::TEXT, v_new_booking_id;
END;
$$ LANGUAGE plpgsql;

-- cancel_booking() is unchanged -- no fix needed there, its logic
-- was already correct (UPDATE ... WHERE status = 'Confirmed' is
-- atomic on its own; no separate lock step required).
