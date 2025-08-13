#!/usr/bin/env python3

# Write a function, pair_product, that takes in a list and a target product as arguments.
# The function should return a tuple containing a pair of indices whose elements multiply to the given target.
# # The indices returned must be unique.

# Be sure to return the indices, not the elements themselves.

# There is guaranteed to be one such pair whose product is the target.


# Approach 2: Dict
# Time complexity -> O(n)
# Space complexity -> O(n)
def pair_product(nums: list[int], target_product: int) -> tuple:
    previous_nums = {}  # Space Complexity -> O(n)
    for index, num in enumerate(nums):  # Time Complexity -> O(n)
        complement = target_product / num

        # Time complexity -> O(1), dict have constant time lookup
        if complement in previous_nums:
            return (index, previous_nums[complement])

        previous_nums[num] = index


if __name__ == "__main__":
    assert (pair_product([3, 2, 5, 4, 1], 8)) == (1, 3) or (3, 1), "test_1 failed"
    assert (pair_product([3, 2, 5, 4, 1], 10)) == (1, 2) or (2, 1), "test_2 failed"
    assert (pair_product([4, 7, 9, 2, 5, 1], 5)) == (4, 5) or (5, 4), "test_3 failed"
    assert (pair_product([4, 7, 9, 2, 5, 1], 35)) == (1, 4) or (4, 1), "test_4 failed"
    assert (pair_product([3, 2, 5, 4, 1], 10)) == (1, 2) or (2, 1), "test_5 failed"
    assert (pair_product([4, 6, 8, 2], 16)) == (2, 3) or (3, 2), "test_6 failed"
    numbers = [i for i in range(1, 6001)]
    assert (pair_product(numbers, 35994000)) == (5998, 5999) or (
        5999,
        5998,
    ), "test_7 failed"
    print("All assertions passed")
