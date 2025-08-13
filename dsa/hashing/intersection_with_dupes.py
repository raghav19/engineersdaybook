# Write a function, intersection_with_dupes, that takes in two lists, a,b, as arguments.
# The function should return a new list containing elements that are common to both input lists.
# The elements in the result should appear as many times as they occur in both input lists.

# You can return the result in any order.

def intersection_with_dupes(a: list, b: list) -> list:
    result: list = []
    dict_a: dict = {}
    for value in a:
        if value not in dict_a:
            dict_a[value] = 1
        else:
            dict_a[value] += 1

    dict_b: dict = {}
    for value in b:
        if value not in dict_b:
            dict_b[value] = 1
        else:
            dict_b[value] += 1

    for k, v in dict_a.items():
        if k in dict_b:
            for itr in range(0, min(dict_a[k], dict_b[k])):
                result.append(k)
    return result


if __name__ == "__main__":
    pass
