import base64
import hashlib
import json
import unittest

import pocket_id_audit as audit


class VersionRange(unittest.TestCase):
    def test_bounded_and_open_ranges(self):
        v = audit.version_tuple("2.19.1")
        self.assertTrue(audit.in_range(v, ">= v2.2.0"))
        self.assertTrue(audit.in_range(v, ">= 2.0.0, < 2.20.0"))
        self.assertFalse(audit.in_range(v, "< 2.4.0"))
        self.assertFalse(audit.in_range(v, "<= v2.19.0"))
        self.assertTrue(audit.in_range(v, "= 2.19.1"))


class Tokens(unittest.TestCase):
    def test_pkce_challenge_is_s256_of_verifier(self):
        verifier, challenge = audit.pkce_pair()
        expected = base64.urlsafe_b64encode(hashlib.sha256(verifier.encode()).digest()).rstrip(b"=").decode()
        self.assertEqual(challenge, expected)

    def test_jwt_parts_decodes_unpadded_segments(self):
        enc = lambda o: base64.urlsafe_b64encode(json.dumps(o).encode()).rstrip(b"=").decode()
        head, claims = audit.jwt_parts(f"{enc({'alg': 'RS256'})}.{enc({'sub': 'x', 'n': 1})}.sig")
        self.assertEqual(head["alg"], "RS256")
        self.assertEqual(claims, {"sub": "x", "n": 1})


if __name__ == "__main__":
    unittest.main()
