import json
import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "src"))

from local_screen import get_manifest


class _FakeResponse:
    def __enter__(self):
        return self

    def __exit__(self, exc_type, exc, tb):
        return False

    def read(self):
        return json.dumps({"details": {"parameter_size": "14B"}}).encode("utf-8")


class LocalManifestTests(unittest.TestCase):
    def test_manifest_uses_local_json_api(self):
        seen = {}

        def opener(request, timeout):
            seen["url"] = request.full_url
            seen["body"] = json.loads(request.data.decode("utf-8"))
            seen["timeout"] = timeout
            return _FakeResponse()

        manifest = get_manifest("qwen3:14b", opener=opener)
        self.assertEqual(seen["url"], "http://127.0.0.1:11434/api/show")
        self.assertEqual(seen["body"], {"model": "qwen3:14b"})
        self.assertEqual(manifest["details"]["parameter_size"], "14B")


if __name__ == "__main__":
    unittest.main()
