"""Leaderboard nicknames: short, plain, and not rude."""

import re

MIN_LENGTH = 2
MAX_LENGTH = 14
_ALLOWED = re.compile(r"^[A-Za-z0-9 _.-]+$")
## Digits and symbols people swap in to sneak a word past a filter.
_LOOKALIKES = str.maketrans({"0": "o", "1": "i", "3": "e", "4": "a", "5": "s", "7": "t", "8": "b", "@": "a", "$": "s"})
## Only words that never sit inside an innocent name: no "rape" (grape) or
## "cock" (peacock). Anything that slips past is hidden from the admin page.
_BLOCKED = (
    "fuck", "shit", "cunt", "bitch", "nigg", "faggot", "pussy", "whore", "slut",
    "nazi", "hitler", "kike", "chink", "retard", "twat", "wank", "porn", "penis",
    "vagina", "asshole", "bastard", "merda", "caralho", "porra",
)


def clean(raw):
    """The nickname to store, or None with the reason it was refused."""
    if not isinstance(raw, str):
        return None, "nickname missing"
    name = " ".join(raw.split())
    if len(name) < MIN_LENGTH or len(name) > MAX_LENGTH:
        return None, "nickname must be %d to %d characters" % (MIN_LENGTH, MAX_LENGTH)
    if not _ALLOWED.match(name):
        return None, "letters, numbers, spaces, dots and dashes only"
    squashed = re.sub(r"[^a-z]", "", name.lower().translate(_LOOKALIKES))
    if any(word in squashed for word in _BLOCKED):
        return None, "pick a different nickname"
    return name, None
