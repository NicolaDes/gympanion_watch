#!/usr/bin/env python3
"""Fake companion app for GymPanion ConnectIQ simulator testing."""

import json
import socket
import sys
import threading

HOST = "0.0.0.0"
PORT = 7381

# Shared state: current connection (None when disconnected)
_conn = None
_conn_lock = threading.Lock()


# ---------------------------------------------------------------------------
# Receiver thread
# ---------------------------------------------------------------------------

def _receiver(conn: socket.socket) -> None:
    """Daemon thread: read messages from watch, pretty-print them."""
    buf = b""
    while True:
        try:
            chunk = conn.recv(4096)
        except OSError:
            break
        if not chunk:
            break
        buf += chunk
        # Try to decode as many complete JSON objects as possible
        while buf:
            try:
                msg, idx = json.JSONDecoder().raw_decode(buf.decode("utf-8"))
                buf = buf[idx:].lstrip()
                _print_event(msg)
            except (json.JSONDecodeError, UnicodeDecodeError):
                break  # wait for more data

    print("\n[companion] Watch disconnected.")
    with _conn_lock:
        global _conn
        _conn = None


# ---------------------------------------------------------------------------
# Event display
# ---------------------------------------------------------------------------

def _print_event(msg: dict) -> None:
    """Pretty-print a message received from the watch."""
    if not isinstance(msg, dict):
        print(f"[MSG] {msg}")
        return

    msg_type = msg.get("type", "unknown")

    if msg_type == "set_complete":
        exercise    = msg.get("exerciseName", "?")
        set_idx     = msg.get("setIndex", 0) + 1
        total_sets  = msg.get("totalSets", "?")
        ex_idx      = msg.get("exerciseIndex", 0) + 1
        total_ex    = msg.get("totalExercises", "?")
        duration_ms = msg.get("durationMs", 0)
        weight      = msg.get("targetWeight", 0)
        reps        = msg.get("targetReps", 0)
        duration_s  = duration_ms // 1000

        print()
        print(f"[SET COMPLETE] {exercise}  set {set_idx}/{total_sets}  (exercise {ex_idx}/{total_ex})")
        print(f"  Duration:  {duration_s}s")
        print(f"  Target:    {weight} kg × {reps} reps")
        print()
    else:
        print(f"[MSG] type={msg_type!r}  {json.dumps(msg)}")


# ---------------------------------------------------------------------------
# Workout presets
# ---------------------------------------------------------------------------

PUSH_DAY_WORKOUT = {
    "id": "push_day_001",
    "name": "Push Day",
    "exercises": [
        {"name": "Overhead Press", "sets": 4, "reps": 8, "weight": 40.0, "rest": 120},
        {"name": "Bench Press",    "sets": 4, "reps": 8, "weight": 60.0, "rest": 120},
        {"name": "Dips",           "sets": 3, "reps": 12, "weight": 0.0, "rest": 90},
    ],
}

def _send_json(payload: dict) -> bool:
    """Send a JSON payload to the watch with ConnectIQ framing."""
    with _conn_lock:
        conn = _conn
    if conn is None:
        print("[companion] No watch connected — nothing sent.")
        return False

    try:
        data = json.dumps(payload).encode("utf-8")
        # frame: 4-byte big-endian length + 1-byte message type (0x01 = generic message)
        frame = len(data).to_bytes(4, byteorder="big") + b'\x01' + data
        conn.sendall(frame)
        print("[companion] Workout sent.")
        return True
    except OSError as e:
        print(f"[companion] Send error: {e}")
        return False

# ---------------------------------------------------------------------------
# Interactive menu
# ---------------------------------------------------------------------------

def _menu() -> None:
    """Main thread: interactive CLI menu."""
    print()
    print("Commands:")
    print("  1  Send test workout (Push Day)")
    print("  2  Send custom workout from file")
    print("  q  Quit")

    while True:
        try:
            cmd = input("> ").strip().lower()
        except (EOFError, KeyboardInterrupt):
            print()
            break

        if cmd == "1":
            _send_json(PUSH_DAY_WORKOUT)

        elif cmd == "2":
            path = input("  JSON file path: ").strip()
            if not path:
                continue
            try:
                with open(path, "r") as f:
                    payload = json.load(f)
                _send_json(payload)
            except FileNotFoundError:
                print(f"  [error] File not found: {path}")
            except json.JSONDecodeError as e:
                print(f"  [error] Invalid JSON: {e}")

        elif cmd == "q":
            break

        elif cmd == "":
            pass  # re-show prompt

        else:
            print("  Unknown command. Use 1, 2, or q.")


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

def main() -> None:
    server = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    server.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    server.bind((HOST, PORT))
    server.listen(1)
    server.settimeout(1.0)  # allows KeyboardInterrupt to interrupt accept()

    print(f"[companion] Listening on {HOST}:{PORT} — waiting for ConnectIQ simulator...")

    menu_started = False

    try:
        while True:
            try:
                conn, addr = server.accept()
            except socket.timeout:
                continue
            except KeyboardInterrupt:
                break

            print(f"[companion] Simulator connected: {addr}")
            with _conn_lock:
                global _conn
                _conn = conn

            t = threading.Thread(target=_receiver, args=(conn,), daemon=True)
            t.start()

            if not menu_started:
                menu_started = True
                _menu()
                break  # exit after menu quits

    finally:
        server.close()
        print("[companion] Bye.")


if __name__ == "__main__":
    main()
