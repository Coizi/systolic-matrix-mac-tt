#!/usr/bin/env python3
"""
Systolic Array Matrix Multiply Tester
Communicates with Basys3 FPGA over UART (115200 baud)
Sends two 4x4 matrices, reads back the 4x4 product, verifies result.
"""

import serial
import serial.tools.list_ports
import time
import numpy as np


# =============================================================================
# Configuration
# =============================================================================
BAUD_RATE   = 115200
TIMEOUT_SEC = 5.0
START_BYTE  = 0xAB
END_BYTE    = 0xFF


# =============================================================================
# Helpers
# =============================================================================

def list_ports():
    ports = serial.tools.list_ports.comports()
    if not ports:
        print("No serial ports found.")
        return []
    print("Available ports:")
    for i, p in enumerate(ports):
        print(f"  [{i}] {p.device} - {p.description}")
    return ports


def pick_port():
    ports = list_ports()
    if not ports:
        return None
    if len(ports) == 1:
        print(f"Auto-selecting: {ports[0].device}")
        return ports[0].device
    idx = int(input("Select port number: "))
    return ports[idx].device


def matrix_input(name):
    """Prompt user to enter a 4x4 matrix row by row."""
    print(f"\nEnter matrix {name} (4x4, values 0-255, space-separated):")
    mat = []
    for i in range(4):
        while True:
            try:
                row = list(map(int, input(f"  Row {i}: ").split()))
                if len(row) != 4:
                    print("  Need exactly 4 values.")
                    continue
                if any(v < 0 or v > 255 for v in row):
                    print("  Values must be 0-255.")
                    continue
                mat.append(row)
                break
            except ValueError:
                print("  Invalid input, try again.")
    return mat


def pack_matrix(mat):
    """Flatten 4x4 matrix to 16 bytes, row-major."""
    return bytes([mat[r][c] for r in range(4) for c in range(4)])


def expected_result(a, b):
    """Compute expected 4x4 matrix product using numpy."""
    A = np.array(a, dtype=np.int64)
    B = np.array(b, dtype=np.int64)
    return (A @ B).tolist()


def send_matrices(ser, a, b):
    """Send start byte + 32 data bytes + end byte."""
    payload = bytes([START_BYTE]) + pack_matrix(a) + pack_matrix(b) + bytes([END_BYTE])
    print(f"\nSending {len(payload)} bytes to FPGA...")
    ser.write(payload)
    ser.flush()


def receive_results(ser):
    """Read 48 bytes back (16 results x 3 bytes each, 20-bit big-endian)."""
    print("Waiting for results...")
    data = b""
    deadline = time.time() + TIMEOUT_SEC
    while len(data) < 48:
        remaining = deadline - time.time()
        if remaining <= 0:
            print(f"  Timeout! Only received {len(data)}/48 bytes.")
            return None
        ser.timeout = remaining
        chunk = ser.read(48 - len(data))
        if chunk:
            data += chunk
            print(f"  Received {len(data)}/48 bytes...")
    return data


def parse_results(raw):
    print(f"  Raw bytes ({len(raw)}): {raw.hex()}")  # add this
    results = []
    for i in range(16):
        b0, b1, b2 = raw[3*i], raw[3*i+1], raw[3*i+2]
        val = (b0 << 16) | (b1 << 8) | b2
        results.append(val)
    return [results[r*4:(r+1)*4] for r in range(4)]


def print_matrix(name, mat):
    print(f"\n{name}:")
    for row in mat:
        print("  " + "  ".join(f"{v:8d}" for v in row))


def verify(fpga_result, expected):
    """Compare FPGA output to expected, print pass/fail per cell."""
    print("\n--- Verification ---")
    all_pass = True
    for r in range(4):
        for c in range(4):
            got = fpga_result[r][c]
            exp = expected[r][c]
            status = "PASS" if got == exp else "FAIL"
            if got != exp:
                all_pass = False
                print(f"  [{r}][{c}] expected={exp:8d}  got={got:8d}  <-- {status}")
            else:
                print(f"  [{r}][{c}] expected={exp:8d}  got={got:8d}      {status}")
    print()
    if all_pass:
        print("All 16 results correct!")
    else:
        print("Some results FAILED. Check FPGA design.")
    return all_pass


# =============================================================================
# Main
# =============================================================================

def main():
    print("=" * 50)
    print("  Systolic Array Matrix Multiply Tester")
    print("=" * 50)

    # Pick serial port
    port = pick_port()
    if not port:
        print("No port available. Exiting.")
        return

    # Open serial connection
    try:
        ser = serial.Serial(port, BAUD_RATE, timeout=TIMEOUT_SEC)
        print(f"Opened {port} at {BAUD_RATE} baud.")
    except serial.SerialException as e:
        print(f"Failed to open port: {e}")
        return

    try:
        while True:
            print("\n" + "=" * 50)

            # Get matrix inputs from user
            a = matrix_input("A")
            b = matrix_input("B")

            print_matrix("Matrix A", a)
            print_matrix("Matrix B", b)

            # Flush any stale bytes
            ser.reset_input_buffer()
            ser.reset_output_buffer()

            # Send to FPGA
            send_matrices(ser, a, b)

            # Receive results
            raw = receive_results(ser)
            if raw is None:
                print("Failed to receive results.")
            else:
                fpga_result = parse_results(raw)
                expected    = expected_result(a, b)

                print_matrix("FPGA Result", fpga_result)
                print_matrix("Expected (numpy)", expected)

                verify(fpga_result, expected)

            # Ask to run again
            again = input("\nRun another test? (y/n): ").strip().lower()
            if again != 'y':
                break

    finally:
        ser.close()
        print("Serial port closed.")


if __name__ == "__main__":
    main()