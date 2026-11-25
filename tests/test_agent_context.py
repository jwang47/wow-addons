"""Claude, Codex and Gemini see the same context (AGENTS.md, "Agents and context files").

Codex and Gemini (agy) read AGENTS.md and .agents/skills/; Claude Code reads
CLAUDE.md and .claude/skills/. Each copy must match its source byte for byte.
"""
import pathlib
import unittest

ROOT = pathlib.Path(__file__).resolve().parent.parent
SKIP = {".git", "node_modules", "logs"}


def walk(base):
    for path in sorted(base.rglob("*")):
        if path.is_file() and not SKIP.intersection(path.relative_to(ROOT).parts):
            yield path


class AgentContext(unittest.TestCase):
    def test_claude_md_matches_agents_md(self):
        for agents in walk(ROOT):
            if agents.name != "AGENTS.md":
                continue
            claude = agents.with_name("CLAUDE.md")
            self.assertTrue(claude.exists(), f"no CLAUDE.md beside {agents.relative_to(ROOT)}")
            self.assertEqual(agents.read_bytes(), claude.read_bytes(),
                             f"{claude.relative_to(ROOT)} differs from AGENTS.md: copy AGENTS.md over it")

    def test_every_claude_md_has_agents_md(self):
        for claude in walk(ROOT):
            if claude.name == "CLAUDE.md":
                self.assertTrue(claude.with_name("AGENTS.md").exists(),
                                f"no AGENTS.md beside {claude.relative_to(ROOT)}: AGENTS.md is the source")

    def test_skill_copies_match(self):
        for source, copy in ((".agents", ".claude"), (".claude", ".agents")):
            for skills in ROOT.rglob(f"{source}/skills"):
                if SKIP.intersection(skills.relative_to(ROOT).parts):
                    continue
                twin_root = skills.parent.parent / copy / "skills"
                for path in walk(skills):
                    twin = twin_root / path.relative_to(skills)
                    self.assertTrue(twin.exists(), f"no copy of {path.relative_to(ROOT)} at {twin.relative_to(ROOT)}")
                    self.assertEqual(path.read_bytes(), twin.read_bytes(),
                                     f"{twin.relative_to(ROOT)} differs from {path.relative_to(ROOT)}")


if __name__ == "__main__":
    unittest.main()
