import json, shutil, subprocess, unittest
from memory_router import contracts

def jq(obj, *args):
    payload = json.dumps(obj)
    out = subprocess.run(["jq", *args, "."], input=payload,
                         capture_output=True, text=True, check=True)
    return out.stdout  # jq appends a trailing newline

SAMPLES = [
    {},
    {"a": 1, "b": True, "c": None, "d": [1, 2, 3]},
    {"nested": {"x": [{"k": "v"}], "ü": "ä/ö"}},
    {"order_b": 2, "order_a": 1},   # insertion order must be preserved verbatim
    [],
    [1, "two", False, None],
]

@unittest.skipUnless(shutil.which("jq"), "jq not installed")
class TestContractsParity(unittest.TestCase):
    def test_compact_matches_jq_c(self):
        for obj in SAMPLES:
            self.assertEqual(contracts.dumps(obj) + "\n", jq(obj, "-c"))

    def test_pretty_matches_jq(self):
        for obj in SAMPLES:
            self.assertEqual(contracts.dumps(obj, pretty=True) + "\n", jq(obj))

if __name__ == "__main__":
    unittest.main()
