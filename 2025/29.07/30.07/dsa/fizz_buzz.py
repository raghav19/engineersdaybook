# Write a function, fizz_buzz, that takes in a number n as an argument. The function should return a list containing numbers from 1 to n, replacing certain numbers according to the following rules:

# if the number is divisible by 3, make the element "fizz"
# if the number is divisible by 5, make the element "buzz"
# if the number is divisible by 3 and 5, make the element "fizzbuzz"


def fizz_buzz(n):
    result = []
    nums = range(1, n + 1)
    for num in nums:
        if num % 3 == 0 and num % 5 == 0:
            num = "fizzbuzz"
            result.append(num)
        elif num % 3 == 0:
            num = "fizz"
            result.append(num)
        elif num % 5 == 0:
            num = "buzz"
            result.append(num)
        else:
            result.append(num)
    return result


if __name__ == "__main__":
    fizz_buzz(11)  # -> [1,2,"fizz",4,"buzz","fizz",7,8,"fizz","buzz",11]
    fizz_buzz(2)  # -> [1,2]
    fizz_buzz(16)  # -> [
    #   1,
    #   2,
    #   "fizz",
    #   4,
    #   "buzz",
    #   "fizz",
    #   7,
    #   8,
    #   "fizz",
    #   "buzz",
    #   11,
    #   "fizz",
    #   13,
    #   14,
    #   "fizzbuzz",
    #   16
    # ]
    fizz_buzz(32)  # -> [
    #   1,      2,          "fizz",     4,
    #   "buzz", "fizz",     7,          8,
    #   "fizz", "buzz",     11,         "fizz",
    #   13,     14,         "fizzbuzz", 16,
    #   17,     "fizz",     19,         "buzz",
    #   "fizz", 22,         23,         "fizz",
    #   "buzz", 26,         "fizz",     28,
    #   29,     "fizzbuzz", 31,         32
    # ]
