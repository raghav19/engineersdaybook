#!/usr/bin/env python3

# Write a function, linked_list_values, that takes in the head of a linked list as an argument.
# The function should return a list containing all values of the nodes in the linked list.


class Node:
    def __init__(self, val):
        self.val = val
        self.next = None


def linked_list_values(a: list[str]) -> None:
    values: list[str] = []
    current = a
    while current is not None:
        values.append(current.val)
        current = current.next
    return values
