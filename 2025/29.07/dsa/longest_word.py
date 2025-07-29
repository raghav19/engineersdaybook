# Write a function, longest_word, that takes in a sentence string as an argument. The function should return the longest word in the sentence.
# If there is a tie, return the word that occurs later in the sentence.

# You can assume that the sentence is non-empty.

def longest_word(sentence):
    longest = ""
    word_array = str.split(sentence)
    for word in word_array:
        if len(word) >= len(longest):
            longest = word
    return longest


if __name__ == "__main__":
    print(longest_word("what a wonderful world"))  # -> "wonderful"
    print(longest_word("have a nice day"))  # # -> "nice"
    print(longest_word("the quick brown fox jumped over the lazy dog"))  # -> "jumped"
    print(longest_word("who did eat the ham"))  # -> "ham"
    print(longest_word("potato"))  # -> "potato"
