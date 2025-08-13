# Write a function, exclusive_items, that takes in two lists, a,b, as arguments.
# The function should return a new list containing elements that are in either list but not both lists.

# You may assume that each input list does not contain duplicate elements.


# Approach: Compare 2 lists with multiple sets
# Time complexity
# Space complexity
def exclusive_items(l1: list, l2: list) -> list:
    set_a = set(l1)
    set_b = set(l2)
    exclusive: list = []  # Space complexity -> O(n)
    for item in l2:  # Time complexity -> O(n)
        # Time complexity -> O(1), set have constant time lookup
        if item not in set_a:
            # Time complexity -> O(1), list have constant time insert
            exclusive.append(item)

    for item in l1:  # Time complexity -> O(m)
        # Time complexity -> O(1), set have constant time lookup
        if item not in set_b:
            # Time complexity -> O(1), list have constant time insert
            exclusive.append(item)

    return exclusive


if __name__ == "__main__":
    exclusive_items([4, 2, 1, 6], [3, 6, 9, 2, 10])  # -> [4,1,3,9,10]
    exclusive_items([2, 4, 6], [4, 2])  # -> [6]
    exclusive_items([4, 2, 1], [1, 2, 4, 6])
    exclusive_items([0, 1, 2], [10, 11])
    a = [i for i in range(0, 50000)]
    b = [i for i in range(0, 50000)]
    exclusive_items(a, b)  # -> [ ]
    pass
