"""The continual-learning loop, with real durable jobs and a fake reviewer."""
import json
from pathlib import Path
import sys
import tempfile
import unittest
from unittest import mock

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import agent_memory as memory
import agent_learning as learning


def events(failed=False):
    return [
        {"type": "session.tool.input.started", "data": {"id": "context", "name": "ii-shell_desktop_context"}},
        {"type": "session.tool.success", "data": {"id": "context", "content": [{"type": "text", "text": "Native QuickShell wallpaper renderer"}]}},
        {"type": "session.tool.input.started", "data": {"id": "apply", "name": "ii-shell_wallpaper_set"}},
        {"type": "session.tool.called", "data": {"id": "apply", "input": {"ref": "/pictures/test.png"}}},
        {"type": "session.tool.failed" if failed else "session.tool.success", "data": {"id": "apply", "content": [
            {"type": "text", "text": "not applied" if failed else '{"requested":true,"configured":true}'},
            {"type": "image", "data": "must-not-be-stored"}]}},
    ]


class LearningLoop(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory(); self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name)
        for key, value in (("STATE", self.root / "state"), ("FACTS", self.root / "state/memory.json"), ("SKILLS", self.root / "skills")):
            patch = mock.patch.object(memory, key, value); patch.start(); self.addCleanup(patch.stop)
        self.config = {"enabled": True, "limit": 40, "skills": True, "autoLearn": True, "retrieveHistory": True, "maxInputTokens": 12000}
        patch = mock.patch.object(memory, "policy", side_effect=lambda options=None: {**self.config, **(options or {})}); patch.start(); self.addCleanup(patch.stop)
        self.online = mock.patch.object(memory, "online_policy_allowed", return_value=True)
        self.online_status = self.online.start()
        self.addCleanup(self.online.stop)
        self.body = {"engine": "codex", "model": {"modelID": "default"}, "chatId": "source-session",
                     "text": "Change my wallpaper using the existing native desktop controls.",
                     "tools": ["wallpaper_set", "desktop_context", "memory_search", "remember_fact", "skill_search", "skill_save"]}

    def job(self, failed=False, text=None):
        body = {**self.body, "text": text or self.body["text"]}
        ident = learning.enqueue(body, "Task finished", events(failed), start=False)
        return memory.read_json(learning.directory() / (ident + ".json"))

    def teach(self, job):
        memory.skill_save({"name": "native-wallpaper", "description": "Change wallpaper with native controls", "procedure": "Discover the library, apply an exact ref and verify configuration.",
                           "verification": "Read the current configured ref after apply.", "evidence": "Native apply reported requested and configured true.",
                           "triggers": ["wallpaper"], "learningJob": job["id"]})
        return "Updated the native wallpaper skill from the verified result."

    def test_local_policy_pauses_pending_learning(self):
        job = self.job()
        self.online_status.return_value = False
        with mock.patch.object(learning, "perform") as perform:
            learning.drain()
            perform.assert_not_called()
        saved = memory.read_json(learning.directory() / (job["id"] + ".json"))
        self.assertEqual(saved["state"], "pending")

    def test_job_keeps_bounded_actual_evidence_and_not_images(self):
        job = self.job()
        self.assertEqual(job["sessionId"], "source-session")
        self.assertEqual(job["evidence"][-1]["tool"], "wallpaper_set")
        self.assertIn("configured", job["evidence"][-1]["result"])
        self.assertNotIn("must-not-be-stored", json.dumps(job))
        self.assertEqual(job["state"], "pending")

    def test_reviewer_has_only_knowledge_tools_and_cannot_recurse(self):
        review = learning.review_body(self.job())
        self.assertTrue(review["learningReview"])
        self.assertTrue(review["learningVerified"])
        self.assertNotIn("wallpaper_set", review["tools"])
        self.assertNotIn("run_shell_command", review["tools"])
        self.assertIsNone(learning.enqueue(review, "done", events(), start=False))

    def test_context_success_does_not_turn_a_failed_action_into_verified_work(self):
        self.assertFalse(learning.review_body(self.job(failed=True))["learningVerified"])

    def test_casual_conversation_does_not_spend_a_learning_review(self):
        self.body["text"] = "Thanks!"
        self.assertIsNone(learning.enqueue(self.body, "You're welcome", [], start=False))

    def test_read_only_lookup_does_not_spend_a_learning_review(self):
        self.body["text"] = "How many windows are open?"
        lookup = [
            {"type": "session.tool.input.started", "data": {"id": "w", "name": "ii-shell_windows_list"}},
            {"type": "session.tool.success", "data": {"id": "w", "content": [{"type": "text", "text": "3 windows"}]}},
        ]
        self.assertIsNone(learning.enqueue(self.body, "3", lookup, start=False))

    def test_same_task_is_not_reviewed_twice_in_a_week(self):
        self.job()
        self.assertIsNone(learning.enqueue(self.body, "Task finished", events(), start=False))

    def test_denied_knowledge_writes_are_not_added_by_the_worker(self):
        self.body["tools"] = ["wallpaper_set", "desktop_context"]
        self.assertIsNone(learning.enqueue(self.body, "done", events(), start=False))

    def test_durable_review_updates_retrievable_skill_then_improves_its_version(self):
        self.job(text="Change my wallpaper using the existing native desktop controls.")
        with mock.patch.object(learning, "perform", side_effect=self.teach):
            learning.drain()
        found = memory.search("wallpaper", ("skill",))
        self.assertEqual(found[0]["metadata"]["version"], 1)
        self.assertTrue(found[0]["metadata"]["learningJob"].startswith("learn_"))
        self.job(text="Update my wallpaper again with the native renderer.")
        with mock.patch.object(learning, "perform", side_effect=self.teach):
            learning.drain()
        self.assertEqual(memory.search("wallpaper", ("skill",))[0]["metadata"]["version"], 2)
        next_turn = memory.prepare({"text": "change wallpaper", "prior": [], "tools": ["wallpaper_set"]})
        self.assertIn("native-wallpaper", next_turn["instructions"])
        self.assertEqual(memory.read_json(memory.STATE / "learning-status.json")["counts"]["completed"], 2)

    def test_failed_review_is_visible_and_does_not_spin(self):
        job = self.job()
        with mock.patch.object(learning, "perform", side_effect=RuntimeError("account limit")) as perform:
            learning.drain(); learning.drain()
            self.assertEqual(perform.call_count, 1)
        saved = memory.read_json(learning.directory() / (job["id"] + ".json"))
        self.assertEqual(saved["state"], "failed")
        self.assertEqual(memory.read_json(memory.STATE / "learning-status.json")["state"], "failed")

    def test_worker_recovers_a_review_interrupted_by_restart(self):
        job = self.job(); job.update(state="reviewing", attempts=1)
        memory.atomic(learning.directory() / (job["id"] + ".json"), job)
        with mock.patch.object(learning, "perform", side_effect=self.teach): learning.drain()
        saved = memory.read_json(learning.directory() / (job["id"] + ".json"))
        self.assertEqual(saved["state"], "completed")
        self.assertEqual(saved["attempts"], 2)

    def test_disabling_learning_before_review_prevents_writes(self):
        self.job(); self.config["autoLearn"] = False
        with mock.patch.object(learning, "perform") as perform:
            learning.drain(); perform.assert_not_called()
        self.assertEqual(list(memory.SKILLS.glob("*/SKILL.md")), [])

    def test_draft_failure_lesson_is_reviewable_but_not_replayed_as_working_skill(self):
        memory.skill_save({"name": "failed-wallpaper", "description": "Wallpaper approach needing repair", "procedure": "Do not repeat the failed approach without validation.",
                           "verification": "Apply with the native API and inspect the result.", "evidence": "The previous command failed.", "status": "draft"})
        self.assertEqual(memory.search("wallpaper", ("skill",)), [])
        self.assertEqual(len(memory.search("wallpaper", ("skill",), include_drafts=True)), 1)


if __name__ == "__main__": unittest.main()
