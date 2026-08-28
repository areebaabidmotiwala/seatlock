"""
SeatLock — Interactive CLI

A simple menu-driven command-line interface for SeatLock, so anyone
(technical or not) can try booking/cancelling seats without writing
any SQL or Python themselves.

Usage:
    pip install psycopg2-binary
    python seatlock_cli.py

Edit DB_CONFIG below to match your local setup before running.
"""

import psycopg2

DB_CONFIG = {
    "host": "localhost",
    "port": 5432,
    "dbname": "seatlock",
    "user": "areebaabidmotiwala",
    "password": "",
}


def connect():
    return psycopg2.connect(**DB_CONFIG)


def list_sessions(conn):
    cur = conn.cursor()
    cur.execute("""
        SELECT sess.session_id, ev.name, sess.session_name, sess.start_time, sess.capacity,
               COUNT(b.booking_id) FILTER (WHERE b.status = 'Confirmed') AS booked_count
        FROM session sess
        JOIN event ev ON ev.event_id = sess.event_id
        LEFT JOIN seat s ON s.session_id = sess.session_id
        LEFT JOIN booking b ON b.seat_id = s.seat_id AND b.status = 'Confirmed'
        GROUP BY sess.session_id, ev.name, sess.session_name, sess.start_time, sess.capacity
        ORDER BY sess.session_id;
    """)
    rows = cur.fetchall()
    print("\nSessions:")
    print(f"{'ID':<4}{'Event':<26}{'Session':<38}{'Start':<20}{'Seats':<10}")
    for (sid, event_name, sname, start, cap, booked) in rows:
        print(f"{sid:<4}{event_name:<26}{sname:<38}{str(start):<20}{f'{booked}/{cap}':<10}")


def list_seats(conn, session_id):
    cur = conn.cursor()
    cur.execute("""
        SELECT s.seat_id, s.seat_label,
               CASE WHEN b.booking_id IS NULL THEN 'Available' ELSE 'Booked' END AS state
        FROM seat s
        LEFT JOIN booking b ON b.seat_id = s.seat_id AND b.status = 'Confirmed'
        WHERE s.session_id = %s
        ORDER BY s.seat_id;
    """, (session_id,))
    rows = cur.fetchall()
    print(f"\nSeats for session {session_id}:")
    for (seat_id, label, state) in rows:
        print(f"  [{seat_id}] {label:<12} {state}")
    return rows


def list_users(conn):
    cur = conn.cursor()
    cur.execute("SELECT user_id, name, email FROM app_user ORDER BY user_id;")
    rows = cur.fetchall()
    print("\nUsers:")
    for (uid, name, email) in rows:
        print(f"  [{uid}] {name} ({email})")
    return rows


def book_seat(conn, seat_id, user_id):
    cur = conn.cursor()
    cur.execute("SELECT * FROM book_seat(%s, %s);", (seat_id, user_id))
    success, message, booking_id = cur.fetchone()
    conn.commit()
    print(f"\n{'✔' if success else '✘'} {message} (booking_id={booking_id})")


def cancel_booking(conn, booking_id):
    cur = conn.cursor()
    cur.execute("SELECT * FROM cancel_booking(%s);", (booking_id,))
    success, message = cur.fetchone()
    conn.commit()
    print(f"\n{'✔' if success else '✘'} {message}")


def list_my_bookings(conn, user_id):
    cur = conn.cursor()
    cur.execute("""
        SELECT b.booking_id, ev.name, sess.session_name, s.seat_label, b.status, b.booked_at
        FROM booking b
        JOIN seat s ON s.seat_id = b.seat_id
        JOIN session sess ON sess.session_id = s.session_id
        JOIN event ev ON ev.event_id = sess.event_id
        WHERE b.user_id = %s
        ORDER BY b.booked_at DESC;
    """, (user_id,))
    rows = cur.fetchall()
    print(f"\nBookings for user {user_id}:")
    if not rows:
        print("  (none yet)")
    for (bid, event_name, sname, seat_label, status, booked_at) in rows:
        print(f"  [{bid}] {event_name} / {sname} / {seat_label} -- {status} (booked {booked_at})")


def main():
    print("=" * 50)
    print("  SeatLock CLI -- concurrency-safe event booking")
    print("=" * 50)

    conn = connect()

    while True:
        print("\nWhat would you like to do?")
        print("  1. View sessions")
        print("  2. View seats for a session")
        print("  3. Book a seat")
        print("  4. Cancel a booking")
        print("  5. View a user's bookings")
        print("  6. View users")
        print("  0. Exit")

        choice = input("\n> ").strip()

        if choice == "1":
            list_sessions(conn)

        elif choice == "2":
            session_id = input("Session ID: ").strip()
            list_seats(conn, session_id)

        elif choice == "3":
            list_sessions(conn)
            session_id = input("\nSession ID: ").strip()
            list_seats(conn, session_id)
            seat_id = input("\nSeat ID to book: ").strip()
            list_users(conn)
            user_id = input("\nYour User ID: ").strip()
            book_seat(conn, seat_id, user_id)

        elif choice == "4":
            booking_id = input("Booking ID to cancel: ").strip()
            cancel_booking(conn, booking_id)

        elif choice == "5":
            list_users(conn)
            user_id = input("\nUser ID: ").strip()
            list_my_bookings(conn, user_id)

        elif choice == "6":
            list_users(conn)

        elif choice == "0":
            print("Goodbye!")
            break

        else:
            print("Not a recognized option, try again.")

    conn.close()


if __name__ == "__main__":
    main()