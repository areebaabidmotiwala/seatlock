"""
SeatLock — Concurrency Simulation

Fires multiple simultaneous booking attempts at the SAME seat from
separate database connections (each in its own thread, its own
transaction) and reports the outcome of each one.

If the locking logic in book_seat() (see 02_booking_logic.sql) is
correct, exactly ONE thread should succeed and every other thread
should be told the seat is already booked -- not error out, not
silently create a duplicate booking.

Usage:
    pip install psycopg2-binary
    python simulate_concurrent_booking.py

Edit the DB_CONFIG and SEAT_LABEL / SESSION_NAME below to match a
real seat in your seeded data before running.
"""

import psycopg2
import threading
import time

DB_CONFIG = {
    "host": "localhost",
    "port": 5432,
    "dbname": "seatlock",
    "user": "areebaabidmotiwala",   
    "password": "",
}

SESSION_NAME = "Scaling Postgres in Production"
SEAT_LABEL = "Seat-7"     # pick a seat that is NOT already booked in your seed data
NUM_CONCURRENT_USERS = 5  # how many simultaneous booking attempts to simulate

results = []
results_lock = threading.Lock()


def attempt_booking(user_name: str, seat_id: int, user_id: int):
    """Each thread runs this in its own connection/transaction."""
    conn = psycopg2.connect(**DB_CONFIG)
    conn.autocommit = False
    try:
        cur = conn.cursor()
        cur.execute("SELECT * FROM book_seat(%s, %s);", (seat_id, user_id))
        success, message, booking_id = cur.fetchone()
        conn.commit()

        with results_lock:
            results.append({
                "user": user_name,
                "success": success,
                "message": message,
                "booking_id": booking_id,
            })
    except Exception as e:
        conn.rollback()
        with results_lock:
            results.append({
                "user": user_name,
                "success": False,
                "message": f"ERROR: {e}",
                "booking_id": None,
            })
    finally:
        conn.close()


def get_seat_id(conn, session_name: str, seat_label: str) -> int:
    cur = conn.cursor()
    cur.execute(
        """
        SELECT s.seat_id FROM seat s
        JOIN session sess ON sess.session_id = s.session_id
        WHERE sess.session_name = %s AND s.seat_label = %s
        """,
        (session_name, seat_label),
    )
    row = cur.fetchone()
    if row is None:
        raise ValueError(f"No seat found for session='{session_name}', label='{seat_label}'")
    return row[0]


def get_sample_user_ids(conn, count: int) -> list[int]:
    cur = conn.cursor()
    cur.execute("SELECT user_id, name FROM app_user ORDER BY user_id LIMIT %s;", (count,))
    return cur.fetchall()


def main():
    setup_conn = psycopg2.connect(**DB_CONFIG)
    seat_id = get_seat_id(setup_conn, SESSION_NAME, SEAT_LABEL)
    users = get_sample_user_ids(setup_conn, NUM_CONCURRENT_USERS)
    setup_conn.close()

    print(f"Target seat: '{SEAT_LABEL}' in session '{SESSION_NAME}' (seat_id={seat_id})")
    print(f"Simulating {len(users)} users attempting to book it at the same time...\n")

    threads = []
    for (user_id, user_name) in users:
        t = threading.Thread(target=attempt_booking, args=(user_name, seat_id, user_id))
        threads.append(t)

    # Start all threads as close to simultaneously as possible
    for t in threads:
        t.start()
    for t in threads:
        t.join()

    # Report
    successes = [r for r in results if r["success"]]
    failures = [r for r in results if not r["success"]]

    print("Results:")
    for r in results:
        status = "SUCCESS" if r["success"] else "blocked"
        print(f"  [{status:7}] {r['user']:15} -> {r['message']} (booking_id={r['booking_id']})")

    print(f"\n{len(successes)} succeeded, {len(failures)} correctly blocked.")
    if len(successes) == 1:
        print("PASS: exactly one booking succeeded, as expected under correct locking.")
    else:
        print("FAIL: expected exactly 1 success -- check the locking logic.")


if __name__ == "__main__":
    main()