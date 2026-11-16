"""Facts, skill learning, scoped recall and context budgeting on real local files."""
import json
import os
from pathlib import Path
import sqlite3
import sys
import tempfile
import unittest
from unittest import mock

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import agent_memory as memory
import opencode_bridge as bridge


class Knowledge(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.state = self.root / "state"
        self.skills = self.root / "skills"
        self.config = {"enabled": True, "limit": 40, "skills": True, "autoLearn": True, "retrieveHistory": True, "maxInputTokens": 12000}
        for key, value in (("STATE", self.state), ("FACTS", self.state / "memory.json"), ("SKILLS", self.skills)):
            patch = mock.patch.object(memory, key, value); patch.start(); self.addCleanup(patch.stop)
        patch = mock.patch.object(memory, "policy", side_effect=lambda options=None: {**self.config, **(options or {})})
        patch.start(); self.addCleanup(patch.stop)

    def chat(self, ident="one", text="We chose the native wallpaper pipeline", project=""):
        memory.atomic(self.state / "sessions" / (ident + ".json"), {"title": "Desktop setup", "projectId": project,
            "messages": [{"id": "question", "role": "user", "content": text},
                         {"id": "answer", "role": "assistant", "content": "Verified successfully."}]})

    def skill(self, **args):
        return memory.skill_save({"name": "native-wallpaper", "description": "Change wallpaper through QuickShell",
            "procedure": "Use desktop_context, wallpaper_search and wallpaper_set.", "triggers": ["wallpaper", "background"],
            "verification": "Check the configured path; inspect the screen if needed.", "evidence": "Native apply returned requested and configured true.", **args})

    def test_fact_update_replaces_one_key_and_survives_reopening_index(self):
        first = memory.remember({"fact": "My editor is Vim", "key": "editor"})
        second = memory.remember({"fact": "My editor is Emacs", "key": "editor"})
        self.assertEqual(first["fact"]["id"], second["fact"]["id"])
        self.assertEqual(len(memory.facts()), 1)
        self.assertEqual(memory.search("editor")[0]["content"], "My editor is Emacs")
        self.assertEqual(memory.search("Vim"), [])

    def test_multilingual_fact_retrieval(self):
        memory.remember({"fact": "أفضل التحدث بالعربية", "key": "language"})
        self.assertIn("بالعربية", memory.search("بالعربية")[0]["content"])

    def test_project_memory_does_not_leak_to_another_project(self):
        memory.remember({"fact": "Project Alpha uses Rust", "projectId": "alpha"})
        memory.remember({"fact": "I prefer concise answers"})
        self.assertEqual(memory.search("Rust", project="beta"), [])
        self.assertEqual(len(memory.search("Rust", project="alpha")), 1)
        self.assertEqual(len(memory.search("concise", project="beta")), 1)

    def test_forgetting_removes_active_fact_and_quoted_historical_recall(self):
        fact = memory.remember({"fact": "My private project name is Tulip"})["fact"]
        self.chat(text="Yesterday I said: My private project name is Tulip")
        self.assertTrue(memory.search("Tulip", ("conversation",)))
        memory.forget({"id": fact["id"]})
        self.assertEqual(memory.search("Tulip", ("fact", "conversation")), [])
        self.assertTrue(list((self.state / "knowledge-history").glob("*.json")))

    def test_explicit_remember_can_restore_a_previously_forgotten_fact(self):
        fact = memory.remember({"fact": "My editor is Vim"})["fact"]
        memory.forget({"id": fact["id"]})
        memory.remember({"fact": fact["text"]})
        self.assertEqual(len(memory.search("Vim")), 1)

    def test_manual_fact_file_edits_and_deletions_update_the_index(self):
        memory.remember({"fact": "Prefer blue wallpapers"})
        self.assertTrue(memory.search("blue"))
        memory.atomic(memory.FACTS, {"schema": 1, "facts": []})
        self.assertEqual(memory.search("blue"), [])

    def test_disabled_memory_refuses_writes_and_does_not_search(self):
        self.config["enabled"] = False
        with self.assertRaisesRegex(ValueError, "disabled"):
            memory.remember({"fact": "should not be stored"})
        self.assertEqual(memory.search("anything"), [])
        self.assertFalse(memory.FACTS.exists())

    def test_secret_values_are_not_saved(self):
        with self.assertRaisesRegex(ValueError, "secret"):
            memory.remember({"fact": "api_key=sk-thisisasecretvalue1234567890"})
        self.assertFalse(memory.FACTS.exists())

    def test_skill_is_reviewable_versioned_and_requires_success_evidence(self):
        first = self.skill()
        self.assertTrue(Path(first["path"]).is_file())
        self.assertIn("## Verification", Path(first["path"]).read_text())
        self.assertEqual(self.skill(procedure="Updated verified procedure")["skill"]["version"], 2)
        self.assertTrue(list((self.state / "knowledge-history").glob("*.json")))
        with self.assertRaises(ValueError):
            self.skill(evidence="")

    def test_skill_retrieval_and_forgetting_remove_stale_index_entries(self):
        self.skill()
        self.assertTrue(memory.search("wallpaper", ("skill",)))
        memory.forget({"id": "skill:native-wallpaper"})
        self.assertEqual(memory.search("wallpaper", ("skill",)), [])
        self.assertEqual(json.loads((self.skills / "index.json").read_text())["skills"], [])

    def test_skill_names_cannot_escape_the_library(self):
        with self.assertRaises(ValueError):
            self.skill(name="../../outside")

    def test_history_search_has_message_references_and_removes_deleted_chats(self):
        self.chat()
        row = memory.search("wallpaper", ("conversation",))[0]
        self.assertEqual(row["metadata"]["sessionId"], "one")
        self.assertEqual(row["metadata"]["messageId"], "question")
        (self.state / "sessions/one.json").unlink()
        self.assertEqual(memory.search("wallpaper", ("conversation",)), [])

    def test_history_retention_is_not_applied_to_another_project(self):
        self.chat(project="other")
        self.assertEqual(memory.search("wallpaper", ("conversation",), project="here"), [])

    def test_context_retrieves_relevant_facts_and_skill_without_all_memory(self):
        memory.remember({"fact": "Prefer dark wallpaper"})
        memory.remember({"fact": "Favourite fruit is kiwi"})
        self.skill()
        body = memory.prepare({"text": "change wallpaper", "tools": ["wallpaper_set"], "prior": []})
        self.assertIn("Prefer dark wallpaper", body["instructions"])
        self.assertIn("native-wallpaper", body["instructions"])
        self.assertNotIn("kiwi", body["instructions"])

    def test_bounded_replay_retains_latest_complete_turns_and_does_not_modify_source(self):
        prior = [{"role": "user" if i % 2 == 0 else "assistant", "text": "wallpaper " + str(i) + "x"*1800} for i in range(80)]
        body = {"text": "continue wallpaper", "tools": [], "prior": prior}
        result = memory.prepare(body)
        self.assertLess(len(result["prior"]), len(prior))
        self.assertEqual(result["prior"][-1], prior[-1])
        self.assertEqual(result["prior"][0]["role"], "user")
        self.assertEqual(len(body["prior"]), 80)
        self.assertIn("older messages were omitted", result["instructions"])
        self.assertLess(result["contextStats"]["estimatedInputTokens"], 12000)

    def test_oversized_current_message_is_refused_instead_of_silently_truncated(self):
        with self.assertRaisesRegex(ValueError, "budget"):
            memory.prepare({"text": "x"*100000})

    def test_corrupt_knowledge_does_not_break_new_chat(self):
        memory.atomic(memory.FACTS, "{broken")
        result = memory.prepare({"text": "hello", "tools": ["memory_search"]})
        self.assertIn("unavailable", result["instructions"])

    def test_large_attachment_is_marked_as_excerpts_and_relevant_part_selected(self):
        path = self.root / "attached.txt"
        path.write_text("Unrelated material. "*2000 + "\nThe wallpaper command is wallpaper_set.\n")
        notes, images = bridge.attachment_parts([{"kind": "text", "path": str(path), "name": path.name}], 2500, "wallpaper")
        self.assertIn("selected excerpts", notes)
        self.assertIn("wallpaper_set", notes)
        self.assertLess(len(notes), 5000)
        self.assertEqual(images, [])


if __name__ == "__main__":
    unittest.main()
