#!/usr/bin/env python3

# Write a function, sum_list, that takes in the head of a linked list containing numbers as an argument. 
# The function should return the total sum of all values in the linked list.

class Node:
  def __init__(self,val):
    self.val = val
    self.next = None

# iterative
# Complexity
# O(n), O(1)
def sum_list(a) -> int:
  sum: int = 0
  current = a
  while current is not None:
    sum = sum + current.val
    current = current.next
  return sum

# recursive
# Complexity
# O(n), O(n)
def sum_list(head) -> int:
  if head is None:
    return 0
  return head.val + sum_list(head.next)
  