import os
import sys
import unittest

sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))
import rules


class PathRules(unittest.TestCase):
    def test_traversal(self) -> None:
        self.assertEqual(rules.check_path("../../etc/passwd"), "path-traversal")
        self.assertEqual(rules.check_path("/etc/passwd"), "path-traversal")

    def test_sensitive(self) -> None:
        for p in (".env", "deploy/server.pem", "infra/terraform.tfstate"):
            self.assertEqual(rules.check_path(p), "sensitive-path", p)

    def test_benign(self) -> None:
        self.assertIsNone(rules.check_path("docs/README.md"))


class SecretRules(unittest.TestCase):
    def test_detect_and_redact(self) -> None:
        token = "ghp_" + "a" * 36
        self.assertEqual(rules.find_secret(f"x {token} y"), "secret-github-token")
        out, fired = rules.redact(f"x {token} y")
        self.assertNotIn(token, out)
        self.assertEqual(fired, ["secret-github-token"])

    def test_clean(self) -> None:
        self.assertIsNone(rules.find_secret("hello world"))


if __name__ == "__main__":
    unittest.main()
