#!/usr/bin/env python3

import time

def calculate_subnet(slot_id):
    second_octet = 16 + (slot_id // 256) % 240
    third_octet = slot_id % 256
    return f"172.{second_octet}.{third_octet}.0/24"

def test_unique_subnets():
    print("Testing unique subnet assignments for slot IDs 1 to 10000...")
    
    used_subnets = set()
    collisions = 0

    for slot_id in range(1, 10001):
        subnet = calculate_subnet(slot_id)
        
        if subnet in used_subnets:
            print(f"Collision detected: Slot ID {slot_id} maps to existing subnet {subnet}")
            collisions += 1
        else:
            used_subnets.add(subnet)

    if collisions == 0:
        print("Test passed: All 10000 slot IDs have unique subnet assignments.")
    else:
        print(f"Test failed: {collisions} collisions detected.")

if __name__ == "__main__":
    start_time = time.time()
    test_unique_subnets()
    end_time = time.time()
    print(f"Execution time: {end_time - start_time:.4f} seconds")