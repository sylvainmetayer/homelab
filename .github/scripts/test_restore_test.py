"""Tests of the command line of restore_test.py (Lint workflow:
python -I -m unittest discover -s .github/scripts -p 'test_*.py')."""
import unittest
from unittest import mock

import restore_test as rt


class Main(unittest.TestCase):
    def test_usage(self):
        with mock.patch("sys.stderr"):
            self.assertEqual(rt.main([]), 2)
            self.assertEqual(rt.main(["a", "b"]), 2)


if __name__ == "__main__":
    unittest.main()
