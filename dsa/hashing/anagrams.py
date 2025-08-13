#!/usr/bin/env python3

# Write a function, anagrams, that takes in two strings as arguments.
# The function should return a boolean indicating whether or not the strings are anagrams.
# Anagrams are strings that contain the same characters, but in any order.

# Algorithmic complexity
# Time complexity = O(n+m)
# Space complexity = O(n+m)


def anagrams(s1: str, s2: str):
    return char_count(s1) == char_count(s2)


def char_count(s: str) -> dict:
    count = {}  # Space complexity -> O(n)
    for char in s:  # Time complexity -> O(n)
        if (
            char not in count
        ):  # Time complexity -> O(1) (Dict lookups and insert operations as constant time)
            count[char] = 0
        else:
            count[char] = +1
    return count


if __name__ == "__main__":
    assert (anagrams("restful", "fluster")) == True, "test_1 failed"
    assert (anagrams("monkeyswrite", "newyorktimes")) == True, "test_2 failed"
    assert (anagrams("paper", "reapa")) == False, "test_3 failed"
    assert (anagrams("elbow", "below")) == True, "test_4 failed"
    assert (anagrams("elbow", "below")) == True, "test_5 failed"
    assert (anagrams("tax", "taxi")) == False, "test_6 failed"
    assert (anagrams("taxi", "tax")) == False, "test_7 failed"
    assert (anagrams("night", "thing")) == True, "test_8 failed"
    assert (anagrams("abbc", "aabc")) == False, "test_9 failed"
    assert (anagrams("po", "popp")) == False, "test_10 failed"
    assert (anagrams("pp", "oo")) == False, "test_11 failed"
    print("All assertions passed")
