#!/usr/bin/env python3
"""Writes frontier/design/dialogue/town.json: ambient NPC-to-NPC conversations for town life (original writing).

Each conversation is 2-4 lines between two townspeople, A and B, with a voice type per side (casting keys in
design/dialogue/voices.json) and the places it fits. tools/audio/voices.py renders the flat "lines" table like any
other dialogue (ids town_cNN_k); src/ai/population.gd reads "conversations" and plays them on pairs on porches, at
the bar, at tables and on the street, with a talk gesture per line, heads turned to each other and subtitles when
Ruth is within 8 m. Run: python3 frontier/tools/town_dialogue.py
"""
import json
import os

# (id, A voice, B voice, places, [(side, line, emotion)])
CONVOS = [
    ("c01", "man_old", "man_town", ["porch", "street"], [
        ("a", "Sky's been promising rain since August.", "tired"),
        ("b", "Sky's a liar. Ask any man who planted corn.", "dry"),
        ("a", "I planted beans. Beans don't care.", "amused")]),
    ("c02", "woman_town", "woman_old", ["porch", "street"], [
        ("a", "Did you hear the Meridian people bought the Ellery place?", "tense"),
        ("b", "Bought it, or got it signed over?", "dry"),
        ("a", "Way Martha tells it, there's a difference only on paper.", "sad")]),
    ("c03", "man_rough", "man_town", ["bar", "table"], [
        ("a", "Two bits says the four-ten is late again.", "calm"),
        ("b", "No bet. It's always late. They print the timetable for the comedy.", "amused")]),
    ("c04", "man_town", "man_young", ["street", "porch"], [
        ("a", "You still hauling for the mill?", "calm"),
        ("b", "When they pay. Last week they paid in promises.", "dry"),
        ("a", "Promises eat cheap. Feed your horse on 'em and see.", "dry")]),
    ("c05", "woman_old", "man_old", ["porch"], [
        ("a", "That new preacher talks like a man who's never been hungry.", "dry"),
        ("b", "Give him a winter. The Sable teaches humility for free.", "calm")]),
    ("c06", "man_town", "man_rough", ["bar"], [
        ("a", "Feed's up to a dollar ten the hundredweight.", "angry"),
        ("b", "And cattle's down. Somebody in Port Linden is doing sums on us.", "angry"),
        ("a", "Somebody in Port Linden is always doing sums.", "tired")]),
    ("c07", "woman_town", "man_town", ["street", "porch"], [
        ("a", "There's a dance at the church hall Saturday.", "warm"),
        ("b", "I've got two left feet and both of them hurt.", "amused"),
        ("a", "Then you'll fit right in with the fiddler.", "amused")]),
    ("c08", "man_old", "man_rough", ["bar", "table"], [
        ("a", "They say there's silver up past Coldwater still.", "calm"),
        ("b", "They say a lot. Mostly the men who sell picks.", "dry")]),
    ("c09", "man_young", "man_town", ["street", "porch"], [
        ("a", "Sheriff's been riding out to the river every morning.", "tense"),
        ("b", "Then let him. Some things are better watched than talked about.", "tense")]),
    ("c10", "woman_town", "woman_town", ["street", "porch"], [
        ("a", "Hollis has calico in. Real calico, not that sacking.", "warm"),
        ("b", "At what price?", "dry"),
        ("a", "Don't ask the price. Ask to feel it first, then you'll pay.", "amused")]),
    ("c11", "man_rough", "man_old", ["bar"], [
        ("a", "Pour me one for the road.", "tired"),
        ("b", "You said that an hour ago.", "dry"),
        ("a", "It's a long road.", "amused")]),
    ("c12", "man_town", "woman_old", ["porch", "street"], [
        ("a", "Your boy back from the drive yet?", "calm"),
        ("b", "Wrote from the railhead. Says the cattle lost weight and he gained sense.", "warm"),
        ("a", "That's a fair trade, most years.", "warm")]),
    ("c13", "man_old", "man_town", ["table", "bar"], [
        ("a", "You read the Lantern this week?", "calm"),
        ("b", "Fenn's paper? I read it twice. Once to believe it, once to be scared.", "tense")]),
    ("c14", "man_young", "man_rough", ["table", "bar"], [
        ("a", "Deal me in.", "calm"),
        ("b", "With what? You owe the house already.", "dry"),
        ("a", "Then deal me out quiet, so it doesn't notice.", "amused")]),
    ("c15", "woman_old", "woman_town", ["porch"], [
        ("a", "I set bread to rise and the heat near baked it in the bowl.", "tired"),
        ("b", "October, and still the stove's the cool part of the house.", "tired")]),
    ("c16", "man_town", "man_old", ["street", "porch"], [
        ("a", "Water's down another foot at the crossing.", "tense"),
        ("b", "Saw it. You can read the old flood marks on the pilings like a ledger.", "sad"),
        ("a", "And every page of it red.", "dry")]),
    ("c17", "shopkeeper", "woman_town", ["street", "porch"], [
        ("a", "Morning, Mrs. Larkin. Coffee came in on the freight.", "warm"),
        ("b", "Honest coffee, or the kind that's half chicory?", "dry"),
        ("a", "Honest as I am, ma'am.", "amused"),
        ("b", "Then I'll take a pound and watch you weigh it.", "amused")]),
    ("c18", "man_rough", "man_young", ["bar", "street"], [
        ("a", "Stranger in town. Woman, rides a good horse.", "tense"),
        ("b", "Saw her. Wears that iron like she knows what it weighs.", "tense"),
        ("a", "Then mind your manners, and your hands.", "tense")]),
    ("c19", "man_old", "woman_old", ["porch"], [
        ("a", "Forty years I've watched that road.", "calm"),
        ("b", "And what's it brought you?", "warm"),
        ("a", "You, for one. And taxes.", "amused")]),
    ("c20", "man_town", "man_young", ["table", "bar"], [
        ("a", "Land office posted new survey lines on the board.", "tense"),
        ("b", "Lines on paper don't move fences.", "angry"),
        ("a", "No. Men with paper hire men who do.", "tense")]),
    ("c21", "woman_town", "man_old", ["street", "porch"], [
        ("a", "School needs a new stove before the cold.", "calm"),
        ("b", "Pass the hat Sunday. The Lord likes a warm schoolhouse.", "warm")]),
    ("c22", "man_rough", "man_town", ["bar", "table"], [
        ("a", "Whiskey's thinner than last month.", "angry"),
        ("b", "So's your credit.", "dry")]),
]

SPEAKERS = ["man_old", "man_town", "man_rough", "man_young", "woman_town", "woman_old", "shopkeeper"]


def main() -> None:
    out = {
        "note": "Town life: ambient NPC-to-NPC conversations (original writing). Generated by tools/town_dialogue.py; "
                "voiced by tools/audio/voices.py from the flat lines table; played by src/ai/population.gd.",
        "speakers": {s: {"name": "", "voice": s} for s in SPEAKERS},
        "lines": [],
        "conversations": [],
    }
    for cid, a, b, places, lines in CONVOS:
        ids = []
        for i, (side, text, emo) in enumerate(lines):
            lid = "town_%s_%d" % (cid, i + 1)
            out["lines"].append({"id": lid, "speaker": a if side == "a" else b, "line": text, "emotion": emo})
            ids.append([side, lid])
        out["conversations"].append({"id": cid, "a": a, "b": b, "places": places, "lines": ids})
    path = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "design", "dialogue", "town.json")
    with open(path, "w") as f:
        json.dump(out, f, indent=1)
    print("town_dialogue: %d conversations, %d lines -> %s" % (len(out["conversations"]), len(out["lines"]), path))


if __name__ == "__main__":
    main()
