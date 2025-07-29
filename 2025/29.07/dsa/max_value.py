# PROBLEM:

# Write a function, max_value, that takes in list of numbers as an argument. The function should return the largest number in the list.
# Solve this without using any built-in list methods.
# You can assume that the list is non-empty.

# max_value([4, 7, 2, 8, 10, 9]) # -> 10
# max_value([10, 5, 40, 40.3]) # -> 40.3
# max_value([-5, -2, -1, -11]) # -> -1
# max_value([42]) # -> 42
# max_value([1000, 8]) # -> 1000
# max_value([1000, 8, 9000]) # -> 9000

def max_value(nums):
  max = float('-inf') # define a top level variable to hold the values during iteration
  for num in nums: # iterate
    if num > max:
      max = num # assign to the top level variable
  return max

if __name__ == '__main__':
  print(max_value([4, 7, 2, 8, 10, 9])) # -> 10
  print(max_value([10, 5, 40, 40.3])) # -> 40.3
  print(max_value([-5, -2, -1, -11])) # -> -1
  print(max_value([42])) # -> 42
  print(max_value([1000, 8])) # -> 1000
  print(max_value([1000, 8, 9000])) # -> 9000