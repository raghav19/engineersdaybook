#!/usr/binenv python3


# Write a function, linked_list_find, that takes in the head of a linked list and a target value.
# The function should return a boolean indicating whether or not the linked list contains the target.


class Node:
    def __init__(self, val):
        self.val = val
        self.next = None


# Complexity
# O(n), O(1)
def linked_list_find(head, target) -> bool:
    contains_target: bool = False
    current = head
    while current is not None:
        if current.val == target:
            contains_target = True
            return contains_target
        current = current.next
    return contains_target


# Complexity
# O(n), O(n)
def linked_list_find(head, target) -> bool:
    if head is None:
        return False
    if head.val == target:
        return True
    return linked_list_find(head.next, target)
