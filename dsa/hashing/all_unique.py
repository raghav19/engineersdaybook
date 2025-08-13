#!/usr/bin/env python3
# Write a function, all_unique, that takes in a list.
# The function should return a boolean indicating whether or not the list contains unique items.


# Algorithmic Complexity:
# Time complexity: O(n)
# Space Complexity = O(m)
def all_unique(l1: list) -> bool:
    return len(set(l1)) == len(l1)


if __name__ == "__main__":
    all_unique(["q", "r", "s", "a"])  # -> True
    all_unique(["q", "r", "s", "a", "r", "z"])  # -> False
    all_unique(["red", "blue", "yellow", "green", "orange"])  # -> True
    all_unique(["cat", "cat", "dog"])  # -> False
    all_unique(["a", "u", "t", "u", "m", "n"])  # -> False
