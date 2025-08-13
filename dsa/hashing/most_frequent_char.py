#!/usr/bin/env python3

# Write a function, most_frequent_char, that takes in a string as an argument.
# The function should return the most frequent character of the string.
# If there are ties, return the character that appears earlier in the string.

# You can assume that the input string is non-empty.

# Algorithmic Complexity
# Time complexity = O(n)
# Space complexity = O(n)


def most_frequent_char(s: str) -> str:
    count: dict = char_count(s)
    result: str = None
    for char in s:  # Time complexity -> O(n)
        if result == None or count[char] > count[result]:  # Time complexity -> O(1)
            result = char
    return result


def char_count(s: str) -> dict:
    count: dict = {}  # Space complexity -> O(n)
    for char in s:  # Time complexity -> O(n)
        if (
            char not in count
        ):  # Time complexity -> O(1), Dict has constant time lookup,insert
            count[char] = 0
        else:
            count[char] += 1
    return count


if __name__ == "__main__":
    assert (most_frequent_char("bookeeper")) == "e", "test_1 failed"
    assert (most_frequent_char("david")) == "d", "test_2 failed"
    assert (most_frequent_char("david")) == "d", "test_3 failed"
    assert (most_frequent_char("mississippi")) == "i", "test_4 failed"
    assert (most_frequent_char("potato")) == "o", "test_5 failed"
    assert (most_frequent_char("eleventennine")) == "e", "test_6 failed"
    assert (most_frequent_char("riverbed")) == "r", "test_7  failed"
    print("All assertions passed")
