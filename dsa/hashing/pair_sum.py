#!/usr/bin/env python3

# Write a function, pair_sum, that takes in a list and a target sum as arguments.
# The function should return a tuple containing a pair of indices whose elements sum to the given target.
# The indices returned must be unique.

# Be sure to return the indices, not the elements themselves.

# There is guaranteed to be one such pair that sums to the target.

# Approach 1: Brute Force
# Algorithmic Complexity
# Time complexity -> O(n2)
# Space complexity -> O(n)
def pair_sum(nums: list[int], target_sum: int) -> tuple:
    for i in range(0,len(nums)):
        for j in range(1, len(nums)):
            if nums[i] + nums[j] == target_sum:
                return(i,j)
    return -1


# Approach 2: More efficient with Dict

# Algorithmic Complexity
# Time complexity -> O(n)
# Space complexity -> O(n)
def pair_sum(nums: list[int], target_sum: int) -> tuple:
    previous_nums = {}  # Space Complexity -> O(n)
    for index, num in enumerate(nums):  # Time complexity = O(n)

        complement = target_sum - num
        
        if complement in previous_nums:  # Time complexity -> O(1), dict lookup, insert is constant time
            return (index, previous_nums[complement])
        
        previous_nums[num] = index

if __name__ == "__main__":
    assert(pair_sum([3, 2, 5, 4, 1], 8)) == (0,2) or (2,0), "test_1 failed"
    

