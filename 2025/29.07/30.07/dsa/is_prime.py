# Write a function, is_prime, that takes in a number as an argument. The function should return a boolean indicating whether or not the given number is prime.
# A prime number is a number that is only divisible by two distinct numbers: 1 and itself.
# For example, 7 is a prime because it is only divisible by 1 and 7. For example, 6 is not a prime because it is divisible by 1, 2, 3, and 6.
# You can assume that the input number is a positive integer.

import math


# approach 1
# in this approach, as n increases, the loop is pretty long and takes time increasing time complexity
# to simplify this an approach 2 is required
# Time: O(n) -> possible to cut down further from O(n)
# Space: O(1)
def is_prime_1(n):
    if n < 2:
        return False

    for i in range(2, n):
        if n % i == 0:
            return False

    return True


# approach 2:
# in this approach, the square root of the number is taken as the approach to allow for reducing the number of iterations
# with this the number of iterations is greatly reduce reducing the time complexity even further
# Time: O(logn)
# Space: O(1)
def is_prime_2(n):
    if n < 2:
        return False

    for i in range(2, math.floor(math.sqrt(n) + 1)):
        if n % i == 0:
            return False
    return True


if __name__ == "__main__":
    print(is_prime_1(2))  # -> True
    print(is_prime_1(3))  # -> True
    print(is_prime_1(4))  # -> False
    print(is_prime_1(5))  # -> True
    print(is_prime_1(6))  # -> False
    print(is_prime_1(7))  # -> True
    print(is_prime_1(8))  # -> False
    print(is_prime_1(25))  # -> False
    print(is_prime_1(31))  # -> True
    print(is_prime_1(2017))  # -> True
    print(is_prime_1(2048))  # -> False
    print(is_prime_1(1))  # -> False
    print(is_prime_1(713))  # -> False

    print(is_prime_2(2))  # -> True
    print(is_prime_2(3))  # -> True
    print(is_prime_2(4))  # -> False
    print(is_prime_2(5))  # -> True
    print(is_prime_2(6))  # -> False
    print(is_prime_2(7))  # -> True
    print(is_prime_2(8))  # -> False
    print(is_prime_2(25))  # -> False
    print(is_prime_2(31))  # -> True
    print(is_prime_2(2017))  # -> True
    print(is_prime_2(2048))  # -> False
    print(is_prime_2(1))  # -> False
    print(is_prime_2(713))  # -> False
