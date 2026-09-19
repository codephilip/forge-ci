"""Tests for the log parsers and job classification behind Forge's Testing view.

Fixtures are synthetic but mirror the exact summary formats each tool prints
(ANSI colour and GitHub's per-line timestamps included, as the logs API returns them).
"""
import os
import sys
import unittest
from pathlib import Path

os.environ.setdefault("FORGE_DB", ":memory:")
sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "forge"))
import server  # noqa: E402


def log(text):
    """Build a raw log the way GitHub returns it: timestamp prefix + ANSI colour."""
    lines = [f"2026-09-19T15:04:4{i % 10}.1234567Z {ln}" for i, ln in enumerate(text.strip("\n").splitlines())]
    return server.clean_log("\n".join(lines).encode())


class CleanLog(unittest.TestCase):
    def test_strips_timestamps_and_ansi(self):
        lines = server.clean_log(b"2026-09-19T15:04:43.1Z \x1b[32m\xe2\x9c\x93\x1b[39m ok\n")
        self.assertEqual(lines, ["✓ ok"])


class Vitest(unittest.TestCase):
    def test_passing_summary(self):
        r = server.parse_test_log(log("""
 ✓ src/a.test.ts (25 tests) 291ms
 Test Files  1 passed (1)
      Tests  16248 passed | 2 skipped (16250)
"""), "Test")
        self.assertEqual((r["kind"], r["passed"], r["failed"], r["skipped"], r["total"]), ("vitest", 16248, 0, 2, 16250))

    def test_failures_prefer_full_path_names(self):
        r = server.parse_test_log(log("""
 ❯ src/chart.test.ts (39 tests | 2 failed) 133ms
   × is on PATH 13ms
   × values.yaml renders without error 5ms
 Test Files  1 failed | 3 passed (4)
      Tests  2 failed | 120 passed (122)
⎯⎯⎯⎯⎯⎯ Failed Tests 2 ⎯⎯⎯⎯⎯⎯⎯
 FAIL  src/chart.test.ts > helm is available > is on PATH
AssertionError: helm is not on PATH
 FAIL  src/chart.test.ts > every environment renders > values.yaml renders without error
"""), "Test")
        self.assertEqual((r["failed"], r["passed"], r["total"]), (2, 120, 122))
        self.assertEqual(r["failures"], ["src/chart.test.ts > helm is available > is on PATH",
                                         "src/chart.test.ts > every environment renders > values.yaml renders without error"])

    def test_falls_back_to_cross_lines_without_timing(self):
        r = server.parse_test_log(log("""
   × rejects a bad budget 3ms
      Tests  1 failed | 4 passed (5)
"""), "Test")
        self.assertEqual(r["failures"], ["rejects a bad budget"])

    def test_multiple_runs_in_one_job_are_summed(self):
        r = server.parse_test_log(log("""
      Tests  10 passed (10)
      Tests  3 passed | 1 skipped (4)
"""), "Node drainer")
        self.assertEqual((r["passed"], r["skipped"], r["total"]), (13, 1, 14))


class Jest(unittest.TestCase):
    def test_summary(self):
        r = server.parse_test_log(log("""
  ● Cart › applies the discount
Tests:       1 failed, 2 skipped, 11 passed, 14 total
"""), "test")
        self.assertEqual((r["kind"], r["failed"], r["skipped"], r["passed"], r["total"]), ("jest", 1, 2, 11, 14))
        self.assertIn("Cart › applies the discount", r["failures"])


class GoTest(unittest.TestCase):
    def test_counts_and_failures(self):
        r = server.parse_test_log(log("""
--- PASS: TestParse (0.00s)
--- FAIL: TestRender (0.01s)
--- PASS: TestServe (0.02s)
"""), "go test")
        self.assertEqual((r["kind"], r["passed"], r["failed"], r["total"]), ("go", 2, 1, 3))
        self.assertEqual(r["failures"], ["TestRender"])


class Eslint(unittest.TestCase):
    def test_problems_line(self):
        r = server.parse_test_log(log("✖ 12 problems (3 errors, 9 warnings)"), "Lint")
        self.assertEqual((r["kind"], r["errors"], r["warnings"]), ("eslint", 3, 9))

    def test_clean_lint_has_no_summary(self):
        self.assertIsNone(server.parse_test_log(log("> eslint .\nDone"), "Lint"))


class Tsc(unittest.TestCase):
    def test_clean_typecheck_records_zero_errors(self):
        r = server.parse_test_log(log("> tsc --noEmit\n"), "Typecheck")
        self.assertEqual((r["kind"], r["errors"]), ("tsc", 0))

    def test_type_errors_are_listed(self):
        r = server.parse_test_log(log("""
src/a.ts(3,7): error TS2322: Type 'string' is not assignable to type 'number'.
Found 1 error in src/a.ts:3
"""), "Typecheck")
        self.assertEqual((r["kind"], r["errors"]), ("tsc", 1))
        self.assertTrue(r["failures"][0].startswith("src/a.ts(3,7): error TS2322"))


class Unrecognised(unittest.TestCase):
    def test_returns_none(self):
        self.assertIsNone(server.parse_test_log(log("Building...\nDone in 3s"), "Build"))


class Classification(unittest.TestCase):
    def test_by_job_or_workflow_name(self):
        self.assertTrue(server.is_test_job("quality / Lint", "Deploy"))
        self.assertTrue(server.is_test_job("Build", "PR Checks"))
        self.assertFalse(server.is_test_job("Build & Push Web Image", "Deploy"))

    def test_by_step_command(self):
        steps = [{"name": "Run npm run test --workspace @x/worker"}]
        self.assertTrue(server.is_test_job("Node drainer", "Deploy", steps))

    def test_job_base_strips_reusable_prefix(self):
        self.assertEqual(server.job_base("quality / Typecheck"), "Typecheck")


class Formatting(unittest.TestCase):
    def test_fmt_dur(self):
        self.assertEqual([server.fmt_dur(x) for x in (None, 5, 65, 3725)], ["—", "5s", "1m 05s", "1h 02m"])


if __name__ == "__main__":
    unittest.main()
