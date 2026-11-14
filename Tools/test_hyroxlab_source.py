"""The AltStore listing names one build and one file, and they must be the same build.

AltStore refuses a download whose build number differs from the listing it holds. A listing that
points at a file which a later build replaces fails exactly that way on any phone that has not
refreshed yet, which is what happened when the listing pointed at a rolling `latest` release.
"""
import unittest

import hyroxlab_source as src

REPO = "someone/luma"


def listing(build_no: str, url: str, notes=None) -> dict:
    return src.build(REPO, "12.1.0", build_no, "ie.example.luma", 24_000_000, "abc1234", url, notes)


def own_url(build_no: str) -> str:
    return f"https://github.com/{REPO}/releases/download/{src.release_tag(build_no)}/Luma.ipa"


class ListingNamesItsOwnBuild(unittest.TestCase):
    def test_listing_points_at_the_release_of_the_build_it_names(self):
        version = listing("12", own_url("12"))["apps"][0]["versions"][0]
        self.assertEqual(version["buildVersion"], "12")
        self.assertEqual(version["downloadURL"], own_url("12"))
        self.assertIn("/releases/download/build-12/", version["downloadURL"])

    def test_a_rolling_file_is_refused(self):
        rolling = f"https://github.com/{REPO}/releases/download/latest/HYROXLab-ios.ipa"
        with self.assertRaises(ValueError):
            listing("12", rolling)

    def test_another_builds_file_is_refused(self):
        with self.assertRaises(ValueError):
            listing("12", own_url("11"))
        # A tag that merely starts with this build's number is another build.
        with self.assertRaises(ValueError):
            listing("1", own_url("12"))

    def test_two_builds_never_share_a_download(self):
        urls = {listing(n, own_url(n))["apps"][0]["versions"][0]["downloadURL"] for n in ("10", "11", "12")}
        self.assertEqual(len(urls), 3)


class WhatsNew(unittest.TestCase):
    def test_notes_are_shown_after_the_build_number_on_one_line(self):
        version = listing("12", own_url("12"), "Each build has its\nown download link.\n")["apps"][0]["versions"][0]
        self.assertEqual(version["localizedDescription"], "Build 12. Each build has its own download link.")

    def test_without_notes_the_commit_is_named(self):
        for empty in (None, "", "  \n"):
            version = listing("12", own_url("12"), empty)["apps"][0]["versions"][0]
            self.assertEqual(version["localizedDescription"], "Build 12 from commit abc1234.")


if __name__ == "__main__":
    unittest.main()
