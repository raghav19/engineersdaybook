#!/usr/bin/env python3

# Write a function, intersection, that takes in two lists, a,b, as arguments.
# The function should return a new list containing elements that are in both of the two lists.

# You may assume that each input list does not contain duplicate elements.


# Algorithm complexity
# Time Complexity -> O(n)
# Space Complexity -> O(n+m)
def intersection(nums1: list[int], nums2: list[int]) -> list[int]:
    result: list[int] = []  # Space complexity -> O(n)
    set_a: set = set(nums1)  # Space complexity -> O(m)
    for num in nums2:  # Time complexity -> O(n)
        # Time complexity -> O(1), set has constant time lookup, insert, delete
        if num in set_a:
            result.append(num)  # Time complexity -> O(1), list has constant insert time
    return result


if __name__ == "__main__":
    assert (intersection([4, 2, 1, 6], [3, 6, 9, 2, 10])) == [2, 6] or [
        6,
        2,
    ], "test_1 failed"
    assert (intersection([2, 4, 6], [4, 2])) == [2, 4] or [4, 2], "test_2 failed"
    assert (intersection([4, 2, 1], [1, 2, 4, 6])) == [1, 2, 4], "test_3 failed"
    assert (intersection([0, 1, 2], [10, 11])) == [], "test_4 failed"
    a = [i for i in range(0, 50000)]
    b = [i for i in range(0, 50000)]
    assert (intersection(a, b)) == list(range(0, 50000)), "test_5 failed"
    print("All assertions passed")
