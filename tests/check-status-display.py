#!/usr/bin/env python3
import subprocess
import os

# Run vpn menu in a pseudo-terminal
import pty
import sys

def run_menu():
    # Create a pseudo-terminal
    master, slave = pty.openpty()
    
    # Run the vpn menu command
    proc = subprocess.Popen(
        ['/home/ikeniborn/Documents/Project/vpn/target/release/vpn', 'menu'],
        stdin=slave,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True
    )
    
    # Close slave end in parent
    os.close(slave)
    
    # Read initial output
    output = []
    while True:
        try:
            line = os.read(master, 1024).decode()
            if not line:
                break
            output.append(line)
            print(line, end='')
            
            # Look for menu header
            if "Server Status:" in line:
                # Read a few more lines to capture status
                for _ in range(10):
                    try:
                        line = os.read(master, 1024).decode()
                        output.append(line)
                        print(line, end='')
                    except:
                        break
                break
        except:
            break
    
    # Send exit command
    os.write(master, b"10\n")
    os.close(master)
    proc.terminate()
    
    return ''.join(output)

if __name__ == "__main__":
    print("Checking VPN menu status display...")
    print("=" * 50)
    output = run_menu()
    print("\n" + "=" * 50)
    
    # Check for expected status indicators
    if "●" in output:
        print("\n✓ Status indicators found!")
    else:
        print("\n✗ No status indicators found")
    
    if "(installed)" in output or "(not installed)" in output:
        print("✓ Installation status shown!")
    else:
        print("✗ Installation status not shown")