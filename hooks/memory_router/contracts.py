"""jq-identical JSON serialization. All stdout JSON in the CLI goes through dumps()."""
import json


def dumps(obj, pretty=False):
    if pretty:
        # jq default pretty: 2-space indent, ", "/": " separators, UTF-8 literals.
        return json.dumps(obj, indent=2, ensure_ascii=False)
    # jq -c compact: no spaces.
    return json.dumps(obj, separators=(",", ":"), ensure_ascii=False)
